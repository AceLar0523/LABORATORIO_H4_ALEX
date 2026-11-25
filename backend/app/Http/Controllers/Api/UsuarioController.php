<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;

class UsuarioController extends Controller
{
    private function autorizarAdmin(Request $request)
    {
        $usuario = $request->user();
        if (!$usuario || $usuario->rol !== 'administrador') {
            abort(response()->json([
                'success' => false,
                'message' => 'Se requieren permisos de administrador para gestionar usuarios y la lista blanca.',
            ], 403));
        }
    }

    private function formatUsuario(User $u): array
    {
        return [
            'id' => $u->id,
            'nombre' => $u->nombre,
            'email_google' => $u->email_google,
            'rol' => $u->rol,
            'activo' => (bool) $u->activo,
            'tiene_password' => !empty($u->password),
            'created_at' => $u->created_at,
            'updated_at' => $u->updated_at,
        ];
    }

    private function esUltimoAdminActivo(User $usuario): bool
    {
        if ($usuario->rol !== 'administrador' || !$usuario->activo) {
            return false;
        }
        return User::where('rol', 'administrador')->where('activo', true)->count() <= 1;
    }

    public function index(Request $request)
    {
        $query = User::query()->orderBy('id', 'asc');

        if ($request->filled('q')) {
            $q = strtolower(trim((string) $request->input('q')));
            $query->where(function ($sub) use ($q) {
                $sub->whereRaw('LOWER(nombre) LIKE ?', ["%{$q}%"])
                    ->orWhereRaw('LOWER(email_google) LIKE ?', ["%{$q}%"]);
            });
        }

        if ($request->filled('rol') && in_array($request->input('rol'), ['administrador', 'operador'], true)) {
            $query->where('rol', $request->input('rol'));
        }

        if ($request->has('activo') && $request->input('activo') !== '') {
            $query->where('activo', filter_var($request->input('activo'), FILTER_VALIDATE_BOOLEAN));
        }

        $usuarios = $query->get()->map(fn (User $u) => $this->formatUsuario($u))->values();

        return response()->json([
            'success' => true,
            'data' => $usuarios,
            'resumen' => [
                'total' => User::count(),
                'activos' => User::where('activo', true)->count(),
                'administradores' => User::where('rol', 'administrador')->count(),
                'operadores' => User::where('rol', 'operador')->count(),
            ],
        ]);
    }

    public function store(Request $request)
    {
        $this->autorizarAdmin($request);

        $validated = $request->validate([
            'nombre' => 'required|string|max:120',
            'email_google' => 'required|email|max:180',
            'rol' => 'required|in:administrador,operador',
            'activo' => 'nullable|boolean',
            'password' => 'nullable|string|min:6|max:100',
        ]);

        $email = strtolower(trim($validated['email_google']));
        if (User::whereRaw('LOWER(email_google) = ?', [$email])->exists()) {
            return response()->json([
                'success' => false,
                'message' => 'Ese correo de Google ya se encuentra registrado en la lista blanca.',
            ], 422);
        }

        $user = User::create([
            'nombre' => trim($validated['nombre']),
            'email_google' => $email,
            'rol' => $validated['rol'],
            'activo' => array_key_exists('activo', $validated) ? (bool) $validated['activo'] : true,
            'password' => !empty($validated['password']) ? Hash::make($validated['password']) : null,
        ]);

        return response()->json([
            'success' => true,
            'message' => 'Usuario agregado a la lista blanca correctamente.',
            'data' => $this->formatUsuario($user),
        ], 201);
    }

    public function update(Request $request, $id)
    {
        $this->autorizarAdmin($request);
        $user = User::findOrFail($id);

        $validated = $request->validate([
            'nombre' => 'required|string|max:120',
            'email_google' => 'required|email|max:180',
            'rol' => 'required|in:administrador,operador',
            'activo' => 'nullable|boolean',
            'password' => 'nullable|string|min:6|max:100',
        ]);

        $email = strtolower(trim($validated['email_google']));
        $duplicado = User::whereRaw('LOWER(email_google) = ?', [$email])
            ->where('id', '!=', $user->id)
            ->exists();

        if ($duplicado) {
            return response()->json([
                'success' => false,
                'message' => 'Ya existe otro usuario registrado con ese correo de Google.',
            ], 422);
        }

        $nuevoActivo = array_key_exists('activo', $validated) ? (bool) $validated['activo'] : (bool) $user->activo;
        $nuevoRol = $validated['rol'];

        if ($this->esUltimoAdminActivo($user) && (!$nuevoActivo || $nuevoRol !== 'administrador')) {
            return response()->json([
                'success' => false,
                'message' => 'No puedes revocar o degradar al último administrador activo del sistema.',
            ], 422);
        }

        $user->nombre = trim($validated['nombre']);
        $user->email_google = $email;
        $user->rol = $nuevoRol;
        $user->activo = $nuevoActivo;

        if (!empty($validated['password'])) {
            $user->password = Hash::make($validated['password']);
        }

        $user->save();

        if (!$user->activo) {
            $user->tokens()->delete();
        }

        return response()->json([
            'success' => true,
            'message' => 'Usuario actualizado correctamente.',
            'data' => $this->formatUsuario($user),
        ]);
    }

    public function toggleEstado(Request $request, $id)
    {
        $this->autorizarAdmin($request);
        $user = User::findOrFail($id);

        $nuevoActivo = $request->has('activo')
            ? filter_var($request->input('activo'), FILTER_VALIDATE_BOOLEAN)
            : !$user->activo;

        if (!$nuevoActivo && $this->esUltimoAdminActivo($user)) {
            return response()->json([
                'success' => false,
                'message' => 'No puedes revocar o degradar al último administrador activo del sistema.',
            ], 422);
        }

        $user->activo = $nuevoActivo;
        $user->save();

        if (!$user->activo) {
            $user->tokens()->delete();
        }

        return response()->json([
            'success' => true,
            'message' => $user->activo ? 'Acceso autorizado correctamente.' : 'Acceso revocado correctamente.',
            'data' => $this->formatUsuario($user),
        ]);
    }

    public function destroy(Request $request, $id)
    {
        $this->autorizarAdmin($request);
        $user = User::findOrFail($id);

        if ($request->user()->id === $user->id) {
            return response()->json([
                'success' => false,
                'message' => 'No puedes eliminar tu propia cuenta mientras tienes la sesión activa.',
            ], 422);
        }

        if ($this->esUltimoAdminActivo($user)) {
            return response()->json([
                'success' => false,
                'message' => 'No puedes eliminar al último administrador activo del sistema.',
            ], 422);
        }

        $user->tokens()->delete();
        $user->delete();

        return response()->json([
            'success' => true,
            'message' => 'Usuario eliminado de la lista blanca correctamente.',
        ]);
    }
}

