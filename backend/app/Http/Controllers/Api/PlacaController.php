<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use App\Models\Vehiculo;
use App\Models\Paso;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Str;

class PlacaController extends Controller
{
    /**
     * Normalizar placa (mayúsculas, sin guiones ni espacios)
     */
    public static function normalizar($texto)
    {
        return strtoupper(preg_replace('/[^A-Za-z0-9]/', '', (string)$texto));
    }

    /**
     * Sugerir placas parecidas corrigiendo confusiones típicas de OCR:
     * O <-> 0, I <-> 1, B <-> 8, S <-> 5
     */
    public static function buscarSugerencias($placa)
    {
        $placasExistentes = Vehiculo::pluck('placa')->toArray();
        $sugerencias = [];

        // Generar variantes con sustitución de caracteres confusos
        $confusiones = [
            'O' => ['0'], '0' => ['O'],
            'I' => ['1'], '1' => ['I'],
            'B' => ['8'], '8' => ['B'],
            'S' => ['5'], '5' => ['S'],
        ];

        foreach ($placasExistentes as $target) {
            if ($target === $placa) continue;

            // Distancia de Levenshtein simple
            $dist = levenshtein($placa, $target);
            if ($dist <= 2) {
                $sugerencias[] = $target;
            }
        }

        return array_unique($sugerencias);
    }

    /**
     * Determinar estado estricto según la Sección 4.8 de los requerimientos:
     * 1. "Registrada y con paso": La placa está registrada y tiene pasos
     * 2. "Registrada sin paso": La placa está registrada pero nunca pasó por el peaje
     * 3. "Identificada no registrada": La cámara la detectó pero no está registrada (posible evasión)
     * 4. "No existe": No hay ningún registro de la placa
     */
    public static function obtenerEstadoPlaca($placaNormalizada)
    {
        $vehiculo = Vehiculo::where('placa', $placaNormalizada)->first();
        $pasos = Paso::where('placa_normalizada', $placaNormalizada)->orderBy('created_at', 'desc')->get();

        if ($vehiculo) {
            if ($pasos->count() > 0) {
                $ultimoPaso = $pasos->first();
                return [
                    'estado' => 'Registrada y con paso',
                    'vehiculo' => $vehiculo,
                    'ultimo_paso' => [
                        'fecha' => $ultimoPaso->created_at->format('Y-m-d H:i:s'),
                        'caseta' => $ultimoPaso->caseta ? $ultimoPaso->caseta->nombre : 'Caseta General',
                        'categoria' => $ultimoPaso->categoria_detectada,
                        'ejes' => $ultimoPaso->ejes_detectados,
                        'monto' => $ultimoPaso->monto,
                        'imagen_url' => $ultimoPaso->imagen_url,
                    ],
                    'total_pasos' => $pasos->count(),
                    'sugerencias' => [],
                ];
            } else {
                return [
                    'estado' => 'Registrada sin paso',
                    'vehiculo' => $vehiculo,
                    'ultimo_paso' => null,
                    'total_pasos' => 0,
                    'sugerencias' => [],
                ];
            }
        } else {
            if ($pasos->count() > 0) {
                $ultimoPaso = $pasos->first();
                return [
                    'estado' => 'Identificada no registrada',
                    'vehiculo' => null,
                    'ultimo_paso' => [
                        'fecha' => $ultimoPaso->created_at->format('Y-m-d H:i:s'),
                        'caseta' => $ultimoPaso->caseta ? $ultimoPaso->caseta->nombre : 'Caseta General',
                        'categoria' => $ultimoPaso->categoria_detectada,
                        'ejes' => $ultimoPaso->ejes_detectados,
                        'monto' => $ultimoPaso->monto,
                        'imagen_url' => $ultimoPaso->imagen_url,
                    ],
                    'total_pasos' => $pasos->count(),
                    'sugerencias' => self::buscarSugerencias($placaNormalizada),
                ];
            } else {
                return [
                    'estado' => 'No existe',
                    'vehiculo' => null,
                    'ultimo_paso' => null,
                    'total_pasos' => 0,
                    'sugerencias' => self::buscarSugerencias($placaNormalizada),
                ];
            }
        }
    }

    /**
     * POST /api/v1/placas/consultar
     */
    public function consultar(Request $request)
    {
        $request->validate([
            'placa' => 'required|string',
        ]);

        $placaNormalizada = self::normalizar($request->input('placa'));
        $info = self::obtenerEstadoPlaca($placaNormalizada);
        $info['placa_consultada'] = $request->input('placa');
        $info['placa_normalizada'] = $placaNormalizada;

        return response()->json([
            'success' => true,
            'data' => $info,
        ]);
    }

    /**
     * POST /api/v1/placas/consultar-imagen
     * Envía imagen al M1 + OCR y luego consulta el estado
     */
    public function consultarImagen(Request $request)
    {
        $request->validate([
            'imagen' => 'nullable|image|max:10240',
            'imagen_base64' => 'nullable|string',
        ]);

        $inferenceUrl = rtrim(env('INFERENCE_URL', 'http://127.0.0.1:8000'), '/');
        $imageData = null;
        $imageExtension = 'jpg';

        if ($request->hasFile('imagen')) {
            $file = $request->file('imagen');
            $imageData = file_get_contents($file->getRealPath());
            $imageExtension = $file->getClientOriginalExtension() ?: 'jpg';
        } elseif ($request->filled('imagen_base64')) {
            $base64 = $request->input('imagen_base64');
            if (preg_match('/^data:image\/(\w+);base64,/', $base64, $type)) {
                $base64 = substr($base64, strpos($base64, ',') + 1);
                $imageExtension = strtolower($type[1]);
            }
            $imageData = base64_decode($base64);
        }

        if (!$imageData) {
            return response()->json(['success' => false, 'message' => 'No se proporcionó imagen válida'], 400);
        }

        $filename = 'consulta_' . time() . '.' . $imageExtension;
        $placaDetectada = null;
        $confianzaOcr = 0.0;

        try {
            $response = Http::timeout(12)
                ->attach('file', $imageData, $filename)
                ->post($inferenceUrl . '/predict/ocr');

            if ($response->successful()) {
                $res = $response->json();
                $placaDetectada = $res['placa'] ?? null;
                $confianzaOcr = $res['confianza'] ?? 0.0;
            }
        } catch (\Exception $e) {
            \Log::warning('Fallo llamada OCR: ' . $e->getMessage());
        }

        if (!$placaDetectada || $placaDetectada === 'SIN_PLACA') {
            return response()->json([
                'success' => false,
                'message' => 'No se pudo leer ninguna placa en la imagen. Por favor sube una imagen más nítida o escribe la placa.',
            ], 422);
        }

        $placaNormalizada = self::normalizar($placaDetectada);
        $info = self::obtenerEstadoPlaca($placaNormalizada);
        $info['placa_leida'] = $placaDetectada;
        $info['placa_normalizada'] = $placaNormalizada;
        $info['confianza_ocr'] = $confianzaOcr;

        return response()->json([
            'success' => true,
            'data' => $info,
        ]);
    }

    /**
     * GET /api/v1/placas/{placa}/historial
     */
    public function historial($placa)
    {
        $placaNormalizada = self::normalizar($placa);
        $pasos = Paso::with('caseta')
            ->where('placa_normalizada', $placaNormalizada)
            ->orderBy('created_at', 'desc')
            ->get();

        $vehiculo = Vehiculo::where('placa', $placaNormalizada)->first();

        return response()->json([
            'success' => true,
            'placa' => $placaNormalizada,
            'vehiculo' => $vehiculo,
            'historial' => $pasos,
        ]);
    }
}

