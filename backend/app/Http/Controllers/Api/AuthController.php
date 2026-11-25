<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use App\Models\User;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

class AuthController extends Controller
{
    /**
     * GET /api/v1/auth/config
     * Expone configuración pública de Google OAuth 2.0 (Web y Móvil Android) para los clientes.
     */
    public function authConfig()
    {
        $webClientId = trim((string) config('services.google.client_id', ''));
        $androidClientId = trim((string) config('services.google.android_client_id', ''));

        return response()->json([
            'google_client_id' => $webClientId,
            'google_android_client_id' => $androidClientId,
            'google_oauth_enabled' => ($webClientId !== '' || $androidClientId !== ''),
        ]);
    }

    /**
     * POST /api/v1/auth/google
     * Valida el ID Token real de Google OAuth 2.0 (Web o Android) contra Google tokeninfo y lista blanca.
     */
    public function googleLogin(Request $request)
    {
        $request->validate([
            'id_token' => 'nullable|string',
            'token' => 'nullable|string',
        ]);

        $allowedClientIds = array_values(array_filter([
            trim((string) config('services.google.client_id', '')),
            trim((string) config('services.google.android_client_id', '')),
        ]));

        if (empty($allowedClientIds)) {
            return response()->json([
                'success' => false,
                'message' => 'Google OAuth 2.0 aún no está configurado en el servidor.',
            ], 503);
        }

        $token = $request->input('id_token') ?? $request->input('token');
        if (!$token) {
            return response()->json([
                'success' => false,
                'message' => 'Se requiere id_token de Google OAuth 2.0.',
            ], 422);
        }

        $googleEmail = null;
        $googleName = null;

        try {
            $response = Http::timeout(8)->get('https://oauth2.googleapis.com/tokeninfo', [
                'id_token' => $token,
            ]);

            if ($response->successful()) {
                $payload = $response->json();
                $aud = (string) ($payload['aud'] ?? '');
                $audOk = in_array($aud, $allowedClientIds, true);
                $verifiedOk = !isset($payload['email_verified'])
                    || $payload['email_verified'] === true
                    || $payload['email_verified'] === 'true';

                if ($audOk && $verifiedOk) {
                    $googleEmail = $payload['email'] ?? null;
                    $googleName = $payload['name'] ?? null;
                } else {
                    return response()->json([
                        'success' => false,
                        'message' => 'Token de Google inválido para esta aplicación o correo no verificado.',
                    ], 401);
                }
            }
        } catch (\Exception $e) {
            Log::warning('Error verificando token con Google: ' . $e->getMessage());
        }

        if (!$googleEmail) {
            return response()->json([
                'success' => false,
                'message' => 'Token de Google inválido o expirado.',
            ], 401);
        }

        $emailNormalized = strtolower(trim($googleEmail));
        $user = User::whereRaw('LOWER(email_google) = ?', [$emailNormalized])->first();

        if (!$user) {
            return response()->json([
                'success' => false,
                'message' => 'Acceso denegado. La cuenta de Google no se encuentra en la lista blanca de usuarios autorizados.',
            ], 403);
        }

        if (!$user->activo) {
            return response()->json([
                'success' => false,
                'message' => 'Acceso denegado. El usuario se encuentra inactivo.',
            ], 403);
        }

        if ($googleName && (empty($user->nombre) || $user->nombre === 'Usuario Google')) {
            $user->nombre = $googleName;
            $user->save();
        }

        $apiToken = $user->createToken('peaje-session')->plainTextToken;

        return response()->json([
            'success' => true,
            'token' => $apiToken,
            'usuario' => [
                'id' => $user->id,
                'nombre' => $user->nombre,
                'email_google' => $user->email_google,
                'rol' => $user->rol,
                'activo' => (bool) $user->activo,
            ],
        ]);
    }

    public function me(Request $request)
    {
        return response()->json([
            'success' => true,
            'usuario' => $request->user(),
        ]);
    }
}
