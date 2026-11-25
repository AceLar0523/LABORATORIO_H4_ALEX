<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Alerta;
use App\Models\Caseta;
use App\Models\Paso;
use App\Models\Tarifa;
use App\Models\User;
use App\Models\Vehiculo;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Http;

class AgenteController extends Controller
{
    private const MAX_IMAGENES = 6;
    private const MAX_HISTORIAL = 12;

    /**
     * Endpoint principal del Agente Conversacional Inteligente.
     * Exclusivo del Sistema Inteligente de Control de Peaje:
     * - Rechaza consultas fuera de dominio.
     * - Analiza 1 o varias imágenes vehiculares (M1-M4 + tarifa + estado en BD).
     * - Responde preguntas operativas y de seguimiento de forma interactiva.
     */
    public function chat(Request $request)
    {
        $request->validate([
            'mensaje' => 'nullable|string|max:2000',
            'imagen_base64' => 'nullable|string',
            'imagenes_base64' => 'nullable|array',
            'imagenes_base64.*' => 'string',
            'historial' => 'nullable|array',
        ]);

        $mensaje = trim((string) $request->input('mensaje', ''));
        $historial = $this->normalizarHistorial($request->input('historial', []));
        $imagenes = $this->extraerImagenesEntrada($request);

        if ($mensaje === '' && count($imagenes) === 0) {
            return response()->json([
                'respuesta' => 'Por favor escribe una consulta sobre el sistema de peaje o adjunta una o varias imágenes vehiculares para analizarlas.',
                'estado' => 'Entrada vacía',
                'en_dominio' => true,
            ], 422);
        }

        // 1. Si hay imágenes adjuntas: analizar cada una con RunPod (M1-M4) + BD de peaje
        if (count($imagenes) > 0) {
            $avisoLimite = count($imagenes) > self::MAX_IMAGENES
                ? 'Se procesaron las primeras ' . self::MAX_IMAGENES . ' imágenes de las ' . count($imagenes) . ' enviadas.'
                : null;
            $imagenes = array_slice($imagenes, 0, self::MAX_IMAGENES);

            // Si el usuario acompañó las imágenes con texto explícitamente ajeno al proyecto
            if ($mensaje !== '' && $this->esExplicitamenteFueraDeDominio($mensaje) && !$this->tieneSenalDeProyecto($mensaje, $historial)) {
                return response()->json([
                    'respuesta' => 'Solo respondo consultas e imágenes relacionadas con el Sistema Inteligente de Control de Peaje (placas, vehículos, tarifas, ejes, pasajeros, alertas, casetas y modelos M1–M4). Si deseas analizar las imágenes para control de peaje, envíalas con una pregunta del sistema o sin texto ajeno al proyecto.',
                    'estado' => 'Fuera de dominio',
                    'en_dominio' => false,
                    'ollama_usado' => false,
                ]);
            }

            return $this->procesarLoteImagenes($imagenes, $mensaje, $historial, $avisoLimite);
        }

        // 2. Consulta de solo texto: aplicar guardrail estricto de dominio
        if (!$this->esConsultaDelProyecto($mensaje, $historial)) {
            return response()->json([
                'respuesta' => "Soy el asistente exclusivo del **Sistema Inteligente de Control de Peaje**. No respondo consultas ajenas al proyecto.\n\n" .
                    "Puedo ayudarte con:\n" .
                    "• Analizar **1 o varias imágenes** de vehículos (placa M1, categoría M2, ejes M3, pasajeros M4, tarifa estimada y estado en BD).\n" .
                    "• Consultar una **placa** específica (por ejemplo: `4021XYZ`).\n" .
                    "• Ver **tarifas vigentes**, **alertas pendientes**, **recaudación**, **casetas**, **vehículos registrados** y **estado de modelos IA**.",
                'estado' => 'Fuera de dominio',
                'en_dominio' => false,
                'ollama_usado' => false,
            ]);
        }

        // 3. Saludo o solicitud de capacidades dentro del proyecto
        if ($this->esSaludoInicial($mensaje) && !$this->tieneSenalDeProyecto($mensaje, [])) {
            $resumen = $this->obtenerSnapshotSistema();
            return response()->json([
                'respuesta' => "Hola, soy el **Asistente Exclusivo de Control de Peaje**. Estoy conectado a la base operativa ({$resumen['vehiculos']} vehículos, {$resumen['total_pasos']} pasos registrados, {$resumen['alertas_pendientes']} alertas pendientes).\n\n" .
                    "Puedes enviarme **una o varias fotos de vehículos** al mismo tiempo para analizarlas una por una, consultar una **placa**, o preguntarme por **tarifas, recaudación, alertas o casetas**.",
                'estado' => 'Asistente listo',
                'en_dominio' => true,
                'ollama_usado' => false,
            ]);
        }

        // 4. Consulta de placas mencionadas en el texto
        $placas = $this->extraerPlacas($mensaje);
        if (count($placas) > 0) {
            return $this->responderConsultaPlacas($placas, $mensaje, $historial);
        }

        // 5. Consulta operativa o de seguimiento interactivo sobre el proyecto
        return $this->responderConsultaOperativa($mensaje, $historial);
    }

    /**
     * Analiza un lote de 1..N imágenes en RunPod (/predict) y cruza con Tarifa + Vehículo + Pasos.
     */
    private function procesarLoteImagenes(array $imagenes, string $mensaje, array $historial, ?string $avisoLimite)
    {
        $analisis = [];
        $totalTarifa = 0.0;
        $totalPasajeros = 0;
        $exitosas = 0;
        $placasOk = [];
        $noRegistradas = 0;
        $sinSaldo = 0;

        foreach ($imagenes as $idx => $dataUri) {
            $numero = $idx + 1;
            $item = $this->analizarImagenEnRunPod($dataUri, $numero);
            $analisis[] = $item;

            if ($item['exito']) {
                $exitosas++;
                $totalTarifa += (float) $item['tarifa_estimada'];
                $totalPasajeros += (int) $item['pasajeros'];
                if ($item['placa_normalizada'] !== '') {
                    $placasOk[] = $item['placa_normalizada'];
                }
                if ($item['estado_bd'] === 'Identificada no registrada') {
                    $noRegistradas++;
                }
                if (!empty($item['saldo_insuficiente'])) {
                    $sinSaldo++;
                }
            }
        }

        $resumenLote = [
            'total_imagenes' => count($imagenes),
            'exitosas' => $exitosas,
            'placas' => $placasOk,
            'total_tarifa_bs' => round($totalTarifa, 2),
            'total_pasajeros' => $totalPasajeros,
            'no_registradas' => $noRegistradas,
            'saldo_insuficiente' => $sinSaldo,
        ];

        $bloques = [];
        if ($avisoLimite !== null) {
            $bloques[] = $avisoLimite;
        }

        foreach ($analisis as $item) {
            if (!$item['exito']) {
                $bloques[] = "**Imagen #{$item['indice']}**: No se pudo completar la inferencia ({$item['error']}).";
                continue;
            }

            $placaTxt = $item['placa_normalizada'] !== '' ? $item['placa_normalizada'] : ($item['placa_detectada'] ?: 'No legible');
            $confPct = round(((float) $item['confianza_ocr']) * 100, 1);
            $formatoTxt = $item['formato_placa'] ? " ({$item['formato_placa']})" : '';
            $tarifaTxt = number_format((float) $item['tarifa_estimada'], 2);

            $detalleBd = match ($item['estado_bd']) {
                'Registrada y con paso' => "**Registrada y con paso** ({$item['total_pasos']} paso(s) | Propietario: {$item['propietario']} | Saldo: Bs. " . number_format((float) $item['saldo'], 2) . ')',
                'Registrada sin paso' => "**Registrada sin paso** (Propietario: {$item['propietario']} | Saldo: Bs. " . number_format((float) $item['saldo'], 2) . ')',
                'Identificada no registrada' => '**Identificada no registrada** (sin alta en padrón vehicular; requeriría alerta en caseta)',
                'Placa no legible' => '**Placa no legible**: No se detectó una placa legible en esta imagen. Por favor sube otra fotografía más nítida o frontal de la placa, o escribe la placa en texto.',
                default => '**No existe** (sin registros en padrón vehicular ni en historial de pasos)',
            };

            if (!empty($item['sugerencias'])) {
                $detalleBd .= ' | ¿Quisiste decir: ' . implode(', ', $item['sugerencias']) . '?';
            }

            if (!empty($item['saldo_insuficiente'])) {
                $detalleBd .= ' [ALERTA: saldo inferior a tarifa]';
            }

            $linea = "**Imagen #{$item['indice']}**\n" .
                "• **Placa (M1):** `{$placaTxt}`{$formatoTxt} — Confianza OCR: {$confPct}%\n" .
                "• **Clasificación (M2/M3/M4):** {$item['categoria']} | {$item['ejes']} ejes | {$item['pasajeros']} pasajero(s)\n" .
                "• **Tarifa estimada:** Bs. {$tarifaTxt} *(consulta solo lectura)*\n" .
                "• **Estado en BD:** {$detalleBd}";

            if ($item['latencia_ms'] !== null) {
                $linea .= " | Latencia: {$item['latencia_ms']} ms";
            }

            $bloques[] = $linea;
        }

        if (count($imagenes) > 1) {
            $placasResumen = count($placasOk) > 0 ? implode(', ', $placasOk) : 'Ninguna legible';
            $bloques[] = "**Resumen consolidado ({$exitosas}/" . count($imagenes) . " imágenes analizadas)**\n" .
                "• **Placas detectadas:** {$placasResumen}\n" .
                "• **Total de pasajeros:** {$totalPasajeros}\n" .
                "• **Suma estimada de tarifas:** Bs. " . number_format($totalTarifa, 2) . "\n" .
                "• **Observaciones:** {$noRegistradas} no registrada(s), {$sinSaldo} con saldo insuficiente.";
        }

        $reporteDeterminista = implode("\n\n", $bloques);
        $ollamaUsado = false;
        $respuestaFinal = $reporteDeterminista;

        if ($mensaje !== '') {
            $contextoJson = json_encode([
                'pregunta_usuario' => $mensaje,
                'resumen_lote' => $resumenLote,
                'analisis_por_imagen' => $analisis,
            ], JSON_UNESCAPED_UNICODE);

            $instruccion = "Eres el Agente Exclusivo del Sistema Inteligente de Control de Peaje. " .
                "Responde en español a la pregunta del usuario basándote ÚNICAMENTE en los resultados reales de inferencia y base de datos proporcionados. " .
                "Mantén exactos los números de placa, categorías, ejes, pasajeros y montos en Bs. No inventes registros.";

            $comentarioLlm = $this->llamarOllama($instruccion, $contextoJson, $mensaje, $historial);
            if ($comentarioLlm !== null) {
                $ollamaUsado = true;
                $respuestaFinal = $reporteDeterminista . "\n\n**Respuesta sobre tu consulta:**\n" . $comentarioLlm;
            }
        }

        $primeraPlaca = count($placasOk) > 0 ? $placasOk[0] : null;
        $estadoFinal = count($imagenes) > 1
            ? 'Analisis multi-imagen'
            : ($analisis[0]['estado_bd'] ?? 'Analisis de imagen');

        return response()->json([
            'respuesta' => $respuestaFinal,
            'estado' => $estadoFinal,
            'placa_consultada' => $primeraPlaca,
            'datos_consulta' => count($imagenes) === 1 ? $analisis[0] : $resumenLote,
            'analisis_imagenes' => $analisis,
            'resumen_lote' => $resumenLote,
            'en_dominio' => true,
            'ollama_usado' => $ollamaUsado,
        ]);
    }

    /**
     * Envía una imagen base64 a RunPod (/predict) sin registrar paso ni descontar saldo.
     */
    private function analizarImagenEnRunPod(string $dataUri, int $indice): array
    {
        $inferenceUrl = rtrim((string) config('services.inference.url', ''), '/');
        if ($inferenceUrl === '') {
            return [
                'indice' => $indice,
                'exito' => false,
                'error' => 'INFERENCE_URL no está configurado en el servidor.',
            ];
        }

        $extension = 'jpg';
        $base64Payload = $dataUri;
        if (str_starts_with($dataUri, 'data:image/')) {
            if (preg_match('/^data:image\/([a-zA-Z0-9+]+);base64,(.*)$/s', $dataUri, $m)) {
                $ext = strtolower($m[1]);
                $extension = $ext === 'jpeg' ? 'jpg' : $ext;
                $base64Payload = $m[2];
            }
        }

        $binario = base64_decode($base64Payload, true);
        if ($binario === false || strlen($binario) < 32) {
            return [
                'indice' => $indice,
                'exito' => false,
                'error' => 'Formato de imagen base64 inválido o vacío.',
            ];
        }

        try {
            $resp = Http::timeout(30)
                ->attach('file', $binario, "consulta_{$indice}.{$extension}")
                ->post("{$inferenceUrl}/predict");

            if (!$resp->successful()) {
                return [
                    'indice' => $indice,
                    'exito' => false,
                    'error' => "Motor de inferencia devolvió HTTP {$resp->status()}",
                ];
            }

            $pred = $resp->json();
            if (!is_array($pred)) {
                return [
                    'indice' => $indice,
                    'exito' => false,
                    'error' => 'Respuesta no válida del motor de inferencia.',
                ];
            }

            $placaBruta = trim((string) ($pred['placa'] ?? ''));
            $placaNorm = PlacaController::normalizar($placaBruta);
            if (in_array($placaNorm, ['SINPLACA', 'NOLEIBLE', 'NORECONOCIDA', 'NONE', 'NULL'], true)) {
                $placaNorm = '';
            }

            $categoria = strtolower(trim((string) ($pred['categoria'] ?? 'auto')));
            $ejes = max(1, (int) ($pred['ejes'] ?? 2));
            $pasajeros = max(0, (int) ($pred['pasajeros'] ?? 0));
            $confianza = (float) ($pred['confianza'] ?? 0);
            $formatoPlaca = $pred['formato_placa'] ?? null;
            $latenciaMs = isset($pred['latencia_ms']) ? round((float) $pred['latencia_ms'], 2) : null;

            $tarifa = Tarifa::where('categoria', $categoria)->where('ejes', $ejes)->first()
                ?? Tarifa::where('categoria', $categoria)->first();
            $montoTarifa = $tarifa ? (float) $tarifa->monto : 10.00;

            $estadoBd = 'Placa no legible';
            $vehiculo = null;
            $totalPasos = 0;
            $ultimoPaso = null;
            $sugerencias = [];
            $saldoInsuficiente = false;

            if ($placaNorm !== '') {
                $consultaBd = PlacaController::obtenerEstadoPlaca($placaNorm);
                $estadoBd = $consultaBd['estado'];
                $vehiculo = $consultaBd['vehiculo'];
                $totalPasos = (int) $consultaBd['total_pasos'];
                $ultimoPaso = $consultaBd['ultimo_paso'];
                $sugerencias = $consultaBd['sugerencias'] ?? [];

                if ($vehiculo && (float) $vehiculo->saldo < $montoTarifa) {
                    $saldoInsuficiente = true;
                }
            }

            return [
                'indice' => $indice,
                'exito' => true,
                'placa_detectada' => $placaBruta,
                'placa_normalizada' => $placaNorm,
                'formato_placa' => $formatoPlaca,
                'confianza_ocr' => $confianza,
                'categoria' => $categoria,
                'ejes' => $ejes,
                'pasajeros' => $pasajeros,
                'tarifa_estimada' => round($montoTarifa, 2),
                'latencia_ms' => $latenciaMs,
                'estado_bd' => $estadoBd,
                'propietario' => $vehiculo?->propietario,
                'saldo' => $vehiculo ? (float) $vehiculo->saldo : null,
                'saldo_insuficiente' => $saldoInsuficiente,
                'total_pasos' => $totalPasos,
                'ultimo_paso_fecha' => is_array($ultimoPaso) ? ($ultimoPaso['fecha'] ?? null) : null,
                'sugerencias' => $sugerencias,
            ];
        } catch (\Exception $e) {
            return [
                'indice' => $indice,
                'exito' => false,
                'error' => 'Error de conexión con RunPod: ' . $e->getMessage(),
            ];
        }
    }

    /**
     * Responde consultas con 1 o más placas mencionadas en el texto.
     */
    private function responderConsultaPlacas(array $placas, string $mensaje, array $historial)
    {
        $resultados = [];
        $lineas = [];

        foreach ($placas as $placaRaw) {
            $placaNorm = PlacaController::normalizar($placaRaw);
            $res = PlacaController::obtenerEstadoPlaca($placaNorm);
            $resultados[$placaNorm] = $res;

            $v = $res['vehiculo'];
            $ultimo = $res['ultimo_paso'];

            $texto = match ($res['estado']) {
                'Registrada y con paso' => "**Placa `{$placaNorm}` — Registrada y con paso**\n" .
                    "• Propietario: {$v->propietario} | Categoría: {$v->categoria} ({$v->ejes} ejes) | Saldo: Bs. " . number_format((float) $v->saldo, 2) . "\n" .
                    "• Pasos totales: {$res['total_pasos']} | Último paso: " . ($ultimo['fecha'] ?? 'N/D') . " en " . ($ultimo['caseta'] ?? 'Caseta General') . " (Bs. " . ($ultimo['monto'] ?? '0.00') . ").",
                'Registrada sin paso' => "**Placa `{$placaNorm}` — Registrada sin paso**\n" .
                    "• Propietario: {$v->propietario} | Categoría: {$v->categoria} ({$v->ejes} ejes) | Saldo: Bs. " . number_format((float) $v->saldo, 2) . "\n" .
                    "• Aún no registra pasos por casetas.",
                'Identificada no registrada' => "**Placa `{$placaNorm}` — Identificada no registrada**\n" .
                    "• Registra {$res['total_pasos']} paso(s) detectado(s) sin estar dada de alta en el padrón vehicular.\n" .
                    "• Última detección: " . ($ultimo['fecha'] ?? 'N/D') . " en " . ($ultimo['caseta'] ?? 'Caseta General') . " (Bs. " . ($ultimo['monto'] ?? '0.00') . ")." .
                    (!empty($res['sugerencias']) ? "\n• ¿Quisiste decir: " . implode(', ', $res['sugerencias']) . '?' : ''),
                default => "**Placa `{$placaNorm}` — No existe**\n" .
                    "• No figura en vehículos registrados ni en historial de pasos." .
                    (!empty($res['sugerencias']) ? ' ¿Quisiste decir: ' . implode(', ', $res['sugerencias']) . '?' : ''),
            };

            $lineas[] = $texto;
        }

        $baseRespuesta = implode("\n\n", $lineas);
        $primeraPlaca = PlacaController::normalizar($placas[0]);
        $primerRes = $resultados[$primeraPlaca];
        $ollamaUsado = false;

        $instruccion = "Eres el Agente Exclusivo del Sistema Inteligente de Control de Peaje. " .
            "Responde en español de forma breve usando SOLO estos datos reales de placas y base de datos. Mantén exactos placas, montos y fechas y no inventes registros.";
        $llm = $this->llamarOllama($instruccion, json_encode($resultados, JSON_UNESCAPED_UNICODE), $mensaje, $historial);
        if ($llm !== null) {
            $ollamaUsado = true;
            $baseRespuesta .= "\n\n**Nota del asistente:**\n" . $llm;
        }

        return response()->json([
            'respuesta' => $baseRespuesta,
            'estado' => count($placas) > 1 ? 'Consulta multi-placa' : $primerRes['estado'],
            'placa_consultada' => $primeraPlaca,
            'datos_consulta' => count($placas) === 1 ? $primerRes : $resultados,
            'en_dominio' => true,
            'ollama_usado' => $ollamaUsado,
        ]);
    }

    /**
     * Responde preguntas operativas sobre tarifas, alertas, casetas, pasos, recaudación, modelos IA o seguimiento.
     */
    private function responderConsultaOperativa(string $mensaje, array $historial)
    {
        $lower = mb_strtolower($mensaje, 'UTF-8');

        $tarifas = Tarifa::orderBy('id')->get(['categoria', 'ejes', 'monto']);
        $alertasPendientesList = Alerta::with('paso')
            ->where('atendida', false)
            ->orderByDesc('id')
            ->take(5)
            ->get(['id', 'paso_id', 'tipo', 'mensaje', 'created_at']);
        $casetas = Caseta::withCount('pasos')->get(['id', 'nombre', 'ubicacion']);
        $ultimosPasos = Paso::with('caseta:id,nombre')
            ->orderByDesc('id')
            ->take(5)
            ->get(['id', 'placa_normalizada', 'categoria_detectada', 'ejes_detectados', 'pasajeros', 'monto', 'estado', 'caseta_id', 'created_at']);

        $snapshot = [
            'vehiculos_registrados' => Vehiculo::count(),
            'usuarios_autorizados' => User::where('activo', true)->count(),
            'total_pasos' => Paso::count(),
            'recaudacion_total_bs' => round((float) Paso::sum('monto'), 2),
            'pasajeros_totales_registrados' => (int) Paso::sum('pasajeros'),
            'alertas_pendientes' => Alerta::where('atendida', false)->count(),
            'alertas_recientes' => $alertasPendientesList,
            'tarifas' => $tarifas,
            'casetas' => $casetas,
            'ultimos_pasos' => $ultimosPasos,
            'modelos_ia' => [
                'M1' => 'Detección de placas y OCR (fast-plate-ocr)',
                'M2' => 'Clasificación vehicular por segmentación (auto, minibus, bus, camion, trailer, moto)',
                'M3' => 'Detección y conteo de ejes por keypoints',
                'M4' => 'Conteo de pasajeros / ocupantes detectados',
            ],
        ];

        $secciones = [];

        if (preg_match('/(tarifa|precio|cobro|monto|costo|cu[aá]nto paga|ejes)/u', $lower)) {
            $listaTarifas = $tarifas->map(fn ($t) => "• **{$t->categoria}** ({$t->ejes} ejes): **Bs. " . number_format((float) $t->monto, 2) . '**')->implode("\n");
            $secciones[] = "**Tarifas vigentes del peaje:**\n" . ($listaTarifas ?: '• Sin tarifas configuradas.');
        }

        if (preg_match('/(alerta|incidencia|sin saldo|no registrad|pendiente)/u', $lower)) {
            $textoAlertas = $alertasPendientesList->map(fn ($a) => "• [{$a->tipo}] {$a->mensaje}")->implode("\n");
            $secciones[] = "**Alertas pendientes:** {$snapshot['alertas_pendientes']}\n" .
                ($textoAlertas !== '' ? $textoAlertas : '• No hay alertas sin atender en este momento.');
        }

        if (preg_match('/(caseta|estaci[oó]n|carril|puesto)/u', $lower)) {
            $listaCasetas = $casetas->map(fn ($c) => "• **{$c->nombre}** ({$c->ubicacion}): {$c->pasos_count} paso(s)")->implode("\n");
            $secciones[] = "**Casetas registradas:**\n" . ($listaCasetas ?: '• Sin casetas registradas.');
        }

        if (preg_match('/(recaudaci[oó]n|ingreso|pasos|resumen|estad[ií]stica|veh[ií]culo|padr[oó]n|hoy|total|usuario)/u', $lower)) {
            $secciones[] = "**Resumen operativo del sistema:**\n" .
                "• **Vehículos registrados:** {$snapshot['vehiculos_registrados']} | **Usuarios autorizados:** {$snapshot['usuarios_autorizados']}\n" .
                "• **Pasos registrados:** {$snapshot['total_pasos']} | **Recaudación acumulada:** Bs. " . number_format($snapshot['recaudacion_total_bs'], 2) . "\n" .
                "• **Alertas pendientes:** {$snapshot['alertas_pendientes']} | **Pasajeros acumulados en pasos:** {$snapshot['pasajeros_totales_registrados']}";
        }

        if (preg_match('/(modelo|m1|m2|m3|m4|yolo|ocr|arquitectura|c[oó]mo funciona|pipeline)/u', $lower)) {
            $secciones[] = "**Pipeline de Visión Artificial (M1–M4):**\n" .
                "• **M1:** Detección de placa vehicular + OCR (`fast-plate-ocr`).\n" .
                "• **M2:** Clasificación de categoría vehicular (`auto`, `minibus`, `bus`, `camion`, `trailer`, `moto`).\n" .
                "• **M3:** Conteo de ejes mediante keypoints.\n" .
                "• **M4:** Estimación de pasajeros visibles.";
        }

        // Si el usuario hace una pregunta de seguimiento sobre imágenes o respuestas previas en el historial
        $contextoSeguimiento = $this->extraerSeguimientoDeHistorial($mensaje, $historial);
        if ($contextoSeguimiento !== null) {
            array_unshift($secciones, $contextoSeguimiento);
        }

        if (count($secciones) === 0) {
            $secciones[] = "**Estado actual del Sistema de Peaje:**\n" .
                "• Vehículos registrados: {$snapshot['vehiculos_registrados']} | Pasos: {$snapshot['total_pasos']} | Recaudación: Bs. " . number_format($snapshot['recaudacion_total_bs'], 2) . " | Alertas pendientes: {$snapshot['alertas_pendientes']}.\n" .
                "• Puedes consultarme una **placa**, **tarifas**, **alertas**, **casetas**, o enviarme **una o varias fotos de vehículos**.";
        }

        $respuestaFinal = implode("\n\n", $secciones);
        $ollamaUsado = false;

        $instruccion = "Eres el Agente Exclusivo del Sistema Inteligente de Control de Peaje. " .
            "Responde ÚNICAMENTE sobre este proyecto de peaje inteligente usando los datos reales del sistema y el historial de la conversación. " .
            "Si el historial incluye resultados de análisis de imágenes previas (placas, pasajeros, tarifas, categorías), úsalos directamente para responder preguntas de seguimiento con exactitud numérica. " .
            "No inventes cifras ni respondas temas externos al peaje.";

        $llm = $this->llamarOllama($instruccion, json_encode($snapshot, JSON_UNESCAPED_UNICODE), $mensaje, $historial);
        if ($llm !== null) {
            $ollamaUsado = true;
            $respuestaFinal = $llm;
        }

        return response()->json([
            'respuesta' => $respuestaFinal,
            'estado' => 'Consulta operativa',
            'placa_consultada' => null,
            'datos_consulta' => $snapshot,
            'en_dominio' => true,
            'ollama_usado' => $ollamaUsado,
        ]);
    }

    /**
     * Si Ollama no está disponible y el usuario pregunta en seguimiento sobre el historial reciente
     * (por ejemplo "¿Cuántos pasajeros sumaron en total?" tras subir varias imágenes), extrae la respuesta exacta del historial.
     */
    private function extraerSeguimientoDeHistorial(string $mensaje, array $historial): ?string
    {
        if (count($historial) === 0) {
            return null;
        }

        $ultimoAsistente = '';
        for ($i = count($historial) - 1; $i >= 0; $i--) {
            if (($historial[$i]['role'] ?? '') === 'assistant') {
                $ultimoAsistente = (string) ($historial[$i]['content'] ?? '');
                break;
            }
        }

        if ($ultimoAsistente === '') {
            return null;
        }

        $lower = mb_strtolower($mensaje, 'UTF-8');
        $mencionaResumenPrevio = preg_match('/(imagen|lote|anterior|sumaron|total|cu[aá]ntos|cu[aá]nto|pasajer|placas|primera|segunda|tercera|esos|esas)/u', $lower) === 1;

        if (!$mencionaResumenPrevio) {
            return null;
        }

        if (str_contains($ultimoAsistente, 'Imagen #')) {
            if (preg_match('/pasajer/u', $lower) && preg_match('/Total de pasajeros:\*\*\s*(\d+)/u', $ultimoAsistente, $m)) {
                return "**Seguimiento del último lote de imágenes:** El total combinado fue de **{$m[1]} pasajero(s)** según el análisis previo.";
            }
            if (preg_match('/(tarifa|suma|monto|pagar|cobro|total|bs)/u', $lower) && preg_match('/Suma estimada de tarifas:\*\*\s*Bs\.\s*([\d.,]+)/u', $ultimoAsistente, $m)) {
                return "**Seguimiento del último lote de imágenes:** La suma estimada de tarifas fue **Bs. {$m[1]}**.";
            }
            if (preg_match('/placas?/u', $lower) && preg_match('/Placas detectadas:\*\*\s*([^\n]+)/u', $ultimoAsistente, $m)) {
                return "**Seguimiento del último lote de imágenes:** Placas detectadas: **{$m[1]}**.";
            }

            return "**Seguimiento sobre el análisis previo:**\n" . $ultimoAsistente;
        }

        return null;
    }

    /**
     * Guardrail estricto: valida que la consulta pertenezca al proyecto de Control de Peaje.
     */
    private function esConsultaDelProyecto(string $mensaje, array $historial): bool
    {
        if ($this->esExplicitamenteFueraDeDominio($mensaje) && !$this->tieneSenalDeProyecto($mensaje, [])) {
            return false;
        }

        if ($this->tieneSenalDeProyecto($mensaje, $historial)) {
            return true;
        }

        if ($this->esSaludoInicial($mensaje)) {
            return true;
        }

        // Seguimiento corto sobre un turno previo válido (sin palabras fuera de dominio)
        if (count($historial) > 0 && $this->esSeguimientoReferencial($mensaje)) {
            return true;
        }

        return false;
    }

    private function tieneSenalDeProyecto(string $mensaje, array $historial): bool
    {
        if (count($this->extraerPlacas($mensaje)) > 0) {
            return true;
        }

        $patronProyecto = '/\b(peaje|peajes|placa|placas|veh[ií]culo|veh[ií]culos|caseta|casetas|tarifa|tarifas|' .
            'alerta|alertas|recaudaci[oó]n|saldo|saldos|paso|pasos|pasajero|pasajeros|eje|ejes|categor[ií]a|categor[ií]as|' .
            'ocr|modelo|modelos|m1|m2|m3|m4|yolo|runpod|inferencia|c[aá]mara|imagen|im[aá]genes|foto|fotos|' .
            'auto|autos|minibus|minib[uú]s|bus|buses|cami[oó]n|camiones|trailer|tr[aá]iler|moto|motos|vagoneta|' .
            'propietario|conductor|usuario|usuarios|whitelist|lista blanca|oauth|padr[oó]n|carril|carretera|tr[aá]nsito|' .
            'resumen|reporte|estad[ií]sticas|cobro|pase|latencia|ollama)\b/ui';

        if (preg_match($patronProyecto, $mensaje) === 1) {
            return true;
        }

        // Combinación explícita de contexto previo + pregunta cuantitativa sobre el lote
        if (count($historial) > 0 && preg_match('/\b(sumaron|total|totales|detectad[oa]s?|registrad[oa]s?|analizad[oa]s?|primera|segunda|tercera)\b/ui', $mensaje) === 1) {
            return true;
        }

        return false;
    }

    private function esExplicitamenteFueraDeDominio(string $mensaje): bool
    {
        $patronFuera = '/\b(receta|pizza|cocina|ingredientes|hornear|f[uú]tbol|messi|ronaldo|chiste|chistes|poema|cancion|canci[oó]n|m[uú]sica|' .
            'hor[oó]scopo|astrolog[ií]a|bitcoin|criptomoneda|pel[ií]cula|novela|anime|videojuego|minecraft|' .
            'python|javascript|react|angular|sql\s+tutorial|tarea\s+de|presidente\s+de|capital\s+de|clima\s+en)\b/ui';

        return preg_match($patronFuera, $mensaje) === 1;
    }

    private function esSaludoInicial(string $mensaje): bool
    {
        $limpio = mb_strtolower(trim(preg_replace('/[¡!¿?.,]/u', '', $mensaje)), 'UTF-8');
        $saludos = ['hola', 'buenos dias', 'buenos días', 'buenas tardes', 'buenas noches', 'quien eres', 'quién eres', 'ayuda', 'que puedes hacer', 'qué puedes hacer', 'menu', 'menú'];
        return in_array($limpio, $saludos, true);
    }

    private function esSeguimientoReferencial(string $mensaje): bool
    {
        return preg_match('/\b(y\s+la|y\s+el|y\s+los|y\s+las|cu[aá]l|cu[aá]les|cu[aá]nto|cu[aá]ntos|dime\s+m[aá]s|expl[ií]came|detalles|diferencia|esa|ese|esos|esas)\b/ui', $mensaje) === 1;
    }

    /**
     * Extrae candidatos reales de placa vehicular (exige al menos un dígito para evitar falsos positivos en texto normal).
     */
    private function extraerPlacas(string $texto): array
    {
        $textoUpper = strtoupper($texto);
        $encontradas = [];

        // Formato boliviano o internacional con dígitos y letras: 4021XYZ, 2745-LYR, 4021 XYZ, ABC-123
        if (preg_match_all('/\b(?=[A-Z0-9 -]*\d)[A-Z0-9]{2,4}[- ]?[A-Z0-9]{2,4}\b/', $textoUpper, $matches)) {
            foreach ($matches[0] as $cand) {
                $norm = PlacaController::normalizar($cand);
                if (strlen($norm) >= 5 && strlen($norm) <= 8 && preg_match('/[A-Z]/', $norm) && preg_match('/\d/', $norm)) {
                    // Evitar falsos positivos como M1, 100BS, 2026
                    if (preg_match('/^\d+BS$/', $norm)) {
                        continue;
                    }
                    $encontradas[] = $norm;
                }
            }
        }

        return array_values(array_unique($encontradas));
    }

    private function extraerImagenesEntrada(Request $request): array
    {
        $imagenes = [];

        $lista = $request->input('imagenes_base64');
        if (is_array($lista)) {
            foreach ($lista as $img) {
                if (is_string($img) && trim($img) !== '') {
                    $imagenes[] = trim($img);
                }
            }
        }

        $unica = $request->input('imagen_base64');
        if (is_string($unica) && trim($unica) !== '' && count($imagenes) === 0) {
            $imagenes[] = trim($unica);
        }

        return $imagenes;
    }

    private function normalizarHistorial($raw): array
    {
        if (!is_array($raw)) {
            return [];
        }

        $limpio = [];
        foreach (array_slice($raw, -self::MAX_HISTORIAL) as $item) {
            if (!is_array($item)) {
                continue;
            }
            $role = ($item['role'] ?? '') === 'assistant' ? 'assistant' : 'user';
            $content = trim((string) ($item['content'] ?? ''));
            if ($content !== '') {
                $limpio[] = [
                    'role' => $role,
                    'content' => mb_substr($content, 0, 1200, 'UTF-8'),
                ];
            }
        }

        return $limpio;
    }

    private function obtenerSnapshotSistema(): array
    {
        return [
            'vehiculos' => Vehiculo::count(),
            'total_pasos' => Paso::count(),
            'alertas_pendientes' => Alerta::where('atendida', false)->count(),
        ];
    }

    /**
     * Llama a Ollama en RunPod SOLO si tiene al menos un modelo descargado y responde JSON válido.
     */
    private function llamarOllama(string $instruccion, string $contextoDatos, string $mensajeUsuario, array $historial): ?string
    {
        $ollamaUrl = rtrim((string) config('services.ollama.url', ''), '/');
        if ($ollamaUrl === '') {
            return null;
        }
        $ollamaModel = (string) config('services.ollama.model', 'llama3.2:3b');

        $tagsUrl = str_ends_with($ollamaUrl, '/ollama') ? "{$ollamaUrl}/tags" : "{$ollamaUrl}/api/tags";
        $generateUrl = str_ends_with($ollamaUrl, '/ollama') ? "{$ollamaUrl}/generate" : "{$ollamaUrl}/api/generate";

        try {
            $respTags = Http::timeout(3)->get($tagsUrl);
            if (!$respTags->successful()) {
                return null;
            }

            $tagsJson = $respTags->json();
            $models = is_array($tagsJson) ? ($tagsJson['models'] ?? []) : [];
            if (count($models) === 0) {
                return null;
            }

            $nombresDisponibles = collect($models)
                ->map(fn ($m) => is_array($m) ? ($m['name'] ?? ($m['model'] ?? null)) : null)
                ->filter()
                ->values()
                ->all();

            $modeloAUsar = in_array($ollamaModel, $nombresDisponibles, true)
                ? $ollamaModel
                : ($nombresDisponibles[0] ?? $ollamaModel);

            $historialTexto = '';
            if (count($historial) > 0) {
                $turnos = array_map(
                    fn ($h) => ($h['role'] === 'assistant' ? 'Asistente: ' : 'Usuario: ') . $h['content'],
                    array_slice($historial, -6)
                );
                $historialTexto = "HISTORIAL RECIENTE:\n" . implode("\n", $turnos) . "\n\n";
            }

            $prompt = "{$instruccion}\n\n" .
                "{$historialTexto}" .
                "DATOS REALES DEL SISTEMA:\n{$contextoDatos}\n\n" .
                "MENSAJE ACTUAL DEL USUARIO:\n{$mensajeUsuario}\n\n" .
                "RESPUESTA (concisa, en español y estrictamente sobre el proyecto):";

            $resp = Http::timeout(25)->post($generateUrl, [
                'model' => $modeloAUsar,
                'prompt' => $prompt,
                'stream' => false,
                'options' => [
                    'temperature' => 0.1,
                    'top_p' => 0.9,
                ],
            ]);

            if (!$resp->successful()) {
                return null;
            }

            $json = $resp->json();
            if (!is_array($json) || !isset($json['response']) || !is_string($json['response'])) {
                return null;
            }

            $texto = trim($json['response']);
            return $texto !== '' ? $texto : null;
        } catch (\Exception $e) {
            return null;
        }
    }
}
