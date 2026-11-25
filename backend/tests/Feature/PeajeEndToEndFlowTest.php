<?php

namespace Tests\Feature;

use App\Models\Alerta;
use App\Models\Paso;
use App\Models\User;
use App\Models\Vehiculo;
use Database\Seeders\DatabaseSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\Client\Factory as HttpClientFactory;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;

class PeajeEndToEndFlowTest extends TestCase
{
    use RefreshDatabase;

    private string $tinyJpegBase64;

    protected function setUp(): void
    {
        parent::setUp();

        $this->seed(DatabaseSeeder::class);

        config()->set('services.google.client_id', 'web-client-id.apps.googleusercontent.com');
        config()->set('services.google.android_client_id', 'android-client-id.apps.googleusercontent.com');
        config()->set('services.inference.url', 'https://mock-pod-8000.proxy.runpod.net');
        config()->set('services.ollama.url', 'https://mock-pod-8000.proxy.runpod.net/ollama');
        config()->set('services.ollama.model', 'llama3.2:3b');

        $this->tinyJpegBase64 = 'data:image/jpeg;base64,/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////wgALCAABAAEBAREA/8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABPxA=';
    }

    private function resetHttpFake(callable|array $stubs): void
    {
        Http::swap(new HttpClientFactory());
        Http::fake($stubs);
    }

    private function loginConGoogle(string $email, string $token = 'valid-token'): string
    {
        $this->resetHttpFake([
            'https://oauth2.googleapis.com/tokeninfo*' => Http::response([
                'aud' => 'web-client-id.apps.googleusercontent.com',
                'email' => $email,
                'email_verified' => 'true',
                'name' => 'Usuario Test',
            ], 200),
        ]);

        $resp = $this->postJson('/api/v1/auth/google', ['id_token' => $token]);
        $resp->assertStatus(200)->assertJsonPath('success', true);

        return $resp->json('token');
    }

    public function test_google_oauth_config_y_validaciones_lista_blanca(): void
    {
        $this->getJson('/api/v1/auth/config')
            ->assertStatus(200)
            ->assertJson([
                'google_client_id' => 'web-client-id.apps.googleusercontent.com',
                'google_android_client_id' => 'android-client-id.apps.googleusercontent.com',
                'google_oauth_enabled' => true,
            ]);

        // Token inválido -> 401
        $this->resetHttpFake([
            'https://oauth2.googleapis.com/tokeninfo*' => Http::response(['error' => 'invalid_token'], 400),
        ]);
        $this->postJson('/api/v1/auth/google', ['id_token' => 'bad'])->assertStatus(401);

        // Usuario no registrado en lista blanca -> 403
        $this->resetHttpFake([
            'https://oauth2.googleapis.com/tokeninfo*' => Http::response([
                'aud' => 'web-client-id.apps.googleusercontent.com',
                'email' => 'intruso@gmail.com',
                'email_verified' => true,
            ], 200),
        ]);
        $this->postJson('/api/v1/auth/google', ['id_token' => 'intruso'])->assertStatus(403);

        // Usuario inactivo -> 403
        User::where('email_google', 'operador@peaje.com')->update(['activo' => false]);
        $this->resetHttpFake([
            'https://oauth2.googleapis.com/tokeninfo*' => Http::response([
                'aud' => 'android-client-id.apps.googleusercontent.com',
                'email' => 'operador@peaje.com',
                'email_verified' => true,
            ], 200),
        ]);
        $this->postJson('/api/v1/auth/google', ['id_token' => 'op-inactivo'])->assertStatus(403);

        // Reactivar operador y autenticar admin
        User::where('email_google', 'operador@peaje.com')->update(['activo' => true]);
        $adminToken = $this->loginConGoogle('admin@peaje.com');
        $this->app['auth']->forgetGuards();
        $this->withToken($adminToken)->getJson('/api/v1/auth/me')
            ->assertStatus(200)
            ->assertJsonPath('usuario.rol', 'administrador');
    }

    public function test_rutas_protegidas_y_stream_sse_autenticado(): void
    {
        // Todas las rutas protegidas incluyendo SSE deben exigir autenticación
        $this->getJson('/api/v1/vehiculos')->assertStatus(401);
        $this->getJson('/api/v1/stream/eventos')->assertStatus(401);
        $this->getJson('/api/v1/stream/eventos?token=token-falso')->assertStatus(401);

        $adminToken = $this->loginConGoogle('admin@peaje.com');

        // Crear un paso y alerta nuevos para verificar emisión SSE
        $paso = Paso::create([
            'placa_leida' => 'SSE123',
            'placa_normalizada' => 'SSE123',
            'confianza_ocr' => 0.96,
            'categoria_detectada' => 'auto',
            'ejes_detectados' => 2,
            'monto' => 10.00,
            'caseta_id' => 1,
            'estado' => 'Identificada no registrada',
            'pasajeros' => 2,
        ]);

        $alerta = Alerta::create([
            'paso_id' => $paso->id,
            'tipo' => 'placa_no_registrada',
            'mensaje' => 'Alerta SSE test',
            'atendida' => false,
        ]);

        $response = $this->get('/api/v1/stream/eventos?token=' . urlencode($adminToken) . '&once=1&last_paso_id=' . ($paso->id - 1) . '&last_alerta_id=' . ($alerta->id - 1));
        $response->assertStatus(200);
        $this->assertStringStartsWith('text/event-stream', (string) $response->headers->get('Content-Type'));

        $body = $response->streamedContent();
        $this->assertStringContainsString("id: {$paso->id}", $body);
        $this->assertStringContainsString('event: nuevo_paso', $body);
        $this->assertStringContainsString('SSE123', $body);
        $this->assertStringContainsString('event: nueva_alerta', $body);
        $this->assertStringContainsString('Alerta SSE test', $body);
    }

    public function test_control_de_roles_y_crud_completo_sin_password(): void
    {
        $operadorToken = $this->loginConGoogle('operador@peaje.com');
        $adminToken = $this->loginConGoogle('admin@peaje.com');

        // Operador solo lectura en vehículos, tarifas, casetas y usuarios
        $this->app['auth']->forgetGuards();
        $this->withToken($operadorToken)->getJson('/api/v1/vehiculos')->assertStatus(200);
        $this->withToken($operadorToken)->postJson('/api/v1/vehiculos', [
            'placa' => '9988ZZZ',
            'propietario' => 'Prueba',
            'categoria' => 'auto',
            'ejes' => 2,
        ])->assertStatus(403);
        $this->withToken($operadorToken)->postJson('/api/v1/tarifas', [
            'categoria' => 'camion',
            'ejes' => 7,
            'monto' => 90,
        ])->assertStatus(403);
        $this->withToken($operadorToken)->postJson('/api/v1/casetas', [
            'nombre' => 'Caseta Este',
            'ubicacion' => 'Km 99',
        ])->assertStatus(403);
        $this->withToken($operadorToken)->postJson('/api/v1/usuarios', [
            'nombre' => 'Nuevo',
            'email_google' => 'nuevo@gmail.com',
            'rol' => 'operador',
        ])->assertStatus(403);

        // Cambiar a token de Administrador limpiando cache del guard Sanctum en memoria
        $this->app['auth']->forgetGuards();

        // Administrador realiza CRUD completo de Vehículo
        $vehResp = $this->withToken($adminToken)->postJson('/api/v1/vehiculos', [
            'placa' => '7711-abc',
            'propietario' => 'Transportes Admin',
            'categoria' => 'auto',
            'ejes' => 2,
            'saldo' => 100,
        ]);
        $vehResp->assertStatus(201)->assertJsonPath('data.placa', '7711ABC');
        $vehId = $vehResp->json('data.id');

        $this->withToken($adminToken)->putJson("/api/v1/vehiculos/{$vehId}", [
            'saldo' => 150,
            'activo' => true,
        ])->assertStatus(200)->assertJsonPath('data.saldo', '150.00');
        $this->withToken($adminToken)->deleteJson("/api/v1/vehiculos/{$vehId}")->assertStatus(200);

        // CRUD Tarifa
        $tarifaResp = $this->withToken($adminToken)->postJson('/api/v1/tarifas', [
            'categoria' => 'camion',
            'ejes' => 7,
            'monto' => 95,
        ]);
        $tarifaResp->assertStatus(201);
        $tarifaId = $tarifaResp->json('data.id');
        $this->withToken($adminToken)->putJson("/api/v1/tarifas/{$tarifaId}", [
            'categoria' => 'camion',
            'ejes' => 7,
            'monto' => 98.5,
        ])->assertStatus(200);
        $this->withToken($adminToken)->deleteJson("/api/v1/tarifas/{$tarifaId}")->assertStatus(200);

        // CRUD Caseta
        $casetaResp = $this->withToken($adminToken)->postJson('/api/v1/casetas', [
            'nombre' => 'Caseta Este',
            'ubicacion' => 'Km 80',
        ]);
        $casetaResp->assertStatus(201);
        $casetaId = $casetaResp->json('data.id');
        $this->withToken($adminToken)->putJson("/api/v1/casetas/{$casetaId}", [
            'nombre' => 'Caseta Este Renovada',
            'ubicacion' => 'Km 81',
        ])->assertStatus(200);
        $this->withToken($adminToken)->deleteJson("/api/v1/casetas/{$casetaId}")->assertStatus(200);

        // CRUD Usuario (sin tiene_password)
        $userResp = $this->withToken($adminToken)->postJson('/api/v1/usuarios', [
            'nombre' => 'Docente Invitado',
            'email_google' => 'docente.real@gmail.com',
            'rol' => 'administrador',
        ]);
        $userResp->assertStatus(201)->assertJsonMissing(['tiene_password']);
        $userId = $userResp->json('data.id');
        $this->withToken($adminToken)->patchJson("/api/v1/usuarios/{$userId}/estado", ['activo' => false])->assertStatus(200);
        $this->withToken($adminToken)->deleteJson("/api/v1/usuarios/{$userId}")->assertStatus(200);
    }

    public function test_flujo_caseta_cobro_alertas_y_resumen(): void
    {
        Storage::fake('public');
        $operadorToken = $this->loginConGoogle('operador@peaje.com');
        $this->app['auth']->forgetGuards();

        // 1. Vehículo registrado con saldo suficiente (3142ABC tiene Bs. 50.00, auto 2 ejes = Bs. 5.00)
        $this->resetHttpFake([
            'https://mock-pod-8000.proxy.runpod.net/predict' => Http::response([
                'placa' => '3142-ABC',
                'confianza' => 0.94,
                'categoria' => 'auto',
                'ejes' => 2,
                'pasajeros' => 3,
                'latencia_ms' => 54.2,
            ], 200),
        ]);

        $res1 = $this->withToken($operadorToken)->postJson('/api/v1/pasos/frame', [
            'frame_base64' => $this->tinyJpegBase64,
            'caseta_id' => 1,
        ]);
        $res1->assertStatus(201)
            ->assertJsonPath('paso.placa_normalizada', '3142ABC')
            ->assertJsonPath('paso.estado', 'Registrada y con paso')
            ->assertJsonPath('paso.pasajeros', 3)
            ->assertJsonPath('alerta', null);

        $this->assertEquals('45.00', Vehiculo::where('placa', '3142ABC')->first()->saldo);
        Storage::disk('public')->assertExists(str_replace('/storage/', '', $res1->json('paso.imagen_url')));

        // 2. Vehículo registrado SIN saldo (1209OPL tiene Bs. 0.00)
        $this->resetHttpFake([
            'https://mock-pod-8000.proxy.runpod.net/predict' => Http::response([
                'placa' => '1209OPL',
                'confianza' => 0.91,
                'categoria' => 'auto',
                'ejes' => 2,
                'pasajeros' => 1,
                'latencia_ms' => 48.0,
            ], 200),
        ]);

        $res2 = $this->withToken($operadorToken)->postJson('/api/v1/pasos/frame', [
            'frame_base64' => $this->tinyJpegBase64,
            'caseta_id' => 1,
        ]);
        $res2->assertStatus(201)->assertJsonPath('alerta.tipo', 'sin_saldo');

        // 3. Placa NO registrada -> alerta placa_no_registrada (camión 3 ejes = Bs. 18.00)
        $this->resetHttpFake([
            'https://mock-pod-8000.proxy.runpod.net/predict' => Http::response([
                'placa' => '8888NUE',
                'confianza' => 0.89,
                'categoria' => 'camion',
                'ejes' => 3,
                'pasajeros' => 2,
                'latencia_ms' => 61.5,
            ], 200),
        ]);

        $res3 = $this->withToken($operadorToken)->postJson('/api/v1/pasos/frame', [
            'frame_base64' => $this->tinyJpegBase64,
            'caseta_id' => 1,
        ]);
        $res3->assertStatus(201)
            ->assertJsonPath('paso.estado', 'Identificada no registrada')
            ->assertJsonPath('paso.monto', '18.00')
            ->assertJsonPath('alerta.tipo', 'placa_no_registrada');

        $alertaId = $res3->json('alerta.id');
        $this->withToken($operadorToken)->patchJson("/api/v1/alertas/{$alertaId}/atender")
            ->assertStatus(200)
            ->assertJsonPath('alerta.atendida', true);

        // Resúmenes actualizados
        $this->withToken($operadorToken)->getJson('/api/v1/panel/resumen')
            ->assertStatus(200)
            ->assertJsonPath('vehiculos_registrados', 21);

        $this->withToken($operadorToken)->getJson('/api/v1/casetas/1/resumen')
            ->assertStatus(200)
            ->assertJsonPath('success', true);
    }

    public function test_consultas_placas_sugerencias_ocr_y_agente_conversacional(): void
    {
        $operadorToken = $this->loginConGoogle('operador@peaje.com');
        $this->app['auth']->forgetGuards();

        // Sugerencia OCR con múltiples confusiones simultáneas (I->1, S->5, O->0 para 1540QWE)
        $this->withToken($operadorToken)->postJson('/api/v1/placas/consultar', ['placa' => 'IS4O-QWE'])
            ->assertStatus(200)
            ->assertJsonPath('data.estado', 'No existe')
            ->assertJsonFragment(['1540QWE']);

        // Consulta por imagen exitosa
        $this->resetHttpFake([
            'https://mock-pod-8000.proxy.runpod.net/predict/ocr' => Http::response([
                'placa' => '4021-XYZ',
                'confianza' => 0.97,
            ], 200),
        ]);
        $this->withToken($operadorToken)->postJson('/api/v1/placas/consultar-imagen', [
            'imagen_base64' => $this->tinyJpegBase64,
        ])->assertStatus(200)
            ->assertJsonPath('data.estado', 'Registrada y con paso');

        // Consulta por imagen sin placa legible -> 422
        $this->resetHttpFake([
            'https://mock-pod-8000.proxy.runpod.net/predict/ocr' => Http::response([
                'placa' => 'SIN_PLACA',
                'confianza' => 0.0,
            ], 200),
        ]);
        $this->withToken($operadorToken)->postJson('/api/v1/placas/consultar-imagen', [
            'imagen_base64' => $this->tinyJpegBase64,
        ])->assertStatus(422);

        // Historial de placa
        $this->withToken($operadorToken)->getJson('/api/v1/placas/4021XYZ/historial')
            ->assertStatus(200)
            ->assertJsonPath('placa', '4021XYZ');

        // Agente conversacional: guardrail fuera de dominio
        $this->withToken($operadorToken)->postJson('/api/v1/agente/chat', [
            'mensaje' => 'Dame una receta de pizza casera',
        ])->assertStatus(200)
            ->assertJsonPath('en_dominio', false)
            ->assertJsonPath('estado', 'Fuera de dominio');

        // Agente: 4 estados + sugerencias "¿Quisiste decir..."
        $this->resetHttpFake([
            'https://mock-pod-8000.proxy.runpod.net/ollama/tags' => Http::response(['models' => []], 200),
        ]);

        // Estado 1: Registrada y con paso
        $this->withToken($operadorToken)->postJson('/api/v1/agente/chat', ['mensaje' => 'Consulta placa 4021XYZ'])
            ->assertStatus(200)->assertJsonPath('estado', 'Registrada y con paso');

        // Estado 2: Registrada sin paso
        $this->withToken($operadorToken)->postJson('/api/v1/agente/chat', ['mensaje' => 'Consulta placa 3142ABC'])
            ->assertStatus(200)->assertJsonPath('estado', 'Registrada sin paso');

        // Estado 3: Identificada no registrada
        $this->withToken($operadorToken)->postJson('/api/v1/agente/chat', ['mensaje' => 'Consulta placa 9999INV'])
            ->assertStatus(200)->assertJsonPath('estado', 'Identificada no registrada');

        // Estado 4: No existe + sugerencia OCR
        $respNoExiste = $this->withToken($operadorToken)->postJson('/api/v1/agente/chat', ['mensaje' => 'Consulta placa IS4OQWE']);
        $respNoExiste->assertStatus(200)->assertJsonPath('estado', 'No existe');
        $this->assertStringContainsString('¿Quisiste decir: 1540QWE?', $respNoExiste->json('respuesta'));

        // Agente con imagen sin placa legible -> pide otra foto
        $this->resetHttpFake([
            'https://mock-pod-8000.proxy.runpod.net/predict' => Http::response([
                'placa' => 'SIN_PLACA',
                'confianza' => 0.0,
                'categoria' => 'auto',
                'ejes' => 2,
                'pasajeros' => 1,
                'latencia_ms' => 45.0,
            ], 200),
        ]);
        $respIlegible = $this->withToken($operadorToken)->postJson('/api/v1/agente/chat', [
            'imagen_base64' => $this->tinyJpegBase64,
        ]);
        $respIlegible->assertStatus(200)->assertJsonPath('estado', 'Placa no legible');
        $this->assertStringContainsString('No se detectó una placa legible', $respIlegible->json('respuesta'));

        // Agente multi-imagen + Ollama LLM activo
        $this->resetHttpFake([
            'https://mock-pod-8000.proxy.runpod.net/predict' => Http::sequence()
                ->push(['placa' => '4021XYZ', 'confianza' => 0.95, 'categoria' => 'auto', 'ejes' => 2, 'pasajeros' => 2, 'latencia_ms' => 50.0], 200)
                ->push(['placa' => '1540QWE', 'confianza' => 0.93, 'categoria' => 'camion', 'ejes' => 3, 'pasajeros' => 1, 'latencia_ms' => 52.0], 200),
            'https://mock-pod-8000.proxy.runpod.net/ollama/tags' => Http::response([
                'models' => [['name' => 'llama3.2:3b']],
            ], 200),
            'https://mock-pod-8000.proxy.runpod.net/ollama/generate' => Http::response([
                'response' => 'En total suman 3 pasajeros y Bs. 45.00 entre ambos vehículos.',
            ], 200),
        ]);
        $respMulti = $this->withToken($operadorToken)->postJson('/api/v1/agente/chat', [
            'mensaje' => '¿Cuántos pasajeros y tarifa suman?',
            'imagenes_base64' => [$this->tinyJpegBase64, $this->tinyJpegBase64],
        ]);
        $respMulti->assertStatus(200)
            ->assertJsonPath('estado', 'Analisis multi-imagen')
            ->assertJsonPath('ollama_usado', true)
            ->assertJsonPath('resumen_lote.total_pasajeros', 3);

        // Estado de inferencia
        $this->resetHttpFake([
            'https://mock-pod-8000.proxy.runpod.net/' => Http::response([
                'status' => 'online',
                'models' => [
                    'm1_detector' => true,
                    'm1_ocr' => true,
                    'm2_segmentation' => true,
                    'm3_keypoints' => true,
                    'm4_passengers' => true,
                ],
            ], 200),
            'https://mock-pod-8000.proxy.runpod.net/ollama/tags' => Http::response([
                'models' => [['name' => 'llama3.2:3b']],
            ], 200),
        ]);
        $this->withToken($operadorToken)->getJson('/api/v1/estado/inferencia')
            ->assertStatus(200)
            ->assertJsonPath('status', 'online')
            ->assertJsonPath('ollama_status', 'online')
            ->assertJsonPath('modelos.m4_passengers', true);
    }

    public function test_modo_live_ignora_sin_placa_y_evita_duplicados_por_cooldown(): void
    {
        Storage::fake('public');
        $operadorToken = $this->loginConGoogle('operador@peaje.com');
        $this->app['auth']->forgetGuards();

        $pasosAntes = Paso::count();
        $saldoInicial = (float) Vehiculo::where('placa', '3142ABC')->first()->saldo;

        // 1. Frame vacío sin vehículo ni placa -> 200 sin registrar
        $this->resetHttpFake([
            'https://mock-pod-8000.proxy.runpod.net/predict' => Http::response([
                'vehiculo_detectado' => false,
                'placa' => 'SIN_PLACA',
                'confianza' => 0.0,
                'categoria' => 'ninguno',
                'ejes' => 0,
                'pasajeros' => 0,
                'latencia_ms' => 30.0,
                'imagen_size' => [640, 480],
                'vehiculos' => [],
                'detalles' => ['m2' => ['total_vehiculos' => 0]],
            ], 200),
        ]);
        $this->withToken($operadorToken)->postJson('/api/v1/pasos/frame', [
            'frame_base64' => $this->tinyJpegBase64,
            'caseta_id' => 1,
            'modo_live' => true,
        ])->assertStatus(200)
            ->assertJsonPath('registrado', false)
            ->assertJsonPath('motivo', 'sin_vehiculo');
        $this->assertEquals($pasosAntes, Paso::count());

        // 1b. Texto falso en calle cuando M2 detecta 0 vehículos -> también ignorado
        $this->resetHttpFake([
            'https://mock-pod-8000.proxy.runpod.net/predict' => Http::response([
                'vehiculo_detectado' => false,
                'placa' => 'AB1234',
                'confianza' => 0.5,
                'categoria' => 'ninguno',
                'ejes' => 0,
                'pasajeros' => 0,
                'latencia_ms' => 28.0,
                'imagen_size' => [640, 480],
                'vehiculos' => [],
                'detalles' => ['m2' => ['total_vehiculos' => 0]],
            ], 200),
        ]);
        $this->withToken($operadorToken)->postJson('/api/v1/pasos/frame', [
            'frame_base64' => $this->tinyJpegBase64,
            'caseta_id' => 1,
            'modo_live' => true,
        ])->assertStatus(200)
            ->assertJsonPath('registrado', false)
            ->assertJsonPath('motivo', 'sin_vehiculo');
        $this->assertEquals($pasosAntes, Paso::count());

        // 2. Vehículo presente pero OCR basura ("Y4") -> 200 esperando_placa
        $this->resetHttpFake([
            'https://mock-pod-8000.proxy.runpod.net/predict' => Http::response([
                'placa' => 'Y4',
                'confianza' => 0.4,
                'categoria' => 'auto',
                'ejes' => 2,
                'pasajeros' => 1,
                'latencia_ms' => 35.0,
                'imagen_size' => [640, 480],
                'vehiculos' => [['id' => 1, 'categoria' => 'auto', 'box' => [10, 10, 400, 400]]],
                'detalles' => ['m2' => ['total_vehiculos' => 1, 'bbox' => [10, 10, 400, 400]]],
            ], 200),
        ]);
        $this->withToken($operadorToken)->postJson('/api/v1/pasos/frame', [
            'frame_base64' => $this->tinyJpegBase64,
            'caseta_id' => 1,
            'modo_live' => true,
        ])->assertStatus(200)
            ->assertJsonPath('registrado', false)
            ->assertJsonPath('motivo', 'esperando_placa');
        $this->assertEquals($pasosAntes, Paso::count());

        // 2b. Vehículo lejano (< 8% del frame, ej. en la calle) -> 200 vehiculo_lejano sin registrar
        $this->resetHttpFake([
            'https://mock-pod-8000.proxy.runpod.net/predict' => Http::response([
                'vehiculo_detectado' => true,
                'placa' => '3142-ABC',
                'confianza' => 0.95,
                'categoria' => 'auto',
                'ejes' => 2,
                'pasajeros' => 1,
                'latencia_ms' => 35.0,
                'imagen_size' => [640, 480],
                'vehiculos' => [['id' => 1, 'categoria' => 'auto', 'box' => [10, 10, 110, 110]]],
                'detalles' => ['m2' => ['total_vehiculos' => 1, 'bbox' => [10, 10, 110, 110]]],
            ], 200),
        ]);
        $this->withToken($operadorToken)->postJson('/api/v1/pasos/frame', [
            'frame_base64' => $this->tinyJpegBase64,
            'caseta_id' => 1,
            'modo_live' => true,
        ])->assertStatus(200)
            ->assertJsonPath('registrado', false)
            ->assertJsonPath('motivo', 'vehiculo_lejano');
        $this->assertEquals($pasosAntes, Paso::count());

        // 2c. Solo Vista Previa -> devuelve detección pero NO guarda nada
        $this->withToken($operadorToken)->postJson('/api/v1/pasos/frame', [
            'frame_base64' => $this->tinyJpegBase64,
            'caseta_id' => 1,
            'modo_live' => true,
            'solo_preview' => true,
        ])->assertStatus(200)
            ->assertJsonPath('registrado', false)
            ->assertJsonPath('motivo', 'solo_preview');
        $this->assertEquals($pasosAntes, Paso::count());

        // 3. Primera detección válida en vivo -> 201 nuevo_registro y descuenta saldo 1 vez (Bs. 5.00)
        $this->resetHttpFake([
            'https://mock-pod-8000.proxy.runpod.net/predict' => Http::response([
                'vehiculo_detectado' => true,
                'placa' => '3142-ABC',
                'confianza' => 0.96,
                'categoria' => 'auto',
                'ejes' => 2,
                'pasajeros' => 2,
                'latencia_ms' => 42.0,
                'imagen_size' => [640, 480],
                'vehiculos' => [['id' => 1, 'categoria' => 'auto', 'box' => [20, 20, 500, 450]]],
                'detalles' => [
                    'm1' => ['placa' => '3142-ABC', 'bbox' => [200, 340, 320, 380]],
                    'm2' => ['total_vehiculos' => 1, 'bbox' => [20, 20, 500, 450]],
                    'm3' => ['ejes' => 2, 'puntos' => [[120.0, 410.0, 0.9], [410.0, 410.0, 0.9]]],
                    'm4' => ['pasajeros' => 2, 'cajas' => [[150.0, 100.0, 230.0, 220.0]]],
                ],
            ], 200),
        ]);
        $nuevoPasoResp = $this->withToken($operadorToken)->postJson('/api/v1/pasos/frame', [
            'frame_base64' => $this->tinyJpegBase64,
            'caseta_id' => 1,
            'modo_live' => true,
            'cooldown_segundos' => 20,
        ]);
        $nuevoPasoResp->assertStatus(201)
            ->assertJsonPath('registrado', true)
            ->assertJsonPath('motivo', 'nuevo_registro')
            ->assertJsonPath('deteccion.m3.puntos.0.0', 120);

        $pasoNuevoId = $nuevoPasoResp->json('paso.id');
        $this->assertEquals($pasosAntes + 1, Paso::count());
        $this->assertEquals($saldoInicial - 5.00, (float) Vehiculo::where('placa', '3142ABC')->first()->saldo);

        // 4. Mismo vehículo 1 segundo después -> 200 duplicado_reciente sin cobrar doble
        $this->withToken($operadorToken)->postJson('/api/v1/pasos/frame', [
            'frame_base64' => $this->tinyJpegBase64,
            'caseta_id' => 1,
            'modo_live' => true,
            'cooldown_segundos' => 20,
        ])->assertStatus(200)
            ->assertJsonPath('registrado', false)
            ->assertJsonPath('motivo', 'duplicado_reciente');

        $this->assertEquals($pasosAntes + 1, Paso::count());
        $this->assertEquals($saldoInicial - 5.00, (float) Vehiculo::where('placa', '3142ABC')->first()->saldo);

        // 5. Operador NO puede eliminar pasos ni restaurar tarifas (403); Admin sí puede y reembolsa saldo
        $this->withToken($operadorToken)->deleteJson("/api/v1/pasos/{$pasoNuevoId}")->assertStatus(403);
        $this->withToken($operadorToken)->postJson('/api/v1/tarifas/restaurar')->assertStatus(403);

        $adminToken = $this->loginConGoogle('admin@peaje.com');
        $this->app['auth']->forgetGuards();

        $this->withToken($adminToken)->deleteJson("/api/v1/pasos/{$pasoNuevoId}")->assertStatus(200);
        $this->assertEquals($saldoInicial, (float) Vehiculo::where('placa', '3142ABC')->first()->saldo);

        // Crear paso falso SINPLACA y limpiarlo masivamente
        Paso::create([
            'placa_leida' => 'SIN_PLACA',
            'placa_normalizada' => 'SINPLACA',
            'confianza_ocr' => 0.0,
            'categoria_detectada' => 'auto',
            'ejes_detectados' => 2,
            'monto' => 5.00,
            'caseta_id' => 1,
            'estado' => 'Identificada no registrada',
        ]);
        $this->withToken($adminToken)->deleteJson('/api/v1/pasos/limpiar/sin-placa')
            ->assertStatus(200)
            ->assertJsonPath('eliminados', 1);

        // Restaurar tarifas oficiales tras borrar una
        \App\Models\Tarifa::where('categoria', 'moto')->delete();
        $this->withToken($adminToken)->postJson('/api/v1/tarifas/restaurar')
            ->assertStatus(200)
            ->assertJsonPath('success', true);
        $this->assertEquals('2.00', \App\Models\Tarifa::where('categoria', 'moto')->first()->monto);
    }
}
