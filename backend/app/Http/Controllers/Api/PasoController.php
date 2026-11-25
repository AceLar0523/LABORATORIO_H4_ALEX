<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use App\Models\Paso;
use App\Models\Vehiculo;
use App\Models\Tarifa;
use App\Models\Alerta;
use App\Models\Caseta;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;
use Illuminate\Support\Facades\DB;

class PasoController extends Controller
{
    public function index(Request $request)
    {
        $query = Paso::with(['caseta', 'usuario', 'alertas'])->orderBy('created_at', 'desc');

        if ($request->has('estado')) {
            $query->where('estado', $request->input('estado'));
        }

        return response()->json($query->paginate(20));
    }

    public function registrarFrame(Request $request)
    {
        $request->validate([
            'frame' => 'nullable|image|max:10240',
            'frame_base64' => 'nullable|string',
            'caseta_id' => 'nullable|exists:casetas,id',
        ]);

        $inferenceUrl = rtrim(env('INFERENCE_URL', 'http://127.0.0.1:8000'), '/');
        $casetaId = $request->input('caseta_id', 1);
        $usuario = $request->user();

        $imageData = null;
        $imageExtension = 'jpg';

        if ($request->hasFile('frame')) {
            $file = $request->file('frame');
            $imageData = file_get_contents($file->getRealPath());
            $imageExtension = $file->getClientOriginalExtension() ?: 'jpg';
        } elseif ($request->filled('frame_base64')) {
            $base64 = $request->input('frame_base64');
            if (preg_match('/^data:image\/(\w+);base64,/', $base64, $type)) {
                $base64 = substr($base64, strpos($base64, ',') + 1);
                $imageExtension = strtolower($type[1]);
            }
            $imageData = base64_decode($base64);
        }

        if (!$imageData) {
            return response()->json(['success' => false, 'message' => 'No se proporcionó imagen válida'], 400);
        }

        $filename = 'evidencia_' . time() . '_' . Str::random(6) . '.' . $imageExtension;
        Storage::disk('public')->put('evidencias/' . $filename, $imageData);
        $imagenUrl = '/storage/evidencias/' . $filename;

        $placaDetectada = 'SIN_PLACA';
        $confianzaOcr = 0.00;
        $categoria = 'auto';
        $ejes = 2;
        $pasajeros = 0;
        $latenciaMs = 0.00;

        // Llamar exclusivamente al motor de inferencia real en RunPod (M1 + M2 + M3 + M4)
        $aiResolved = false;
        try {
            $response = Http::timeout(20)
                ->attach('file', $imageData, $filename)
                ->post($inferenceUrl . '/predict');

            if ($response->successful()) {
                $aiData = $response->json();
                if (is_array($aiData)) {
                    $placaRaw = trim((string)($aiData['placa'] ?? ''));
                    $placaDetectada = $placaRaw !== '' ? $placaRaw : 'SIN_PLACA';
                    $confianzaOcr = floatval($aiData['confianza'] ?? 0.00);
                    $categoria = strtolower((string)($aiData['categoria'] ?? 'auto'));
                    $ejes = intval($aiData['ejes'] ?? 2);
                    $pasajeros = intval($aiData['pasajeros'] ?? 0);
                    $latenciaMs = floatval($aiData['latencia_ms'] ?? 0.00);
                    $aiResolved = true;
                }
            }
        } catch (\Exception $e) {
            \Log::warning('Error conectando con RunPod en PasoController: ' . $e->getMessage());
        }

        if (!$aiResolved) {
            return response()->json([
                'success' => false,
                'message' => 'El motor de inferencia en RunPod no respondió. Verifica que el Pod esté en línea y con el puerto 8000 expuesto.',
                'inference_url' => $inferenceUrl,
            ], 503);
        }

        $placaNormalizada = strtoupper(preg_replace('/[^A-Za-z0-9]/', '', $placaDetectada));

        $tarifa = Tarifa::where('categoria', $categoria)->where('ejes', $ejes)->first();
        if (!$tarifa) {
            $tarifa = Tarifa::where('categoria', $categoria)->first();
        }
        $monto = $tarifa ? $tarifa->monto : 10.00;

        $vehiculo = Vehiculo::where('placa', $placaNormalizada)->first();
        $alertaGenerada = null;

        if ($vehiculo) {
            $estado = 'Registrada y con paso';
            if ($vehiculo->saldo < $monto) {
                $alertaGenerada = Alerta::create([
                    'tipo' => 'sin_saldo',
                    'mensaje' => "Vehículo {$vehiculo->placa} pasó con saldo insuficiente (Saldo: {$vehiculo->saldo}, Tarifa: {$monto})",
                    'atendida' => false,
                ]);
            } else {
                $vehiculo->decrement('saldo', $monto);
            }
        } else {
            $estado = 'Identificada no registrada';
            $alertaGenerada = Alerta::create([
                'tipo' => 'placa_no_registrada',
                'mensaje' => "Placa no registrada detectada en caseta: {$placaNormalizada}",
                'atendida' => false,
            ]);
        }

        $paso = Paso::create([
            'placa_leida' => $placaDetectada,
            'placa_normalizada' => $placaNormalizada,
            'confianza_ocr' => $confianzaOcr,
            'categoria_detectada' => $categoria,
            'ejes_detectados' => $ejes,
            'monto' => $monto,
            'caseta_id' => $casetaId,
            'usuario_id' => $usuario ? $usuario->id : null,
            'imagen_url' => $imagenUrl,
            'estado' => $estado,
            'pasajeros' => $pasajeros,
        ]);

        if ($alertaGenerada) {
            $alertaGenerada->update(['paso_id' => $paso->id]);
        }

        return response()->json([
            'success' => true,
            'paso' => $paso->load('caseta', 'alertas'),
            'vehiculo' => $vehiculo,
            'latencia_ms' => $latenciaMs,
            'alerta' => $alertaGenerada,
        ], 201);
    }

    /**
     * Resumen ultrarrápido optimizado en una sola consulta agregada
     */
    public function resumenGeneral()
    {
        // 1. Obtener métricas agregadas en 1 sola consulta
        $metrics = DB::selectOne("
            SELECT 
                COUNT(*) as total_pasos, 
                COALESCE(SUM(monto), 0) as recaudacion_hoy 
            FROM pasos
        ");

        $alertasPendientes = Alerta::where('atendida', false)->count();

        // 2. Obtener últimos pasos y alertas
        $ultimosPasos = Paso::with(['caseta'])->orderBy('id', 'desc')->take(10)->get();
        $ultimasAlertas = Alerta::orderBy('id', 'desc')->take(10)->get();

        return response()->json([
            'total_pasos' => (int)($metrics->total_pasos ?? 0),
            'recaudacion_hoy' => round((float)($metrics->recaudacion_hoy ?? 0), 2),
            'alertas_pendientes' => $alertasPendientes,
            'ultimos_pasos' => $ultimosPasos,
            'ultimas_alertas' => $ultimasAlertas,
            'timestamp' => now()->toIso8601String(),
        ]);
    }
}
