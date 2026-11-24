<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use App\Models\Paso;
use App\Models\Alerta;
use Symfony\Component\HttpFoundation\StreamedResponse;

class StreamController extends Controller
{
    /**
     * GET /api/v1/stream/eventos
     * Servidor de Server-Sent Events (SSE) para el panel web en tiempo real.
     * Transmite inmediatamente pasos nuevos, alertas y actualización de contadores
     * sin sobrecargar la red ni requerir librerías externas o servidores WebSocket de pago.
     */
    public function stream(Request $request)
    {
        $response = new StreamedResponse(function () use ($request) {
            $lastPasoId = $request->query('last_paso_id', Paso::max('id') ?? 0);
            $lastAlertaId = $request->query('last_alerta_id', Alerta::max('id') ?? 0);

            // Mantener la conexión abierta por 30 segundos
            $startTime = time();

            while (time() - $startTime < 28) {
                // Verificar si hay nuevos pasos
                $nuevosPasos = Paso::with(['caseta', 'alertas'])
                    ->where('id', '>', $lastPasoId)
                    ->orderBy('id', 'asc')
                    ->get();

                if ($nuevosPasos->isNotEmpty()) {
                    foreach ($nuevosPasos as $paso) {
                        echo "event: nuevo_paso\n";
                        echo 'data: ' . json_encode($paso) . "\n\n";
                        $lastPasoId = max($lastPasoId, $paso->id);
                    }
                    ob_flush();
                    flush();
                }

                // Verificar nuevas alertas
                $nuevasAlertas = Alerta::with('paso')
                    ->where('id', '>', $lastAlertaId)
                    ->orderBy('id', 'asc')
                    ->get();

                if ($nuevasAlertas->isNotEmpty()) {
                    foreach ($nuevasAlertas as $alerta) {
                        echo "event: nueva_alerta\n";
                        echo 'data: ' . json_encode($alerta) . "\n\n";
                        $lastAlertaId = max($lastAlertaId, $alerta->id);
                    }
                    ob_flush();
                    flush();
                }

                // Heartbeat para mantener vivo el stream
                echo ": heartbeat\n\n";
                ob_flush();
                flush();

                usleep(700000); // 0.7s
            }
        });

        $response->headers->set('Content-Type', 'text/event-stream');
        $response->headers->set('Cache-Control', 'no-cache');
        $response->headers->set('Connection', 'keep-alive');
        $response->headers->set('X-Accel-Buffering', 'no'); // Para Nginx / hosting

        return $response;
    }
}

