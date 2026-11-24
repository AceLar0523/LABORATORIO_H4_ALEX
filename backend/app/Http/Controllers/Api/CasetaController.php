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
     * Indica si el endpoint de inferencia responde (Sección 4.2 requerimientos)
     */
    public function estadoInferencia()
    {
        $url = env('INFERENCE_URL', 'http://127.0.0.1:8000');
        $t0 = microtime(true);
        $status = 'offline';
        $details = null;

        try {
            $resp = Http::timeout(3)->get($url . '/');
            if ($resp->successful()) {
                $status = 'online';
                $details = $resp->json();
            }
        } catch (\Exception $e) {
            $status = 'offline';
            $details = ['error' => $e->getMessage()];
        }

        $latency = round((microtime(true) - $t0) * 1000, 2);

        return response()->json([
            'status' => $status,
            'url' => $url,
            'latencia_ms' => $latency,
            'detalles' => $details,
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

