<?php

use Illuminate\Http\Request;
use Illuminate\Support\Facades\Route;
use App\Http\Controllers\Api\AuthController;
use App\Http\Controllers\Api\VehiculoController;
use App\Http\Controllers\Api\PasoController;
use App\Http\Controllers\Api\PlacaController;
use App\Http\Controllers\Api\CasetaController;
use App\Http\Controllers\Api\AgenteController;
use App\Http\Controllers\Api\StreamController;
use App\Http\Controllers\Api\UsuarioController;

/*
|--------------------------------------------------------------------------
| Rutas API del Sistema Inteligente de Control de Peaje
|--------------------------------------------------------------------------
*/

Route::prefix('v1')->group(function () {

    // Ping público de diagnóstico para app móvil y monitoreo
    Route::get('/ping', function () {
        return response()->json([
            'success' => true,
            'message' => 'Servidor de Peaje Inteligente en Línea',
            'timestamp' => now()->toIso8601String(),
        ]);
    });

    // Configuración y rutas de Login públicas (exclusivo Google OAuth 2.0)
    Route::get('/auth/config', [AuthController::class, 'authConfig']);
    Route::post('/auth/google', [AuthController::class, 'googleLogin']);

    // Stream SSE en tiempo real para Panel Web (permite token por query o cabecera)
    Route::get('/stream/eventos', [StreamController::class, 'stream']);

    // Rutas protegidas por Sanctum
    Route::middleware('auth:sanctum')->group(function () {

        Route::get('/auth/me', [AuthController::class, 'me']);

        // 4.5 API REST mínima requerida por rúbrica
        Route::post('/pasos/frame', [PasoController::class, 'registrarFrame']);
        Route::post('/placas/consultar', [PlacaController::class, 'consultar']);
        Route::post('/placas/consultar-imagen', [PlacaController::class, 'consultarImagen']);
        Route::get('/placas/{placa}/historial', [PlacaController::class, 'historial']);
        Route::get('/casetas/{id}/resumen', [CasetaController::class, 'resumen']);
        Route::post('/agente/chat', [AgenteController::class, 'chat']);

        // Recursos adicionales del sistema
        Route::get('/pasos', [PasoController::class, 'index']);
        Route::delete('/pasos/limpiar/sin-placa', [PasoController::class, 'limpiarSinPlaca']);
        Route::delete('/pasos/{id}', [PasoController::class, 'destroy']);
        Route::get('/panel/resumen', [PasoController::class, 'resumenGeneral']);
        Route::apiResource('/vehiculos', VehiculoController::class);
        Route::get('/casetas', [CasetaController::class, 'index']);
        Route::post('/casetas', [CasetaController::class, 'storeCaseta']);
        Route::put('/casetas/{id}', [CasetaController::class, 'updateCaseta']);
        Route::delete('/casetas/{id}', [CasetaController::class, 'destroyCaseta']);
        Route::get('/alertas', [CasetaController::class, 'alertas']);
        Route::patch('/alertas/{id}/atender', [CasetaController::class, 'atenderAlerta']);
        Route::get('/tarifas', [CasetaController::class, 'tarifas']);
        Route::post('/tarifas/restaurar', [CasetaController::class, 'restaurarTarifas']);
        Route::post('/tarifas', [CasetaController::class, 'storeTarifa']);
        Route::put('/tarifas/{id}', [CasetaController::class, 'updateTarifa']);
        Route::delete('/tarifas/{id}', [CasetaController::class, 'destroyTarifa']);
        Route::get('/estado/inferencia', [CasetaController::class, 'estadoInferencia']);

        // Gestión de Usuarios y Lista Blanca Google OAuth
        Route::get('/usuarios', [UsuarioController::class, 'index']);
        Route::post('/usuarios', [UsuarioController::class, 'store']);
        Route::put('/usuarios/{id}', [UsuarioController::class, 'update']);
        Route::patch('/usuarios/{id}/estado', [UsuarioController::class, 'toggleEstado']);
        Route::delete('/usuarios/{id}', [UsuarioController::class, 'destroy']);
    });
});
