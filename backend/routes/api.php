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

    // Rutas de Login públicas
    Route::post('/auth/google', [AuthController::class, 'googleLogin']);
    Route::post('/auth/login', [AuthController::class, 'credentialsLogin']);

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
        Route::get('/panel/resumen', [PasoController::class, 'resumenGeneral']);
        Route::apiResource('/vehiculos', VehiculoController::class);
        Route::get('/casetas', [CasetaController::class, 'index']);
        Route::get('/alertas', [CasetaController::class, 'alertas']);
        Route::patch('/alertas/{id}/atender', [CasetaController::class, 'atenderAlerta']);
        Route::get('/tarifas', [CasetaController::class, 'tarifas']);
        Route::get('/estado/inferencia', [CasetaController::class, 'estadoInferencia']);
    });
});
