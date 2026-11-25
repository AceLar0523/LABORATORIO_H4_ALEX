<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use App\Http\Controllers\Api\PlacaController;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

class AgenteController extends Controller
{
    /**
     * POST /api/v1/agente/chat
     * Mensaje al agente conversacional asistido por LLM (Ollama en RunPod).
     * Soporta texto o imagen. Devuelve estrictamente uno de los 4 estados:
     * 1. Registrada y con paso
     * 2. Registrada sin paso
     * 3. Identificada no registrada
     * 4. No existe
     * Incluye sugerencias OCR si no coincide ("¿Quisiste decir...?").
     */
    public function chat(Request $request)
    {
        $request->validate([
            'mensaje' => 'nullable|string',
            'imagen_base64' => 'nullable|string',
        ]);

        $mensaje = trim($request->input('mensaje', ''));
        $imagenBase64 = $request->input('imagen_base64');
        $prefijo = "";

        // Si se envió imagen, resolver placa con M1 + OCR
        if (!empty($imagenBase64)) {
            $reqOcr = new Request(['imagen_base64' => $imagenBase64]);
            $placaCtrl = new PlacaController();
            $resOcr = $placaCtrl->consultarImagen($reqOcr);
            $ocrData = $resOcr->getData(true);

            if (!$ocrData['success']) {
                return response()->json([
                    'success' => true,
                    'respuesta' => "❌ No se pudo identificar una placa legible en la imagen enviada. Por favor, asegúrate de que esté bien iluminada y enfocada, o ingresa el texto de la placa manualmente.",
                    'estado' => 'No legible',
                    'data' => null,
                ]);
            }

            $placaNormalizada = $ocrData['data']['placa_normalizada'];
            $info = $ocrData['data'];
            $confianza = $ocrData['data']['confianza_ocr'];
            $prefijo = "📷 Placa detectada en la imagen: **{$placaNormalizada}** (Confianza OCR: " . ($confianza * 100) . "%)\n\n";
        } else {
            // Extraer placa del texto: buscar palabras alfanuméricas de longitud 4-8
            $stopWords = ['ESTADO', 'PLACA', 'QUIERO', 'CONSULTAR', 'SABER', 'VEHICULO', 'TIENE', 'EXISTE', 'BUENAS', 'TARDES', 'DIAS', 'HOLA', 'CUAL', 'INFO', 'INFORMAR'];
            preg_match_all('/[A-Za-z0-9]{4,8}/', strtoupper($mensaje), $allMatches);
            
            $candidatoPlaca = null;
            if (!empty($allMatches[0])) {
                foreach ($allMatches[0] as $match) {
                    if (!in_array($match, $stopWords)) {
                        if (preg_match('/\d/', $match) || strlen($match) >= 6) {
                            $candidatoPlaca = $match;
                            break;
                        }
                        if (!$candidatoPlaca) {
                            $candidatoPlaca = $match;
                        }
                    }
                }
            }

            if (!$candidatoPlaca) {
                return response()->json([
                    'success' => true,
                    'respuesta' => "Hola. Soy el Asistente Inteligente de Peaje (Ollama LLM). Para consultar un vehículo, indícame la placa (ej: `4021XYZ`) o envía una fotografía clara de la misma.",
                    'estado' => 'Esperando placa',
                    'data' => null,
                ]);
            }

            $placaNormalizada = PlacaController::normalizar($candidatoPlaca);
            $info = PlacaController::obtenerEstadoPlaca($placaNormalizada);
        }

        $estado = $info['estado'];
        
        // Respuesta estructurada base con datos fidedignos de la Base de Datos
        $respuestaBase = $this->generarRespuestaEstructurada($estado, $placaNormalizada, $info);

        // Integración con OLLAMA (en RunPod o Local) si está configurado
        $ollamaUrl = rtrim(env('OLLAMA_URL', 'http://127.0.0.1:11434'), '/');
        $ollamaModel = env('OLLAMA_MODEL', 'llama3.2:3b');
        $respuestaFinal = $respuestaBase;

        try {
            $contextoDatos = json_encode([
                'placa' => $placaNormalizada,
                'estado_oficial' => $estado,
                'detalles' => $info,
                'regla_estricta' => 'NUNCA inventes datos. Usa únicamente la información provista. Informa claramente el estado oficial.',
            ], JSON_UNESCAPED_UNICODE);

            $promptOllama = "Eres el agente oficial del Sistema Inteligente de Control de Peaje. "
                . "Un usuario ha preguntado: '{$mensaje}'. "
                . "Los datos oficiales obtenidos de la base de datos son: {$contextoDatos}. "
                . "Redacta una respuesta profesional, concisa y amable informando exactamente el estado oficial del vehículo. "
                . "Si el estado es 'Identificada no registrada' o 'No existe' y hay sugerencias de placas, menciónalas preguntando '¿Quisiste decir alguna de estas placas registradas?: ...'. "
                . "Mantén las viñetas con los datos relevantes (propietario, saldo, último paso o advertencia).";

            $inferenceUrl = rtrim(env('INFERENCE_URL', 'http://127.0.0.1:8000'), '/');
            $ollamaResponse = null;

            try {
                $ollamaResponse = Http::timeout(12)->post("{$ollamaUrl}/api/generate", [
                    'model' => $ollamaModel,
                    'prompt' => $promptOllama,
                    'stream' => false,
                ]);
            } catch (\Exception $e) {
                // Si el puerto directo de Ollama no responde, intentar mediante el proxy en FastAPI
                try {
                    $ollamaResponse = Http::timeout(25)->post("{$inferenceUrl}/ollama/generate", [
                        'model' => $ollamaModel,
                        'prompt' => $promptOllama,
                        'stream' => false,
                    ]);
                } catch (\Exception $ex) {
                    $ollamaResponse = null;
                }
            }

            if ($ollamaResponse && $ollamaResponse->successful()) {
                $llmOutput = trim($ollamaResponse->json()['response'] ?? '');
                if (!empty($llmOutput)) {
                    $respuestaFinal = $llmOutput;
                }
            }
        } catch (\Exception $e) {
            Log::info("Ollama no disponible en {$ollamaUrl}, usando respuesta estructurada nativa: " . $e->getMessage());
        }

        return response()->json([
            'success' => true,
            'respuesta' => $prefijo . $respuestaFinal,
            'estado' => $estado,
            'llm_motor' => 'Ollama (' . $ollamaModel . ') en RunPod',
            'data' => $info,
        ]);
    }

    private function generarRespuestaEstructurada($estado, $placaNormalizada, $info)
    {
        switch ($estado) {
            case 'Registrada y con paso':
                $v = $info['vehiculo'];
                $up = $info['ultimo_paso'];
                return "✅ **Estado: Registrada y con paso**\n"
                    . "• **Placa:** {$v->placa}\n"
                    . "• **Propietario:** {$v->propietario}\n"
                    . "• **Categoría:** {$v->categoria} ({$v->ejes} ejes)\n"
                    . "• **Saldo actual:** Bs. {$v->saldo}\n"
                    . "• **Último paso registrado:** {$up['fecha']} en {$up['caseta']} (Tarifa cobrada: Bs. {$up['monto']}).\n"
                    . "• **Total de tránsitos:** {$info['total_pasos']}";

            case 'Registrada sin paso':
                $v = $info['vehiculo'];
                return "ℹ️ **Estado: Registrada sin paso**\n"
                    . "• **Placa:** {$v->placa}\n"
                    . "• **Propietario:** {$v->propietario}\n"
                    . "• **Categoría:** {$v->categoria} ({$v->ejes} ejes)\n"
                    . "• **Saldo actual:** Bs. {$v->saldo}\n"
                    . "• El vehículo está debidamente registrado en el sistema pero aún no registra ningún cruce por las casetas de peaje.";

            case 'Identificada no registrada':
                $up = $info['ultimo_paso'];
                $resp = "⚠️ **Estado: Identificada no registrada**\n"
                    . "• **Placa detectada:** {$placaNormalizada}\n"
                    . "• Fue captada por las cámaras de caseta en {$up['caseta']} ({$up['fecha']}), pero **no figura en el padrón de vehículos registrados** (Posible infracción o evasión).\n"
                    . "• Tarifa aplicada: Bs. {$up['monto']} (Categoría estimada: {$up['categoria']}).";
                if (!empty($info['sugerencias'])) {
                    $sugList = implode(', ', array_map(fn($s) => "`{$s}`", $info['sugerencias']));
                    $resp .= "\n\n💡 ¿Quisiste decir alguna de estas placas registradas?: {$sugList}";
                }
                return $resp;

            case 'No existe':
            default:
                $resp = "🚫 **Estado: No existe**\n"
                    . "No existe ningún registro ni paso asociado a la placa **{$placaNormalizada}** en el sistema.";
                if (!empty($info['sugerencias'])) {
                    $sugList = implode(', ', array_map(fn($s) => "`{$s}`", $info['sugerencias']));
                    $resp .= "\n\n💡 ¿Quisiste decir alguna de estas placas registradas?: {$sugList}";
                }
                return $resp;
        }
    }
}
