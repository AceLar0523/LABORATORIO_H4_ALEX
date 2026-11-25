<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use App\Models\Caseta;
use App\Models\Paso;
use App\Models\Alerta;
use App\Models\Tarifa;
use App\Models\Vehiculo;
use App\Models\User;
use Illuminate\Support\Facades\Http;

class CasetaController extends Controller
{
    private function autorizarAdmin(Request $request): void
    {
        $usuario = $request->user();
        if (!$usuario || $usuario->rol !== 'administrador') {
            abort(response()->json([
                'success' => false,
                'message' => 'Se requieren permisos de administrador para gestionar casetas y tarifas.',
            ], 403));
        }
    }

    public function index()
    {
        return response()->json(Caseta::orderBy('id')->get());
    }

    public function storeCaseta(Request $request)
    {
        $this->autorizarAdmin($request);

        $validated = $request->validate([
            'nombre' => 'required|string|max:120',
            'ubicacion' => 'required|string|max:200',
        ]);

        $caseta = Caseta::create([
            'nombre' => trim($validated['nombre']),
            'ubicacion' => trim($validated['ubicacion']),
        ]);

        return response()->json(['success' => true, 'data' => $caseta], 201);
    }

    public function updateCaseta(Request $request, $id)
    {
        $this->autorizarAdmin($request);
        $caseta = Caseta::findOrFail($id);

        $validated = $request->validate([
            'nombre' => 'required|string|max:120',
            'ubicacion' => 'required|string|max:200',
        ]);

        $caseta->update([
            'nombre' => trim($validated['nombre']),
            'ubicacion' => trim($validated['ubicacion']),
        ]);

        return response()->json(['success' => true, 'data' => $caseta]);
    }

    public function destroyCaseta(Request $request, $id)
    {
        $this->autorizarAdmin($request);
        $caseta = Caseta::findOrFail($id);

        if (Caseta::count() <= 1) {
            return response()->json([
                'success' => false,
                'message' => 'No puedes eliminar la última caseta del sistema.',
            ], 422);
        }

        $caseta->delete();
        return response()->json(['success' => true, 'message' => 'Caseta eliminada con éxito']);
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
     * - Motor FastAPI (M1, M2, M3, M4)
     * - Ollama LLM
     */
    public function estadoInferencia()
    {
        $inferenceUrl = rtrim((string) config('services.inference.url', ''), '/');
        $ollamaUrl = rtrim((string) config('services.ollama.url', ''), '/');

        $t0 = microtime(true);
        $statusInferencia = 'offline';
        $detallesModelos = null;

        // 1. Probar salud real del motor FastAPI (timeout tolerante para RunPod HTTPS proxy)
        if ($inferenceUrl !== '') {
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
        }

        // 2. Probar salud real de Ollama LLM (directo o vía /ollama/tags)
        $statusOllama = 'offline';
        $ollamaModels = [];
        if ($ollamaUrl !== '') {
            $ollamaTagsUrl = str_ends_with($ollamaUrl, '/ollama')
                ? "{$ollamaUrl}/tags"
                : "{$ollamaUrl}/api/tags";
            try {
                $respOllama = Http::timeout(4)->get($ollamaTagsUrl);
                if ($respOllama->successful()) {
                    $tagsData = $respOllama->json();
                    $models = is_array($tagsData) ? ($tagsData['models'] ?? []) : [];
                    $ollamaModels = collect($models)
                        ->map(fn ($m) => is_array($m) ? ($m['name'] ?? ($m['model'] ?? null)) : null)
                        ->filter()
                        ->values()
                        ->all();
                    $statusOllama = count($ollamaModels) > 0 ? 'online' : 'sin_modelo';
                }
            } catch (\Exception $e) {
                $statusOllama = 'offline';
            }
        }

        if ($statusOllama === 'offline' && !empty($detallesModelos['ollama_online'])) {
            $statusOllama = count($ollamaModels) > 0 ? 'online' : 'sin_modelo';
        }

        $latency = round((microtime(true) - $t0) * 1000, 2);

        return response()->json([
            'status' => $statusInferencia,
            'url' => $inferenceUrl !== '' ? $inferenceUrl : 'No configurado',
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
            'ollama_models' => $ollamaModels,
            'ollama_url' => $ollamaUrl !== '' ? $ollamaUrl : 'No configurado',
            'vehiculos_registrados' => Vehiculo::count(),
            'usuarios_autorizados' => User::where('activo', true)->count(),
            'detalles' => $detallesModelos,
        ]);
    }

    /**
     * Listado de alertas
     */
    public function alertas(Request $request)
    {
        $query = Alerta::with('paso')->orderBy('created_at', 'desc')->orderBy('id', 'desc');
        if ($request->has('atendida') && $request->input('atendida') !== '') {
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
     * Escala realista de tarifas de peaje en Bs.
     */
    public static function tarifasPorDefecto(): array
    {
        return [
            ['categoria' => 'moto', 'ejes' => 2, 'monto' => 2.00],
            ['categoria' => 'auto', 'ejes' => 2, 'monto' => 5.00],
            ['categoria' => 'minibus', 'ejes' => 2, 'monto' => 7.00],
            ['categoria' => 'bus', 'ejes' => 2, 'monto' => 12.00],
            ['categoria' => 'bus', 'ejes' => 3, 'monto' => 18.00],
            ['categoria' => 'camion', 'ejes' => 2, 'monto' => 12.00],
            ['categoria' => 'camion', 'ejes' => 3, 'monto' => 18.00],
            ['categoria' => 'camion', 'ejes' => 4, 'monto' => 26.00],
            ['categoria' => 'camion', 'ejes' => 5, 'monto' => 34.00],
            ['categoria' => 'camion', 'ejes' => 6, 'monto' => 42.00],
            ['categoria' => 'trailer', 'ejes' => 4, 'monto' => 28.00],
            ['categoria' => 'trailer', 'ejes' => 5, 'monto' => 36.00],
            ['categoria' => 'trailer', 'ejes' => 6, 'monto' => 45.00],
        ];
    }

    /**
     * Listado y gestión de Tarifas
     */
    public function tarifas()
    {
        return response()->json(Tarifa::orderBy('categoria')->orderBy('ejes')->get());
    }

    public function restaurarTarifas(Request $request)
    {
        $this->autorizarAdmin($request);

        foreach (self::tarifasPorDefecto() as $t) {
            Tarifa::updateOrCreate(
                ['categoria' => $t['categoria'], 'ejes' => $t['ejes']],
                ['monto' => $t['monto']]
            );
        }

        return response()->json([
            'success' => true,
            'message' => 'Tarifas realistas restauradas correctamente.',
            'data' => Tarifa::orderBy('categoria')->orderBy('ejes')->get(),
        ]);
    }

    public function storeTarifa(Request $request)
    {
        $this->autorizarAdmin($request);

        $validated = $request->validate([
            'categoria' => 'required|string|max:30',
            'ejes' => 'required|integer|min:1|max:12',
            'monto' => 'required|numeric|min:0',
        ]);

        $categoria = strtolower(trim($validated['categoria']));
        $ejes = (int) $validated['ejes'];

        if (Tarifa::where('categoria', $categoria)->where('ejes', $ejes)->exists()) {
            return response()->json([
                'success' => false,
                'message' => "Ya existe una tarifa para {$categoria} con {$ejes} ejes.",
            ], 422);
        }

        $tarifa = Tarifa::create([
            'categoria' => $categoria,
            'ejes' => $ejes,
            'monto' => $validated['monto'],
        ]);

        return response()->json(['success' => true, 'data' => $tarifa], 201);
    }

    public function updateTarifa(Request $request, $id)
    {
        $this->autorizarAdmin($request);
        $tarifa = Tarifa::findOrFail($id);

        $validated = $request->validate([
            'categoria' => 'required|string|max:30',
            'ejes' => 'required|integer|min:1|max:12',
            'monto' => 'required|numeric|min:0',
        ]);

        $categoria = strtolower(trim($validated['categoria']));
        $ejes = (int) $validated['ejes'];

        $duplicada = Tarifa::where('categoria', $categoria)
            ->where('ejes', $ejes)
            ->where('id', '!=', $tarifa->id)
            ->exists();

        if ($duplicada) {
            return response()->json([
                'success' => false,
                'message' => "Ya existe otra tarifa para {$categoria} con {$ejes} ejes.",
            ], 422);
        }

        $tarifa->update([
            'categoria' => $categoria,
            'ejes' => $ejes,
            'monto' => $validated['monto'],
        ]);

        return response()->json(['success' => true, 'data' => $tarifa]);
    }

    public function destroyTarifa(Request $request, $id)
    {
        $this->autorizarAdmin($request);
        $tarifa = Tarifa::findOrFail($id);
        $tarifa->delete();
        return response()->json(['success' => true, 'message' => 'Tarifa eliminada con éxito']);
    }
}
