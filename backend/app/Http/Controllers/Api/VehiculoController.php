<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use App\Models\Vehiculo;

class VehiculoController extends Controller
{
    private function autorizarAdmin(Request $request): void
    {
        $usuario = $request->user();
        if (!$usuario || $usuario->rol !== 'administrador') {
            abort(response()->json([
                'success' => false,
                'message' => 'Se requieren permisos de administrador para gestionar el padrón de vehículos.',
            ], 403));
        }
    }

    public function index(Request $request)
    {
        $query = Vehiculo::query();
        if ($request->filled('q')) {
            $q = trim((string) $request->input('q'));
            $query->where(function ($sub) use ($q) {
                $sub->where('placa', 'like', "%{$q}%")
                    ->orWhere('propietario', 'like', "%{$q}%");
            });
        }
        return response()->json($query->orderBy('id', 'desc')->paginate(15));
    }

    public function store(Request $request)
    {
        $this->autorizarAdmin($request);

        if ($request->has('placa')) {
            $request->merge([
                'placa' => strtoupper(preg_replace('/[^A-Za-z0-9]/', '', (string) $request->input('placa'))),
            ]);
        }

        $validated = $request->validate([
            'placa' => 'required|string|max:15|unique:vehiculos,placa',
            'propietario' => 'required|string|max:255',
            'categoria' => 'required|string|max:30',
            'ejes' => 'required|integer|min:1|max:10',
            'saldo' => 'nullable|numeric|min:0',
            'activo' => 'nullable|boolean',
        ]);

        $validated['categoria'] = strtolower(trim($validated['categoria']));
        $validated['saldo'] = $validated['saldo'] ?? 0;
        $validated['activo'] = array_key_exists('activo', $validated) ? (bool) $validated['activo'] : true;
        $vehiculo = Vehiculo::create($validated);

        return response()->json(['success' => true, 'data' => $vehiculo], 201);
    }

    public function show($id)
    {
        $vehiculo = Vehiculo::findOrFail($id);
        return response()->json(['success' => true, 'data' => $vehiculo]);
    }

    public function update(Request $request, $id)
    {
        $this->autorizarAdmin($request);
        $vehiculo = Vehiculo::findOrFail($id);

        if ($request->has('placa')) {
            $request->merge([
                'placa' => strtoupper(preg_replace('/[^A-Za-z0-9]/', '', (string) $request->input('placa'))),
            ]);
        }

        $validated = $request->validate([
            'placa' => 'sometimes|required|string|max:15|unique:vehiculos,placa,' . $id,
            'propietario' => 'sometimes|required|string|max:255',
            'categoria' => 'sometimes|required|string|max:30',
            'ejes' => 'sometimes|required|integer|min:1|max:10',
            'saldo' => 'nullable|numeric|min:0',
            'activo' => 'nullable|boolean',
        ]);

        if (isset($validated['categoria'])) {
            $validated['categoria'] = strtolower(trim($validated['categoria']));
        }

        $vehiculo->update($validated);
        return response()->json(['success' => true, 'data' => $vehiculo]);
    }

    public function destroy(Request $request, $id)
    {
        $this->autorizarAdmin($request);
        $vehiculo = Vehiculo::findOrFail($id);
        $vehiculo->delete();
        return response()->json(['success' => true, 'message' => 'Vehículo eliminado con éxito']);
    }
}

