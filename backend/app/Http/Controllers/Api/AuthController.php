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
     * POST /api/v1/auth/google
     * Recibe id_token o token de Google desde la web/app y retorna el token de sesión Sanctum
     */
    public function googleLogin(Request $request)
    {
        $request->validate([
            'id_token' => 'nullable|string',
            'token' => 'nullable|string',
            'email' => 'nullable|email',
            'name' => 'nullable|string',
        ]);

        $googleEmail = null;
        $googleName = null;

        $token = $request->input('id_token') ?? $request->input('token');

        // Si se provee un token de Google, intentar validarlo con la API de Google tokeninfo
        if ($token) {
            try {
                $response = Http::timeout(5)->get('https://oauth2.googleapis.com/tokeninfo', [
                    'id_token' => $token,
                ]);

                if ($response->successful()) {
                    $payload = $response->json();
                    $googleEmail = $payload['email'] ?? null;
                    $googleName = $payload['name'] ?? null;
                }
            } catch (\Exception $e) {
                Log::warning('Error verificando token con Google: ' . $e->getMessage());
            }
        }

        // Modo desarrollo o fallback de payload directo si la verificación remota no está activa
        if (!$googleEmail && $request->filled('email')) {
            $googleEmail = $request->input('email');
            $googleName = $request->input('name', 'Usuario Google');
        }

        if (!$googleEmail) {
            return response()->json([
                'success' => false,
                'message' => 'Token de Google inválido o no se pudo obtener el correo.',
            ], 401);
        }

        // Validar LISTA BLANCA en base de datos
        $user = User::where('email_google', $googleEmail)->first();

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

        // Actualizar nombre si cambió
        if ($googleName && $user->nombre !== $googleName) {
            $user->nombre = $googleName;
            $user->save();
        }

        // Generar token Sanctum
        $apiToken = $user->createToken('peaje-session')->plainTextToken;

        return response()->json([
            'success' => true,
            'token' => $apiToken,
            'usuario' => [
                'id' => $user->id,
                'nombre' => $user->nombre,
                'email_google' => $user->email_google,
                'rol' => $user->rol,
                'activo' => $user->activo,
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

