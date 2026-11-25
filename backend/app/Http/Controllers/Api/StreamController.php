<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use App\Models\Paso;
use App\Models\Alerta;
use Laravel\Sanctum\PersonalAccessToken;
use Symfony\Component\HttpFoundation\StreamedResponse;

class StreamController extends Controller
{
    /**
     * GET /api/v1/stream/eventos
     * SSE autenticado (Bearer o query ?token=) con soporte de Last-Event-ID.
     */
    public function stream(Request $request)
    {
        $rawToken = $request->bearerToken() ?: (string) $request->query('token', '');
        $tokenModel = $rawToken !== '' ? PersonalAccessToken::findToken($rawToken) : null;
        $usuario = $tokenModel?->tokenable;

        if (!$usuario || !$usuario->activo) {
            return response()->json([
                'success' => false,
                'message' => 'No autenticado. Se requiere token válido para el stream en tiempo real.',
            ], 401);
        }

        // Liberar sesión de PHP para que no bloquee otras peticiones HTTP concurrentes
        if (session_status() === PHP_SESSION_ACTIVE) {
            session_write_close();
        }

        if (function_exists('apache_setenv')) {
            @apache_setenv('no-gzip', '1');
        }
        @ini_set('zlib.output_compression', '0');
        @ini_set('implicit_flush', '1');

        $once = $request->boolean('once');

        $response = new StreamedResponse(function () use ($request, $once) {
            $flushStream = function () use ($once): void {
                if (!$once) {
                    if (ob_get_level() > 0) {
                        @ob_flush();
                    }
                    flush();
                }
            };

            $lastEventId = (int) $request->header('Last-Event-ID', 0);
            $lastPasoId = max($lastEventId, (int) $request->query('last_paso_id', 0));
            $lastAlertaId = (int) $request->query('last_alerta_id', 0);

            if ($lastPasoId === 0 && !$request->has('last_paso_id') && $lastEventId === 0) {
                $lastPasoId = (int) (Paso::max('id') ?? 0);
            }
            if ($lastAlertaId === 0 && !$request->has('last_alerta_id')) {
                $lastAlertaId = (int) (Alerta::max('id') ?? 0);
            }

            $startTime = time();

            // Duración máxima de 15 segundos por conexión SSE para liberar sockets periódicamente
            do {
                $nuevosPasos = Paso::with(['caseta', 'alertas'])
                    ->where('id', '>', $lastPasoId)
                    ->orderBy('id', 'asc')
                    ->get();

                if ($nuevosPasos->isNotEmpty()) {
                    foreach ($nuevosPasos as $paso) {
                        echo "id: {$paso->id}\n";
                        echo "event: nuevo_paso\n";
                        echo 'data: ' . json_encode($paso) . "\n\n";
                        $lastPasoId = max($lastPasoId, $paso->id);
                    }
                    $flushStream();
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
                    $flushStream();
                }

                echo ": ping\n\n";
                $flushStream();

                if ($once) {
                    break;
                }

                // 1 segundo de intervalo para no saturar el pooler de Supabase
                sleep(1);
            } while (time() - $startTime < 15);
        });

        $response->headers->set('Content-Type', 'text/event-stream');
        $response->headers->set('Cache-Control', 'no-cache, no-store, must-revalidate');
        $response->headers->set('Connection', 'keep-alive');
        $response->headers->set('X-Accel-Buffering', 'no');

        return $response;
    }
}
