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
    private function autorizarAdmin(Request $request): void
    {
        $usuario = $request->user();
        if (!$usuario || $usuario->rol !== 'administrador') {
            abort(response()->json([
                'success' => false,
                'message' => 'Se requieren permisos de administrador para eliminar registros de pasos.',
            ], 403));
        }
    }

    public function index(Request $request)
    {
        $query = Paso::with(['caseta', 'usuario', 'alertas'])
            ->orderBy('created_at', 'desc')
            ->orderBy('id', 'desc');

        if ($request->filled('estado')) {
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
            'modo_live' => 'nullable|boolean',
            'solo_preview' => 'nullable|boolean',
            'cooldown_segundos' => 'nullable|integer|min:3|max:120',
        ]);

        $inferenceUrl = rtrim((string) config('services.inference.url', ''), '/');
        if ($inferenceUrl === '') {
            return response()->json([
                'success' => false,
                'message' => 'INFERENCE_URL no está configurado en el servidor.',
            ], 503);
        }

        $casetaId = $request->input('caseta_id', 1);
        $usuario = $request->user();
        $modoLive = $request->boolean('modo_live');
        $soloPreview = $request->boolean('solo_preview');
        $cooldownSegundos = (int) $request->input('cooldown_segundos', 20);

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

        $placaDetectada = 'SIN_PLACA';
        $confianzaOcr = 0.00;
        $categoria = 'auto';
        $ejes = 2;
        $pasajeros = 0;
        $latenciaMs = 0.00;
        $aiData = [];

        // Llamar al motor de inferencia en RunPod antes de persistir evidencia
        $aiResolved = false;
        try {
            $response = Http::timeout(20)
                ->attach('file', $imageData, $filename)
                ->post($inferenceUrl . '/predict');

            if ($response->successful()) {
                $parsed = $response->json();
                if (is_array($parsed)) {
                    $aiData = $parsed;
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
        $placaValida = $placaNormalizada !== ''
            && !in_array($placaNormalizada, ['SINPLACA', 'NOLEIBLE', 'ILEGIBLE', 'NONE', 'NULL'], true)
            && strlen($placaNormalizada) >= 5
            && preg_match('/[A-Z]/', $placaNormalizada) === 1
            && preg_match('/\d/', $placaNormalizada) === 1;

        $detalles = is_array($aiData['detalles'] ?? null) ? $aiData['detalles'] : [];
        $vehiculosDetectados = is_array($aiData['vehiculos'] ?? null) ? $aiData['vehiculos'] : [];
        $totalVehiculos = (int) ($detalles['m2']['total_vehiculos'] ?? count($vehiculosDetectados));

        $hasM2Info = array_key_exists('vehiculo_detectado', $aiData)
            || array_key_exists('m2', $detalles)
            || array_key_exists('vehiculos', $aiData);

        $vehiculoDetectado = array_key_exists('vehiculo_detectado', $aiData)
            ? (bool) $aiData['vehiculo_detectado']
            : ($hasM2Info ? ($totalVehiculos > 0 && $categoria !== 'ninguno') : ($categoria !== 'ninguno' && $placaValida));

        $areaRelativa = null;
        $imgSize = $aiData['imagen_size'] ?? null;
        $m2Bbox = $detalles['m2']['bbox'] ?? null;
        if (is_array($imgSize) && count($imgSize) >= 2 && is_array($m2Bbox) && count($m2Bbox) >= 4) {
            $imgArea = max(1.0, (float) $imgSize[0] * (float) $imgSize[1]);
            $boxArea = max(0.0, ((float) $m2Bbox[2] - (float) $m2Bbox[0]) * ((float) $m2Bbox[3] - (float) $m2Bbox[1]));
            $areaRelativa = $boxArea / $imgArea;
        }

        $tarifa = ($vehiculoDetectado && $categoria !== 'ninguno')
            ? (Tarifa::where('categoria', $categoria)->where('ejes', $ejes)->first()
                ?? Tarifa::where('categoria', $categoria)->first())
            : null;
        $monto = $tarifa ? $tarifa->monto : ($vehiculoDetectado ? 5.00 : 0.00);

        $deteccion = [
            'vehiculo_detectado' => $vehiculoDetectado,
            'area_relativa' => $areaRelativa !== null ? round($areaRelativa, 3) : null,
            'imagen_size' => $imgSize,
            'placa' => $placaDetectada,
            'placa_normalizada' => $placaNormalizada,
            'confianza_ocr' => $confianzaOcr,
            'categoria' => $categoria,
            'ejes' => $ejes,
            'pasajeros' => $pasajeros,
            'monto' => (float) $monto,
            'latencia_ms' => $latenciaMs,
            'm1' => $detalles['m1'] ?? null,
            'm2' => $detalles['m2'] ?? null,
            'm3' => $detalles['m3'] ?? null,
            'm4' => $detalles['m4'] ?? null,
            'vehiculos' => $vehiculosDetectados,
        ];

        $vehiculo = ($vehiculoDetectado && $placaValida)
            ? Vehiculo::where('placa', $placaNormalizada)->first()
            : null;

        if ($soloPreview) {
            return response()->json([
                'success' => true,
                'registrado' => false,
                'motivo' => 'solo_preview',
                'latencia_ms' => $latenciaMs,
                'deteccion' => $deteccion,
            ], 200);
        }

        // Lógica de caseta real en Modo Live: solo registra si M2 detecta un vehículo cercano con placa clara y sin duplicado
        if ($modoLive) {
            if (!$vehiculoDetectado) {
                return response()->json([
                    'success' => true,
                    'registrado' => false,
                    'motivo' => 'sin_vehiculo',
                    'latencia_ms' => $latenciaMs,
                    'deteccion' => $deteccion,
                ], 200);
            }

            if ($areaRelativa !== null && $areaRelativa < 0.08) {
                return response()->json([
                    'success' => true,
                    'registrado' => false,
                    'motivo' => 'vehiculo_lejano',
                    'latencia_ms' => $latenciaMs,
                    'deteccion' => $deteccion,
                ], 200);
            }

            if (!$placaValida || $confianzaOcr < 0.50) {
                return response()->json([
                    'success' => true,
                    'registrado' => false,
                    'motivo' => 'esperando_placa',
                    'latencia_ms' => $latenciaMs,
                    'deteccion' => $deteccion,
                ], 200);
            }

            $pasoReciente = Paso::where('caseta_id', $casetaId)
                ->where('placa_normalizada', $placaNormalizada)
                ->where('created_at', '>=', now()->subSeconds($cooldownSegundos))
                ->orderByDesc('id')
                ->first();

            if ($pasoReciente) {
                return response()->json([
                    'success' => true,
                    'registrado' => false,
                    'motivo' => 'duplicado_reciente',
                    'paso' => $pasoReciente->load('caseta', 'alertas'),
                    'vehiculo' => $vehiculo,
                    'latencia_ms' => $latenciaMs,
                    'deteccion' => $deteccion,
                ], 200);
            }
        } elseif (!$vehiculoDetectado && !$placaValida) {
            return response()->json([
                'success' => false,
                'message' => 'No se detectó ningún vehículo (M2) en la imagen.',
                'deteccion' => $deteccion,
            ], 422);
        }

        Storage::disk('public')->put('evidencias/' . $filename, $imageData);
        $imagenUrl = '/storage/evidencias/' . $filename;

        $alertaGenerada = null;

        if ($vehiculo) {
            $estado = 'Registrada y con paso';
            if (!$vehiculo->activo) {
                $alertaGenerada = Alerta::create([
                    'tipo' => 'vehiculo_inactivo',
                    'mensaje' => "Vehículo {$vehiculo->placa} se encuentra suspendido/inactivo en el padrón.",
                    'atendida' => false,
                ]);
            } elseif ($vehiculo->saldo < $monto) {
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
            'registrado' => true,
            'motivo' => $modoLive ? 'nuevo_registro' : 'registro_manual',
            'paso' => $paso->load('caseta', 'alertas'),
            'vehiculo' => $vehiculo,
            'latencia_ms' => $latenciaMs,
            'alerta' => $alertaGenerada,
            'deteccion' => $deteccion,
        ], 201);
    }

    /**
     * Resumen optimizado para el panel en tiempo real (métricas de hoy + totales)
     */
    public function resumenGeneral()
    {
        $inicioHoy = now()->startOfDay();

        $metricsTotal = DB::table('pasos')
            ->selectRaw('COUNT(*) as total_pasos, COALESCE(SUM(monto), 0) as recaudacion_total')
            ->first();

        $metricsHoy = DB::table('pasos')
            ->where('created_at', '>=', $inicioHoy)
            ->selectRaw('COUNT(*) as pasos_hoy, COALESCE(SUM(monto), 0) as recaudacion_hoy')
            ->first();

        $alertasPendientes = Alerta::where('atendida', false)->count();
        $vehiculosRegistrados = Vehiculo::count();

        $ultimosPasos = Paso::with(['caseta'])->orderBy('id', 'desc')->take(10)->get();
        $ultimasAlertas = Alerta::orderBy('id', 'desc')->take(10)->get();

        return response()->json([
            'pasos_hoy' => (int) ($metricsHoy->pasos_hoy ?? 0),
            'recaudacion_hoy' => round((float) ($metricsHoy->recaudacion_hoy ?? 0), 2),
            'total_pasos' => (int) ($metricsTotal->total_pasos ?? 0),
            'recaudacion_total' => round((float) ($metricsTotal->recaudacion_total ?? 0), 2),
            'vehiculos_registrados' => $vehiculosRegistrados,
            'alertas_pendientes' => $alertasPendientes,
            'ultimos_pasos' => $ultimosPasos,
            'ultimas_alertas' => $ultimasAlertas,
            'timestamp' => now()->toIso8601String(),
        ]);
    }

    /**
     * DELETE /api/v1/pasos/{id}
     * Elimina un paso erróneo (solo administrador) y reembolsa saldo si fue cobrado.
     */
    public function destroy(Request $request, $id)
    {
        $this->autorizarAdmin($request);
        $paso = Paso::with('alertas')->findOrFail($id);

        $sinCobro = $paso->alertas->contains(
            fn ($a) => in_array($a->tipo, ['sin_saldo', 'vehiculo_inactivo'], true)
        );

        if ($paso->estado === 'Registrada y con paso' && !$sinCobro && !empty($paso->placa_normalizada)) {
            $vehiculo = Vehiculo::where('placa', $paso->placa_normalizada)->first();
            if ($vehiculo && (float) $paso->monto > 0) {
                $vehiculo->increment('saldo', (float) $paso->monto);
            }
        }

        if (!empty($paso->imagen_url) && str_starts_with((string) $paso->imagen_url, '/storage/')) {
            $rel = str_replace('/storage/', '', (string) $paso->imagen_url);
            Storage::disk('public')->delete($rel);
        }

        $paso->alertas()->delete();
        $paso->delete();

        return response()->json([
            'success' => true,
            'message' => 'Registro de paso eliminado correctamente.',
        ]);
    }

    /**
     * DELETE /api/v1/pasos/limpiar/sin-placa
     * Limpia masivamente falsos registros sin placa legible (solo administrador).
     */
    public function limpiarSinPlaca(Request $request)
    {
        $this->autorizarAdmin($request);

        $pasos = Paso::where(function ($q) {
            $q->whereNull('placa_normalizada')
                ->orWhere('placa_normalizada', '')
                ->orWhereIn('placa_normalizada', ['SINPLACA', 'SIN_PLACA', 'NOLEIBLE', 'ILEGIBLE'])
                ->orWhereRaw('LENGTH(placa_normalizada) < 4');
        })->get();

        $count = $pasos->count();
        if ($count > 0) {
            $ids = $pasos->pluck('id')->all();
            foreach ($pasos as $p) {
                if (!empty($p->imagen_url) && str_starts_with((string) $p->imagen_url, '/storage/')) {
                    Storage::disk('public')->delete(str_replace('/storage/', '', (string) $p->imagen_url));
                }
            }
            Alerta::whereIn('paso_id', $ids)->delete();
            Paso::whereIn('id', $ids)->delete();
        }

        return response()->json([
            'success' => true,
            'eliminados' => $count,
            'message' => "Se limpiaron {$count} registro(s) sin placa legible.",
        ]);
    }
}
