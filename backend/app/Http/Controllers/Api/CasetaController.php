<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use App\Models\Caseta;
use App\Models\Paso;
use App\Models\Alerta;
use App\Models\Tarifa;
use Illuminate\Support\Facades\Http;

class CasetaController extends Controller
{
    public function index()
    {
        return response()->json(Caseta::all());
    }

    /**
     * GET /api/v1/casetas/{id}/resumen
     */
    public function resumen($id)
    {
        $caseta = Caseta::findOrFail($id);
        $hoy = now()->startOfDay();

        $pasosHoy = Paso::where('caseta_id', $id)->where('created_at', '>=', $hoy)->get();
        $conteoHoy = $pasosHoy->count();
        $recaudacionHoy = $pasosHoy->sum('monto');

        return response()->json([
            'success' => true,
            'caseta' => $caseta,
            'conteo_hoy' => $conteoHoy,
            'recaudacion_hoy' => round($recaudacionHoy, 2),
            'fecha' => now()->toDateString(),
        ]);
    }

    /**
     * GET /api/v1/estado/inferencia
     * Verificación REAL y DINÁMICA de cada componente:
     * - Motor FastAPI (M1, M2, M3)
     * - Ollama LLM
     */
    public function estadoInferencia()
    {
        $inferenceUrl = rtrim(env('INFERENCE_URL', 'http://127.0.0.1:8000'), '/');
        $ollamaUrl = rtrim(env('OLLAMA_URL', 'http://127.0.0.1:11434'), '/');

        $t0 = microtime(true);
        $statusInferencia = 'offline';
        $detallesModelos = null;

        // 1. Probar salud real del motor FastAPI (timeout tolerante para RunPod HTTPS proxy)
        try {
            $resp = Http::timeout(5)->get($inferenceUrl . '/');
            $data = $resp->json();
            if ($resp->successful() && is_array($data) && isset($data['models'])) {
                $statusInferencia = 'online';
                $detallesModelos = $data;
            }
        } catch (\Exception $e) {
            $statusInferencia = 'offline';
        }

        // 2. Probar salud real de Ollama LLM (directo o vía estado reportado por proxy FastAPI)
        $statusOllama = 'offline';
        try {
            $respOllama = Http::timeout(3)->get($ollamaUrl . '/api/tags');
            if ($respOllama->successful()) {
                $statusOllama = 'online';
            }
        } catch (\Exception $e) {
            $statusOllama = 'offline';
        }

        if ($statusOllama !== 'online' && !empty($detallesModelos['ollama_online'])) {
            $statusOllama = 'online';
        }

        $latency = round((microtime(true) - $t0) * 1000, 2);

        $isOnline = ($statusInferencia === 'online');

        return response()->json([
            'status' => $statusInferencia,
            'url' => $inferenceUrl,
            'latencia_ms' => $latency,
            'modelos' => [
                'm1_detector' => $detallesModelos['models']['m1_detector'] ?? false,
                'm1_ocr' => $detallesModelos['models']['m1_ocr'] ?? false,
                'm2_segmentation' => $detallesModelos['models']['m2_segmentation'] ?? false,
                'm3_keypoints' => $detallesModelos['models']['m3_keypoints'] ?? false,
                'm4_passengers' => $detallesModelos['models']['m4_passengers'] ?? false,
                'ollama_llm' => ($statusOllama === 'online'),
            ],
            'ollama_status' => $statusOllama,
            'ollama_url' => $ollamaUrl,
            'detalles' => $detallesModelos,
        ]);
    }

    /**
     * Listado de alertas
     */
    public function alertas(Request $request)
    {
        $query = Alerta::with('paso')->orderBy('created_at', 'desc');
        if ($request->has('atendida')) {
            $query->where('atendida', filter_var($request->input('atendida'), FILTER_VALIDATE_BOOLEAN));
        }
        return response()->json($query->paginate(20));
    }

    public function atenderAlerta($id)
    {
        $alerta = Alerta::findOrFail($id);
        $alerta->update(['atendida' => true]);
        return response()->json(['success' => true, 'alerta' => $alerta]);
    }

    /**
     * Listado de Tarifas
     */
    public function tarifas()
    {
        return response()->json(Tarifa::orderBy('categoria')->orderBy('ejes')->get());
    }
}
