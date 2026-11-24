<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use App\Models\Vehiculo;

class VehiculoController extends Controller
{
    public function index(Request $request)
    {
        $query = Vehiculo::query();
        if ($request->has('q')) {
            $q = $request->input('q');
            $query->where('placa', 'like', "%{$q}%")
                  ->orWhere('propietario', 'like', "%{$q}%");
        }
        return response()->json($query->orderBy('id', 'desc')->paginate(15));
    }

    public function store(Request $request)
    {
        $validated = $request->validate([
            'placa' => 'required|string|max:15|unique:vehiculos,placa',
            'propietario' => 'required|string|max:255',
            'categoria' => 'required|string|max:30',
            'ejes' => 'required|integer|min:2|max:10',
            'saldo' => 'nullable|numeric|min:0',
            'activo' => 'nullable|boolean',
        ]);

        $validated['placa'] = strtoupper(preg_replace('/[^A-Za-z0-9]/', '', $validated['placa']));
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
        $vehiculo = Vehiculo::findOrFail($id);

        $validated = $request->validate([
            'placa' => 'sometimes|required|string|max:15|unique:vehiculos,placa,' . $id,
            'propietario' => 'sometimes|required|string|max:255',
            'categoria' => 'sometimes|required|string|max:30',
            'ejes' => 'sometimes|required|integer|min:2|max:10',
            'saldo' => 'nullable|numeric|min:0',
            'activo' => 'nullable|boolean',
        ]);

        if (isset($validated['placa'])) {
            $validated['placa'] = strtoupper(preg_replace('/[^A-Za-z0-9]/', '', $validated['placa']));
        }

        $vehiculo->update($validated);
        return response()->json(['success' => true, 'data' => $vehiculo]);
    }

    public function destroy($id)
    {
        $vehiculo = Vehiculo::findOrFail($id);
        $vehiculo->delete();
        return response()->json(['success' => true, 'message' => 'Vehículo eliminado con éxito']);
    }
}

