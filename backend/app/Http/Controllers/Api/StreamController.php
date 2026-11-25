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
     * SSE no bloqueante para entorno de desarrollo y producción.
     * Cierra la sesión activa de PHP si existiera para liberar el worker inmediatamente.
     */
    public function stream(Request $request)
    {
        // Liberar sesión de PHP para que no bloquee otras peticiones HTTP concurrentes
        if (session_status() === PHP_SESSION_ACTIVE) {
            session_write_close();
        }

        if (function_exists('apache_setenv')) {
            @apache_setenv('no-gzip', '1');
        }
        @ini_set('zlib.output_compression', '0');
        @ini_set('implicit_flush', '1');

        $response = new StreamedResponse(function () use ($request) {
            $lastPasoId = (int)$request->query('last_paso_id', 0);
            $lastAlertaId = (int)$request->query('last_alerta_id', 0);

            if ($lastPasoId === 0) {
                $lastPasoId = (int)(Paso::max('id') ?? 0);
            }
            if ($lastAlertaId === 0) {
                $lastAlertaId = (int)(Alerta::max('id') ?? 0);
            }

            $startTime = time();

            // Duración máxima de 15 segundos por conexión SSE para liberar sockets periódicamente
            while (time() - $startTime < 15) {
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
                    while (ob_get_level() > 0) {
                        ob_end_flush();
                    }
                    flush();
                }

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
                    while (ob_get_level() > 0) {
                        ob_end_flush();
                    }
                    flush();
                }

                echo ": ping\n\n";
                while (ob_get_level() > 0) {
                    ob_end_flush();
                }
                flush();

                // 1 segundo de intervalo para no saturar el pooler de Supabase
                sleep(1);
            }
        });

        $response->headers->set('Content-Type', 'text/event-stream');
        $response->headers->set('Cache-Control', 'no-cache, no-store, must-revalidate');
        $response->headers->set('Connection', 'keep-alive');
        $response->headers->set('X-Accel-Buffering', 'no');

        return $response;
    }
}
