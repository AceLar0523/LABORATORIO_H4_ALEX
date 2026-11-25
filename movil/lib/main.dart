import 'dart:async';
import 'dart:convert';
import 'dart:io' show File;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:camera/camera.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:video_player/video_player.dart';

List<CameraDescription> gAvailableCameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PeajeMovilApp());
}

class PeajeMovilApp extends StatelessWidget {
  const PeajeMovilApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Peaje Inteligente Móvil',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF8FAFC), // Slate 50
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0F172A), // Slate 900 corporativo
          primary: const Color(0xFF0F172A),
          surface: Colors.white,
          brightness: Brightness.light,
        ),
        cardTheme: const CardThemeData(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: Color(0xFFE2E8F0)),
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Color(0xFF0F172A),
          elevation: 0,
          scrolledUnderElevation: 0,
          titleTextStyle: TextStyle(
            color: Color(0xFF0F172A),
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
          shape: Border(
            bottom: BorderSide(color: Color(0xFFE2E8F0)),
          ),
        ),
        fontFamily: 'sans-serif',
        useMaterial3: true,
      ),
      home: const AuthGate(),
    );
  }
}

// -------------------------------------------------------------
// CONTROLADOR DE SESIÓN GOOGLE OAUTH
// -------------------------------------------------------------
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _isLoading = true;
  String? _token;
  Map<String, dynamic>? _user;
  late String _baseUrl;

  @override
  void initState() {
    super.initState();
    const String envApiUrl = String.fromEnvironment('API_BASE_URL');
    _baseUrl = envApiUrl.isNotEmpty
        ? envApiUrl
        : 'https://peaje.peaje-alele.me/api/v1';
    _checkSavedSession();
  }

  Future<void> _checkSavedSession() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('peaje_token');
    final userRaw = prefs.getString('peaje_user');
    final savedUrl = prefs.getString('peaje_base_url');

    setState(() {
      if (savedUrl != null && savedUrl.isNotEmpty) {
        _baseUrl = savedUrl;
      }
      if (token != null && userRaw != null) {
        _token = token;
        _user = jsonDecode(userRaw);
      }
      _isLoading = false;
    });
  }

  void _onLoginSuccess(String token, Map<String, dynamic> user, String baseUrl) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('peaje_token', token);
    await prefs.setString('peaje_user', jsonEncode(user));
    await prefs.setString('peaje_base_url', baseUrl);
    setState(() {
      _token = token;
      _user = user;
      _baseUrl = baseUrl;
    });
  }

  void _onLogout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('peaje_token');
    await prefs.remove('peaje_user');
    setState(() {
      _token = null;
      _user = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: Color(0xFF0F172A))),
      );
    }

    if (_token == null) {
      return LoginScreen(initialBaseUrl: _baseUrl, onLoginSuccess: _onLoginSuccess);
    }

    return MainHomeScreen(
      user: _user!,
      token: _token!,
      baseUrl: _baseUrl,
      onLogout: _onLogout,
    );
  }
}

// -------------------------------------------------------------
// PANTALLA DE ACCESO (SOBRIA, ENTERPRISE)
// -------------------------------------------------------------
class LoginScreen extends StatefulWidget {
  final String initialBaseUrl;
  final Function(String, Map<String, dynamic>, String) onLoginSuccess;
  const LoginScreen({super.key, required this.initialBaseUrl, required this.onLoginSuccess});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static bool _googleInitialized = false;

  late final TextEditingController _serverController;
  bool _loading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _serverController = TextEditingController(text: widget.initialBaseUrl);
  }

  @override
  void dispose() {
    _serverController.dispose();
    super.dispose();
  }

  String get _normalizedBaseUrl =>
      _serverController.text.trim().replaceAll(RegExp(r'/+$'), '');

  Future<void> _abrirConfigServidor() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Configurar Servidor', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'URL de la API del Backend (ej. https://subdominio.com/api/v1)',
                style: TextStyle(fontSize: 12, color: Color(0xFF475569)),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _serverController,
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () async {
                final limpio = _normalizedBaseUrl;
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('peaje_base_url', limpio);
                if (mounted) {
                  setState(() {
                    _serverController.text = limpio;
                    _errorMessage = null;
                  });
                }
                if (ctx.mounted) {
                  Navigator.of(ctx).pop();
                }
              },
              child: const Text('Guardar'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _loginGoogleOAuth() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    final base = _normalizedBaseUrl;

    try {
      final cfgResp = await http
          .get(Uri.parse('$base/auth/config'), headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 15));

      if (cfgResp.statusCode >= 400) {
        setState(() {
          _errorMessage = 'El servidor ($base) devolvió HTTP ${cfgResp.statusCode}. Verifica la URL en ⚙.';
        });
        return;
      }

      final cfg = jsonDecode(cfgResp.body);
      final String webClientId = (cfg['google_client_id'] ?? '').toString().trim();
      final String androidClientId = (cfg['google_android_client_id'] ?? '').toString().trim();
      final bool enabled = cfg['google_oauth_enabled'] == true &&
          (webClientId.isNotEmpty || androidClientId.isNotEmpty);

      if (!enabled) {
        setState(() {
          _errorMessage = 'Google OAuth no está habilitado en $base. Revisa GOOGLE_CLIENT_ID y GOOGLE_ANDROID_CLIENT_ID en backend/.env.';
        });
        return;
      }

      if (!_googleInitialized) {
        await GoogleSignIn.instance.initialize(
          clientId: kIsWeb ? (webClientId.isNotEmpty ? webClientId : null) : null,
          serverClientId: (!kIsWeb && webClientId.isNotEmpty) ? webClientId : null,
        );
        _googleInitialized = true;
      }

      if (!GoogleSignIn.instance.supportsAuthenticate()) {
        setState(() {
          _errorMessage = 'En navegador Web abre el acceso Web principal en HTTPS para iniciar con Google OAuth 2.0.';
        });
        return;
      }

      final account = await GoogleSignIn.instance.authenticate();
      final idToken = account.authentication.idToken;

      if (idToken == null || idToken.isEmpty) {
        setState(() {
          _errorMessage = 'Google no devolvió un ID Token válido.';
        });
        return;
      }

      final resp = await http.post(
        Uri.parse('$base/auth/google'),
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: jsonEncode({'id_token': idToken}),
      ).timeout(const Duration(seconds: 15));

      final data = jsonDecode(resp.body);

      if (resp.statusCode == 200 && data['success'] == true) {
        widget.onLoginSuccess(data['token'], data['usuario'], base);
      } else {
        setState(() {
          _errorMessage = data['message'] ?? 'Acceso denegado. Cuenta no autorizada.';
        });
      }
    } on TimeoutException {
      setState(() {
        _errorMessage =
            'Tiempo de espera agotado al conectar con $base/auth/config. '
            'Toca el ícono ⚙ arriba a la derecha para verificar la URL del servidor '
            '(en producción usa tu subdominio HTTPS; en pruebas locales inicia Laravel con --host=0.0.0.0).';
      });
    } on GoogleSignInException catch (e) {
      setState(() {
        final desc = (e.description ?? '').trim();
        _errorMessage = desc.isNotEmpty
            ? 'Error Google Sign-In (${e.code.name}): $desc'
            : 'Inicio con Google cancelado o no disponible (${e.code.name}).';
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error conectando con Google OAuth / servidor ($base): $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Widget _buildGoogleIcon() {
    return Container(
      width: 22,
      height: 22,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: RichText(
          text: const TextSpan(
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            children: [
              TextSpan(text: 'G', style: TextStyle(color: Color(0xFF4285F4))),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 420),
              padding: const EdgeInsets.all(26.0),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x06000000),
                    blurRadius: 20,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Logo, identidad y acceso discreto a configuración de servidor
                  Align(
                    alignment: Alignment.topRight,
                    child: IconButton(
                      icon: const Icon(Icons.settings_outlined, size: 18, color: Color(0xFF94A3B8)),
                      tooltip: 'Configurar Servidor',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: _abrirConfigServidor,
                    ),
                  ),
                  Center(
                    child: Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.shield_outlined, color: Colors.white, size: 26),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Peaje Inteligente',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                  ),
                  const Text(
                    'Control y Monitoreo de Caseta en Tiempo Real',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 20),

                  if (_errorMessage != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFFECACA)),
                      ),
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(color: Color(0xFF991B1B), fontSize: 11),
                      ),
                    ),

                  // ACCESO EXCLUSIVO GOOGLE OAUTH 2.0 (Sin contraseña)
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      backgroundColor: Colors.white,
                      side: const BorderSide(color: Color(0xFFCBD5E1), width: 1.2),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _loading ? null : _loginGoogleOAuth,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildGoogleIcon(),
                        const SizedBox(width: 10),
                        Text(
                          _loading ? 'Autenticando...' : 'Continuar con Google',
                          style: const TextStyle(
                            color: Color(0xFF0F172A),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Acceso exclusivo con Google Sign-In para cuentas autorizadas en la lista blanca institucional.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF64748B), fontSize: 11),
                  ),
                  const SizedBox(height: 12),
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: _abrirConfigServidor,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.dns_outlined, size: 13, color: Color(0xFF64748B)),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'Servidor: $_normalizedBaseUrl',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF475569),
                                fontSize: 10.5,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_normalizedBaseUrl.startsWith('http://10.0.2.2') ||
                      _normalizedBaseUrl.startsWith('http://localhost') ||
                      _normalizedBaseUrl.startsWith('http://192.168.'))
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFBEB),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFFDE68A)),
                        ),
                        child: const Text(
                          'Aviso: URL local detectada. Para producción/demostración configura tu subdominio HTTPS en ⚙.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Color(0xFF92400E), fontSize: 10.5),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// -------------------------------------------------------------
// PANTALLA PRINCIPAL CON NAVEGACIÓN (3 PESTAÑAS)
// -------------------------------------------------------------
class MainHomeScreen extends StatefulWidget {
  final Map<String, dynamic> user;
  final String token;
  final String baseUrl;
  final VoidCallback onLogout;

  const MainHomeScreen({
    super.key,
    required this.user,
    required this.token,
    required this.baseUrl,
    required this.onLogout,
  });

  @override
  State<MainHomeScreen> createState() => _MainHomeScreenState();
}

class _MainHomeScreenState extends State<MainHomeScreen> {
  int _currentIndex = 0;
  late final List<Map<String, dynamic>> _chatMensajes = [
    _crearMensajeBienvenida(),
  ];

  static Map<String, dynamic> _crearMensajeBienvenida() => {
        'role': 'assistant',
        'text':
            'Soy el asistente exclusivo del **Sistema Inteligente de Control de Peaje**.\n'
            'Puedes subir **1 o varias fotos de vehículos** (hasta 6) para analizar placa (M1), categoría (M2), ejes (M3), pasajeros (M4) y tarifa, o consultarme sobre placas, tarifas, alertas y recaudación.',
        'imagenes': <Uint8List>[],
        'fueraDominio': false,
        'analisis': <dynamic>[],
        'resumenLote': null,
      };

  void _reiniciarChatMensajes() {
    setState(() {
      _chatMensajes
        ..clear()
        ..add(_crearMensajeBienvenida());
    });
  }

  String get _appBarTitle {
    switch (_currentIndex) {
      case 0:
        return 'Caseta de Peaje';
      case 1:
        return 'Historial de Pasos';
      default:
        return 'Agente IA de Peaje';
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool esAdmin = widget.user['rol'] == 'administrador';
    final screens = [
      ModoCasetaScreen(token: widget.token, baseUrl: widget.baseUrl),
      HistorialPasosScreen(token: widget.token, baseUrl: widget.baseUrl, esAdmin: esAdmin),
      ModoConsultaScreen(
        token: widget.token,
        baseUrl: widget.baseUrl,
        mensajes: _chatMensajes,
        onResetMensajes: _reiniciarChatMensajes,
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(_appBarTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_outlined, size: 20),
            tooltip: 'Cerrar Sesión',
            onPressed: widget.onLogout,
          ),
        ],
      ),
      body: screens[_currentIndex],
      bottomNavigationBar: NavigationBar(
        backgroundColor: Colors.white,
        elevation: 0,
        indicatorColor: const Color(0xFFE2E8F0),
        selectedIndex: _currentIndex,
        onDestinationSelected: (idx) => setState(() => _currentIndex = idx),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.videocam_outlined, size: 20),
            selectedIcon: Icon(Icons.videocam, size: 20, color: Color(0xFF0F172A)),
            label: 'Modo Caseta',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined, size: 20),
            selectedIcon: Icon(Icons.history, size: 20, color: Color(0xFF0F172A)),
            label: 'Historial',
          ),
          NavigationDestination(
            icon: Icon(Icons.smart_toy_outlined, size: 20),
            selectedIcon: Icon(Icons.smart_toy, size: 20, color: Color(0xFF0F172A)),
            label: 'Agente IA',
          ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------
// PINTOR DE PUNTOS Y CAJAS EN VIVO (M1 PLACA, M2 VEHÍCULO, M3 RUEDAS, M4 PASAJEROS)
// -------------------------------------------------------------
class _DetectionOverlayPainter extends CustomPainter {
  final Map<String, dynamic>? deteccion;
  final Size? fallbackImageSize;
  final bool isLiveScanning;

  const _DetectionOverlayPainter({
    required this.deteccion,
    required this.fallbackImageSize,
    required this.isLiveScanning,
  });

  Size? _resolveSourceSize() {
    final rawSize = deteccion?['imagen_size'];
    if (rawSize is List && rawSize.length >= 2) {
      final w = (rawSize[0] as num?)?.toDouble() ?? 0;
      final h = (rawSize[1] as num?)?.toDouble() ?? 0;
      if (w > 0 && h > 0) return Size(w, h);
    }
    return fallbackImageSize;
  }

  Rect? _mapBox(dynamic rawBox, double scale, double dx, double dy) {
    if (rawBox is! List || rawBox.length < 4) return null;
    final x1 = (rawBox[0] as num?)?.toDouble();
    final y1 = (rawBox[1] as num?)?.toDouble();
    final x2 = (rawBox[2] as num?)?.toDouble();
    final y2 = (rawBox[3] as num?)?.toDouble();
    if (x1 == null || y1 == null || x2 == null || y2 == null) return null;
    return Rect.fromLTRB(
      x1 * scale + dx,
      y1 * scale + dy,
      x2 * scale + dx,
      y2 * scale + dy,
    );
  }

  void _drawLabel(Canvas canvas, Offset pos, String text, Color bgColor) {
    if (text.trim().isEmpty) return;
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        pos.dx.clamp(4.0, 260.0),
        (pos.dy - tp.height - 6).clamp(4.0, 280.0),
        tp.width + 10,
        tp.height + 4,
      ),
      const Radius.circular(5),
    );
    canvas.drawRRect(rect, Paint()..color = bgColor.withValues(alpha: 0.92));
    tp.paint(canvas, Offset(rect.left + 5, rect.top + 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (isLiveScanning) {
      final guidePaint = Paint()
        ..color = const Color(0xFF34D399).withValues(alpha: 0.75)
        ..strokeWidth = 2.4
        ..style = PaintingStyle.stroke;
      const double pad = 16;
      const double len = 22;
      // Esquina superior izquierda
      canvas.drawPath(
        Path()
          ..moveTo(pad, pad + len)
          ..lineTo(pad, pad)
          ..lineTo(pad + len, pad),
        guidePaint,
      );
      // Esquina superior derecha
      canvas.drawPath(
        Path()
          ..moveTo(size.width - pad - len, pad)
          ..lineTo(size.width - pad, pad)
          ..lineTo(size.width - pad, pad + len),
        guidePaint,
      );
      // Esquina inferior izquierda
      canvas.drawPath(
        Path()
          ..moveTo(pad, size.height - pad - len)
          ..lineTo(pad, size.height - pad)
          ..lineTo(pad + len, size.height - pad),
        guidePaint,
      );
      // Esquina inferior derecha
      canvas.drawPath(
        Path()
          ..moveTo(size.width - pad - len, size.height - pad)
          ..lineTo(size.width - pad, size.height - pad)
          ..lineTo(size.width - pad, size.height - pad - len),
        guidePaint,
      );
    }

    if (deteccion == null) return;
    final src = _resolveSourceSize();
    if (src == null || src.width <= 0 || src.height <= 0) return;

    // Transformación BoxFit.cover idéntica a la del visor de cámara / foto
    final double scaleX = size.width / src.width;
    final double scaleY = size.height / src.height;
    final double scale = scaleX > scaleY ? scaleX : scaleY;
    final double dx = (size.width - src.width * scale) / 2.0;
    final double dy = (size.height - src.height * scale) / 2.0;

    // 1. M2: Caja de vehículo principal
    final m2 = deteccion!['m2'];
    final vehRect = m2 is Map ? _mapBox(m2['bbox'], scale, dx, dy) : null;
    if (vehRect != null) {
      final vehPaint = Paint()
        ..color = const Color(0xFF10B981)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2;
      canvas.drawRRect(RRect.fromRectAndRadius(vehRect, const Radius.circular(6)), vehPaint);
      final cat = (deteccion!['categoria'] ?? 'auto').toString().toUpperCase();
      final ejes = deteccion!['ejes'] ?? 2;
      _drawLabel(canvas, Offset(vehRect.left, vehRect.top), '$cat · $ejes EJES', const Color(0xFF059669));
    }

    // 2. M4: Pasajeros en violeta
    final m4 = deteccion!['m4'];
    final pasCajas = m4 is Map ? m4['cajas'] : null;
    if (pasCajas is List) {
      final pasPaint = Paint()
        ..color = const Color(0xFFA855F7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8;
      for (final b in pasCajas) {
        final r = _mapBox(b, scale, dx, dy);
        if (r != null) {
          canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(4)), pasPaint);
        }
      }
    }

    // 3. M3: Cajas y puntos clave de ruedas (cyan luminoso)
    final m3 = deteccion!['m3'];
    if (m3 is Map) {
      final cajasRuedas = m3['cajas_ruedas'];
      if (cajasRuedas is List) {
        final wheelBoxPaint = Paint()
          ..color = const Color(0xFF06B6D4).withValues(alpha: 0.7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4;
        for (final b in cajasRuedas) {
          final r = _mapBox(b, scale, dx, dy);
          if (r != null) {
            canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(4)), wheelBoxPaint);
          }
        }
      }

      final puntos = m3['puntos'];
      if (puntos is List) {
        final haloPaint = Paint()..color = const Color(0xFF06B6D4).withValues(alpha: 0.35);
        final dotPaint = Paint()..color = const Color(0xFF22D3EE);
        final corePaint = Paint()..color = Colors.white;
        for (final pt in puntos) {
          if (pt is List && pt.length >= 2) {
            final px = (pt[0] as num?)?.toDouble();
            final py = (pt[1] as num?)?.toDouble();
            if (px != null && py != null) {
              final center = Offset(px * scale + dx, py * scale + dy);
              canvas.drawCircle(center, 7.5, haloPaint);
              canvas.drawCircle(center, 4.2, dotPaint);
              canvas.drawCircle(center, 1.8, corePaint);
            }
          }
        }
      }
    }

    // 4. M1: Caja de placa en ámbar
    final m1 = deteccion!['m1'];
    final placaRect = m1 is Map ? _mapBox(m1['bbox'], scale, dx, dy) : null;
    if (placaRect != null) {
      final platePaint = Paint()
        ..color = const Color(0xFFF59E0B)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4;
      canvas.drawRRect(RRect.fromRectAndRadius(placaRect, const Radius.circular(4)), platePaint);
      final placaTxt = (deteccion!['placa_normalizada'] ?? deteccion!['placa'] ?? '').toString();
      if (placaTxt.isNotEmpty && placaTxt != 'SINPLACA' && placaTxt != 'SIN_PLACA') {
        _drawLabel(canvas, Offset(placaRect.left, placaRect.top), placaTxt, const Color(0xFFD97706));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DetectionOverlayPainter oldDelegate) {
    return oldDelegate.deteccion != deteccion ||
        oldDelegate.fallbackImageSize != fallbackImageSize ||
        oldDelegate.isLiveScanning != isLiveScanning;
  }
}

// -------------------------------------------------------------
// MODO CASETA (Saca Foto, Sube Foto, Video y Cámara en Live con Overlays)
// -------------------------------------------------------------
class ModoCasetaScreen extends StatefulWidget {
  final String token;
  final String baseUrl;
  const ModoCasetaScreen({super.key, required this.token, required this.baseUrl});

  @override
  State<ModoCasetaScreen> createState() => _ModoCasetaScreenState();
}

class _ModoCasetaScreenState extends State<ModoCasetaScreen> {
  final ImagePicker _picker = ImagePicker();
  Uint8List? _capturedImageBytes;
  Size? _capturedImageSize;
  bool _processing = false;
  Map<String, dynamic>? _lastResult;
  Map<String, dynamic>? _liveDeteccion;
  String _liveStatusMotivo = '';
  String? _nuevoRegistroPlaca;
  Timer? _nuevoRegistroTimer;

  // Video Controller
  VideoPlayerController? _videoController;
  final GlobalKey _videoBoundaryKey = GlobalKey();
  bool _isPlayingVideo = false;

  // Live Camera Controller & Scanner Timer
  CameraController? _cameraController;
  bool _isLiveScanning = false;
  bool _autoRegistrarLive = true;
  Timer? _liveScanTimer;
  bool _isCameraInitialized = false;

  @override
  void initState() {
    super.initState();
    _initLiveCamera();
  }

  Future<void> _initLiveCamera() async {
    if (!kIsWeb && gAvailableCameras.isEmpty) {
      try {
        gAvailableCameras = await availableCameras();
      } catch (e) {
        debugPrint('Error consultando camaras: $e');
        gAvailableCameras = [];
      }
    }
    if (gAvailableCameras.isNotEmpty) {
      final backCam = gAvailableCameras.firstWhere(
        (cam) => cam.lensDirection == CameraLensDirection.back,
        orElse: () => gAvailableCameras.first,
      );
      _cameraController = CameraController(
        backCam,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      try {
        await _cameraController!.initialize();
        if (mounted) {
          setState(() {
            _isCameraInitialized = true;
          });
        }
      } catch (e) {
        debugPrint('Error inicializando camara: $e');
      }
    }
  }

  @override
  void dispose() {
    _liveScanTimer?.cancel();
    _nuevoRegistroTimer?.cancel();
    _cameraController?.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  void _mostrarBannerNuevoRegistro(String placa) {
    _nuevoRegistroTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _nuevoRegistroPlaca = placa;
    });
    _nuevoRegistroTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) {
        setState(() {
          _nuevoRegistroPlaca = null;
        });
      }
    });
  }

  Future<void> _actualizarFallbackImageSize(Uint8List bytes) async {
    try {
      final completer = Completer<Size>();
      ui.decodeImageFromList(bytes, (ui.Image img) {
        completer.complete(Size(img.width.toDouble(), img.height.toDouble()));
      });
      final size = await completer.future;
      if (mounted) {
        setState(() {
          _capturedImageSize = size;
        });
      }
    } catch (_) {}
  }

  // Toggle Live Mode
  void _toggleLiveMode() {
    setState(() {
      _isLiveScanning = !_isLiveScanning;
      if (!_isLiveScanning) {
        _liveStatusMotivo = '';
      } else {
        _videoController?.pause();
        _liveStatusMotivo = 'sin_vehiculo';
        _liveDeteccion = null;
      }
    });

    if (_isLiveScanning) {
      // Escaneo continuo en vivo (~1.4 fps cuando la red esté libre, protegido por _processing)
      _liveScanTimer = Timer.periodic(const Duration(milliseconds: 700), (timer) {
        if (!_processing && _cameraController != null && _cameraController!.value.isInitialized) {
          _capturarFrameLive();
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Modo Live activo: dibujando detecciones y evitando cobros duplicados.'),
          duration: Duration(seconds: 2),
        ),
      );
    } else {
      _liveScanTimer?.cancel();
      _liveScanTimer = null;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Modo Live pausado'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  Future<void> _capturarFrameLive() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;
    try {
      final XFile shot = await _cameraController!.takePicture();
      final bytes = await shot.readAsBytes();
      await _actualizarFallbackImageSize(bytes);
      await _enviarFrameAI(bytes, esLive: true);
    } catch (_) {}
  }

  // Subir o Sacar Foto
  Future<void> _capturarFoto(ImageSource source) async {
    if (_isLiveScanning) {
      _toggleLiveMode();
    }
    _videoController?.pause();

    final XFile? photo = await _picker.pickImage(source: source, maxWidth: 900, imageQuality: 85);
    if (photo == null) return;

    final bytes = await photo.readAsBytes();
    setState(() {
      _capturedImageBytes = bytes;
      _liveDeteccion = null;
      _nuevoRegistroPlaca = null;
    });
    await _actualizarFallbackImageSize(bytes);
    await _enviarFrameAI(bytes);
  }

  // Cargar y Reproducir Video
  Future<void> _seleccionarVideo() async {
    if (_isLiveScanning) {
      _toggleLiveMode();
    }
    final XFile? video = await _picker.pickVideo(source: ImageSource.gallery);
    if (video == null) return;

    _videoController?.dispose();
    if (kIsWeb) {
      _videoController = VideoPlayerController.networkUrl(Uri.parse(video.path));
    } else {
      _videoController = VideoPlayerController.file(File(video.path));
    }

    await _videoController!.initialize();
    _videoController!.setLooping(true);
    _videoController!.play();

    if (!mounted) return;
    setState(() {
      _isPlayingVideo = true;
      _liveDeteccion = null;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_isPlayingVideo ? 'Video cargado en reproducción. Usa "Analizar Frame del Video" para procesarlo.' : 'Video listo.'),
      ),
    );
  }

  Future<void> _capturarFrameDeVideo() async {
    if (_processing || _videoController == null || !_videoController!.value.isInitialized) return;
    try {
      final renderObject = _videoBoundaryKey.currentContext?.findRenderObject();
      if (renderObject is! RenderRepaintBoundary) {
        throw Exception('El visor de video aún no está listo para captura.');
      }
      final ui.Image image = await renderObject.toImage(pixelRatio: 1.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw Exception('No se pudo codificar el frame del video.');
      }
      final bytes = byteData.buffer.asUint8List();
      if (mounted) {
        setState(() {
          _capturedImageBytes = bytes;
        });
      }
      await _actualizarFallbackImageSize(bytes);
      await _enviarFrameAI(bytes);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo capturar frame del video en este dispositivo ($e). Usa Cámara en Live o Foto.')),
        );
      }
    }
  }

  Future<void> _enviarFrameAI(Uint8List bytes, {bool esLive = false}) async {
    setState(() {
      _processing = true;
      if (!esLive) _lastResult = null;
    });

    try {
      final base64Image = 'data:image/jpeg;base64,${base64Encode(bytes)}';
      final response = await http.post(
        Uri.parse('${widget.baseUrl}/pasos/frame'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer ${widget.token}',
        },
        body: jsonEncode({
          'frame_base64': base64Image,
          'caseta_id': 1,
          'modo_live': esLive,
          'solo_preview': esLive && !_autoRegistrarLive,
          'cooldown_segundos': 20,
        }),
      ).timeout(const Duration(seconds: 20));

      final data = jsonDecode(response.body);
      if ((response.statusCode == 201 || response.statusCode == 200) && data['success'] == true) {
        final bool registrado = data['registrado'] == true;
        final String motivo = (data['motivo'] ?? (registrado ? 'nuevo_registro' : '')).toString();
        final dynamic det = data['deteccion'];
        final Map<String, dynamic>? detMap = det is Map<String, dynamic> ? det : null;

        if (mounted) {
          setState(() {
            _liveStatusMotivo = motivo;
            _liveDeteccion = (motivo == 'sin_vehiculo') ? null : detMap;
            if (data['paso'] != null) {
              _lastResult = data;
            }
          });
          if (registrado && data['paso'] is Map) {
            final placa = (data['paso']['placa_normalizada'] ?? data['paso']['placa_leida'] ?? 'PLACA').toString();
            _mostrarBannerNuevoRegistro(placa);
          }
        }
      } else if (mounted && !esLive) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data['message'] ?? 'No se pudo procesar en RunPod (HTTP ${response.statusCode})'),
          ),
        );
      }
    } catch (e) {
      if (mounted && !esLive) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al procesar en servidor: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _processing = false;
        });
      }
    }
  }

  Widget _buildLiveCameraPreview() {
    final controller = _cameraController!;
    final double sensorRatio = controller.value.aspectRatio > 0 ? controller.value.aspectRatio : (4 / 3);
    final bool isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    final double previewRatio = isLandscape ? sensorRatio : (1.0 / sensorRatio);
    return FittedBox(
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        width: 360,
        height: 360 / previewRatio,
        child: CameraPreview(controller),
      ),
    );
  }

  Widget _buildLiveStatusChip() {
    if (_nuevoRegistroPlaca != null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFF059669),
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 6)],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 14),
            const SizedBox(width: 6),
            Text(
              'NUEVO REGISTRO · $_nuevoRegistroPlaca',
              style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.4),
            ),
          ],
        ),
      );
    }

    if (!_isLiveScanning) return const SizedBox.shrink();

    String texto = 'ESCANEANDO CARRIL...';
    Color bg = Colors.black.withValues(alpha: 0.72);
    IconData icon = Icons.radar;

    if (_liveStatusMotivo == 'solo_preview') {
      texto = 'SOLO VISTA PREVIA (SIN GUARDAR)';
      bg = const Color(0xFF334155).withValues(alpha: 0.9);
      icon = Icons.visibility_outlined;
    } else if (_liveStatusMotivo == 'duplicado_reciente') {
      final p = (_liveDeteccion?['placa_normalizada'] ?? '').toString();
      texto = p.isNotEmpty ? 'YA REGISTRADO · $p' : 'YA REGISTRADO (COOLDOWN)';
      bg = const Color(0xFF1D4ED8).withValues(alpha: 0.9);
      icon = Icons.verified_outlined;
    } else if (_liveStatusMotivo == 'vehiculo_lejano') {
      texto = 'VEHÍCULO LEJANO · ACERCAR A CASETA';
      bg = const Color(0xFFEA580C).withValues(alpha: 0.9);
      icon = Icons.zoom_in_outlined;
    } else if (_liveStatusMotivo == 'esperando_placa') {
      texto = 'VEHÍCULO DETECTADO · ENFOCANDO PLACA';
      bg = const Color(0xFFD97706).withValues(alpha: 0.9);
      icon = Icons.center_focus_weak;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 12),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              texto,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // VISOR PRINCIPAL (Cámara Live sin deformación, Video o Imagen + Puntos IA en Vivo)
          Container(
            height: 320,
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _nuevoRegistroPlaca != null
                    ? const Color(0xFF10B981)
                    : (_isLiveScanning ? const Color(0xFF34D399) : const Color(0xFFE2E8F0)),
                width: (_isLiveScanning || _nuevoRegistroPlaca != null) ? 2.5 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: _isLiveScanning ? const Color(0x3310B981) : Colors.black12,
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // 1. Si está en Modo Live y la cámara está lista
                  if (_isLiveScanning && _isCameraInitialized && _cameraController != null)
                    _buildLiveCameraPreview()
                  // 2. Si hay video seleccionado
                  else if (_videoController != null && _videoController!.value.isInitialized)
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          if (_videoController!.value.isPlaying) {
                            _videoController!.pause();
                            _isPlayingVideo = false;
                          } else {
                            _videoController!.play();
                            _isPlayingVideo = true;
                          }
                        });
                      },
                      child: RepaintBoundary(
                        key: _videoBoundaryKey,
                        child: AspectRatio(
                          aspectRatio: _videoController!.value.aspectRatio,
                          child: VideoPlayer(_videoController!),
                        ),
                      ),
                    )
                  // 3. Si hay foto capturada
                  else if (_capturedImageBytes != null)
                    Image.memory(_capturedImageBytes!, fit: BoxFit.cover)
                  // 4. Placeholder inicial
                  else
                    const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.videocam_outlined, size: 48, color: Color(0xFF94A3B8)),
                        SizedBox(height: 8),
                        Text(
                          'Caseta de Peaje Inteligente',
                          style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        Text(
                          'Activa Cámara en Live, Sube Foto o Video',
                          style: TextStyle(color: Colors.white38, fontSize: 11),
                        ),
                      ],
                    ),

                  // Capa de Overlay en Tiempo Real: cajas M1/M2/M4 + puntos de ruedas M3
                  if (_isLiveScanning || _liveDeteccion != null)
                    IgnorePointer(
                      child: CustomPaint(
                        painter: _DetectionOverlayPainter(
                          deteccion: _liveDeteccion,
                          fallbackImageSize: _capturedImageSize,
                          isLiveScanning: _isLiveScanning,
                        ),
                      ),
                    ),

                  // Badge superior izquierdo en Modo Live
                  if (_isLiveScanning)
                    Positioned(
                      top: 10,
                      left: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.fiber_manual_record, color: Colors.white, size: 11),
                            SizedBox(width: 5),
                            Text(
                              'EN VIVO • IA',
                              style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // Etiqueta de Estado Live / NUEVO REGISTRO (abajo izquierda)
                  if (_nuevoRegistroPlaca != null || _isLiveScanning)
                    Positioned(
                      bottom: 10,
                      left: 10,
                      right: _processing ? 130 : 10,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: _buildLiveStatusChip(),
                      ),
                    ),

                  // Indicador procesando (abajo derecha)
                  if (_processing)
                    Positioned(
                      bottom: 10,
                      right: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(width: 11, height: 11, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                            SizedBox(width: 6),
                            Text('M1..M4', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Leyenda compacta de puntos/cajas en vivo
          if (_isLiveScanning || _liveDeteccion != null) ...[
            const SizedBox(height: 8),
            const Wrap(
              spacing: 12,
              runSpacing: 4,
              alignment: WrapAlignment.center,
              children: [
                _LegendDot(color: Color(0xFFF59E0B), label: 'M1 Placa'),
                _LegendDot(color: Color(0xFF10B981), label: 'M2 Vehículo'),
                _LegendDot(color: Color(0xFF22D3EE), label: 'M3 Ruedas/Ejes'),
                _LegendDot(color: Color(0xFFA855F7), label: 'M4 Pasajeros'),
              ],
            ),
          ],

          const SizedBox(height: 10),

          // Control para evitar cobros/registros accidentales al probar en la calle
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              activeThumbColor: const Color(0xFF059669),
              title: const Text(
                'Auto-registrar pasos en Live',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
              ),
              subtitle: Text(
                _autoRegistrarLive
                    ? 'Registra solo vehículos cercanos (>8% del cuadro) con placa clara y sin duplicar.'
                    : 'Solo Vista Previa: muestra puntos y datos en vivo sin guardar ni cobrar.',
                style: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B)),
              ),
              value: _autoRegistrarLive,
              onChanged: (val) => setState(() => _autoRegistrarLive = val),
            ),
          ),

          const SizedBox(height: 10),

          // BOTONERA DE ACCIONES (Sacar Foto, Subir Foto, Video, Live)
          Row(
            children: [
              // Botón 1: Cámara Live
              Expanded(
                flex: 3,
                child: ElevatedButton.icon(
                  icon: Icon(_isLiveScanning ? Icons.stop : Icons.sensors, size: 18),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isLiveScanning ? const Color(0xFFDC2626) : const Color(0xFF0F172A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: _toggleLiveMode,
                  label: Text(_isLiveScanning ? 'Detener Live' : 'Cámara en Live', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 8),

              // Botón 2: Sacar Foto
              Expanded(
                flex: 2,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.camera_alt_outlined, size: 16),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF0F172A),
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: _processing ? null : () => _capturarFoto(ImageSource.camera),
                  label: const Text('Foto', style: TextStyle(fontSize: 12)),
                ),
              ),
              const SizedBox(width: 8),

              // Botón 3: Subir Foto
              Expanded(
                flex: 2,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.photo_library_outlined, size: 16),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF0F172A),
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: _processing ? null : () => _capturarFoto(ImageSource.gallery),
                  label: const Text('Galería', style: TextStyle(fontSize: 12)),
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Botón secundario: Cargar Video y Analizar Frame
          OutlinedButton.icon(
            icon: const Icon(Icons.video_library_outlined, size: 18, color: Color(0xFF475569)),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 10),
              side: const BorderSide(color: Color(0xFFE2E8F0)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: _seleccionarVideo,
            label: const Text(
              'Cargar y Reproducir Video de Caseta',
              style: TextStyle(fontSize: 12, color: Color(0xFF475569)),
            ),
          ),

          if (_videoController != null && _videoController!.value.isInitialized) ...[
            const SizedBox(height: 8),
            ElevatedButton.icon(
              icon: const Icon(Icons.center_focus_strong_outlined, size: 18),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1D4ED8),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 11),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: _processing ? null : _capturarFrameDeVideo,
              label: const Text(
                'Analizar Frame del Video',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
          ],

          // TELEMETRÍA EN VIVO MIENTRAS ESCANEA (cuando aún no hay registro guardado o está enfocando placa)
          if (_isLiveScanning && _liveDeteccion != null && _lastResult == null) ...[
            const SizedBox(height: 14),
            _buildLiveTelemetryCard(_liveDeteccion!),
          ],

          // TARJETA DE RESULTADO DE DETECCIÓN IA (Registro persistido / último paso)
          if (_lastResult != null && _lastResult!['paso'] != null) ...[
            const SizedBox(height: 14),
            _buildResultCard(
              _lastResult!['paso'] as Map<String, dynamic>,
              _lastResult!['latencia_ms'],
              esNuevoRegistro: _nuevoRegistroPlaca != null,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLiveTelemetryCard(Map<String, dynamic> det) {
    final placa = (det['placa_normalizada'] ?? '').toString();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFCBD5E1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'DETECCIÓN EN VIVO (ENFOCANDO)',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF64748B)),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFDE68A)),
                ),
                child: const Text(
                  'En espera de placa legible',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF92400E)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            placa.isNotEmpty && placa != 'SINPLACA' ? placa : 'LEYENDO...',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, fontFamily: 'monospace', color: Color(0xFF0F172A)),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildInfoTile('Categoría (M2)', '${det['categoria'] ?? 'auto'}'.toUpperCase(), Icons.directions_car_outlined),
              ),
              Expanded(
                child: _buildInfoTile('Ejes (M3)', '${det['ejes'] ?? 2} Ejes', Icons.adjust_outlined),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildInfoTile('Pasajeros (M4)', '${det['pasajeros'] ?? 0} Pers.', Icons.people_outline),
              ),
              Expanded(
                child: _buildInfoTile('Tarifa Est.', 'Bs. ${det['monto'] ?? '10.00'}', Icons.payments_outlined, isHighlight: true),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildResultCard(Map<String, dynamic> paso, dynamic latencia, {bool esNuevoRegistro = false}) {
    final bool esValido = paso['estado'] == 'Registrada y con paso';
    final int pasajeros = paso['pasajeros'] ?? 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: esValido ? const Color(0xFFA7F3D0) : const Color(0xFFFECDD3), width: 1.5),
        boxShadow: const [
          BoxShadow(color: Color(0x08000000), blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (esNuevoRegistro)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF6EE7B7)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.fiber_new, color: Color(0xFF059669), size: 16),
                  SizedBox(width: 6),
                  Text(
                    'NUEVO REGISTRO EN CASETA',
                    style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Color(0xFF065F46)),
                  ),
                ],
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('PLACA RECONOCIDA (M1 + OCR)', style: TextStyle(fontSize: 10, color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                      paso['placa_normalizada'] ?? 'DESCONOCIDA',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF0F172A), letterSpacing: 1.2, fontFamily: 'monospace'),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 155),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: esValido ? const Color(0xFFECFDF5) : const Color(0xFFFFF1F2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: esValido ? const Color(0xFF6EE7B7) : const Color(0xFFFDA4AF)),
                    ),
                    child: Text(
                      paso['estado'] ?? '',
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      softWrap: true,
                      style: TextStyle(
                        fontSize: 10.5,
                        height: 1.25,
                        fontWeight: FontWeight.w600,
                        color: esValido ? const Color(0xFF065F46) : const Color(0xFF9F1239),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const Divider(height: 22, color: Color(0xFFF1F5F9)),

          // Cuadrícula de Especificaciones Técnicas (M1, M2, M3, M4)
          Row(
            children: [
              Expanded(
                child: _buildInfoTile('Categoría (M2)', '${paso['categoria_detectada']}'.toUpperCase(), Icons.directions_car_outlined),
              ),
              Expanded(
                child: _buildInfoTile('Ejes (M3)', '${paso['ejes_detectados']} Ejes', Icons.adjust_outlined),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildInfoTile('Pasajeros (M4)', '$pasajeros Persona${pasajeros == 1 ? '' : 's'}', Icons.people_outline),
              ),
              Expanded(
                child: _buildInfoTile('Tarifa Cobrada', 'Bs. ${paso['monto']}', Icons.payments_outlined, isHighlight: true),
              ),
            ],
          ),

          if (latencia != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '• Caseta: ${paso['caseta']?['nombre'] ?? 'Principal 1'}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '⚡ Latencia IA: ${latencia}ms',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF059669), fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoTile(String label, String value, IconData icon, {bool isHighlight = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: isHighlight ? const Color(0xFFF0FDF4) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isHighlight ? const Color(0xFFBBF7D0) : const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: isHighlight ? const Color(0xFF16A34A) : const Color(0xFF64748B)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 9, color: Color(0xFF64748B))),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isHighlight ? const Color(0xFF15803D) : const Color(0xFF0F172A),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFF475569), fontWeight: FontWeight.w600)),
      ],
    );
  }
}

// -------------------------------------------------------------
// HISTORIAL DE PASOS GUARDADOS (CON FOTO, FILTROS, ELIMINACIÓN Y PAGINACIÓN)
// -------------------------------------------------------------
class HistorialPasosScreen extends StatefulWidget {
  final String token;
  final String baseUrl;
  final bool esAdmin;
  const HistorialPasosScreen({super.key, required this.token, required this.baseUrl, required this.esAdmin});

  @override
  State<HistorialPasosScreen> createState() => _HistorialPasosScreenState();
}

class _HistorialPasosScreenState extends State<HistorialPasosScreen> {
  final List<Map<String, dynamic>> _pasos = [];
  bool _cargando = false;
  bool _cargandoMas = false;
  int _paginaActual = 1;
  int _ultimaPagina = 1;
  int _total = 0;
  String _filtroEstado = '';
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    _cargarPasos(reiniciar: true);
  }

  String? _resolverMediaUrl(dynamic raw) {
    if (raw == null) return null;
    final url = raw.toString().trim();
    if (url.isEmpty) return null;
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    final parsed = Uri.tryParse(widget.baseUrl);
    if (parsed == null || parsed.host.isEmpty) return url;
    final path = url.startsWith('/') ? url : '/$url';
    return '${parsed.scheme}://${parsed.authority}$path';
  }

  Future<void> _cargarPasos({bool reiniciar = false}) async {
    if (reiniciar) {
      setState(() {
        _cargando = true;
        _errorMsg = null;
        _paginaActual = 1;
      });
    } else {
      if (_cargandoMas || _paginaActual >= _ultimaPagina) return;
      setState(() {
        _cargandoMas = true;
      });
    }

    final int targetPage = reiniciar ? 1 : (_paginaActual + 1);
    final queryParams = <String, String>{'page': '$targetPage'};
    if (_filtroEstado.isNotEmpty) {
      queryParams['estado'] = _filtroEstado;
    }

    try {
      final uri = Uri.parse('${widget.baseUrl}/pasos').replace(queryParameters: queryParams);
      final resp = await http.get(
        uri,
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer ${widget.token}',
        },
      ).timeout(const Duration(seconds: 15));

      if (!mounted) return;
      if (resp.statusCode == 200) {
        final json = jsonDecode(resp.body);
        final List<dynamic> items = (json['data'] as List<dynamic>?) ?? [];
        setState(() {
          if (reiniciar) _pasos.clear();
          _pasos.addAll(items.whereType<Map<String, dynamic>>());
          _paginaActual = (json['current_page'] as num?)?.toInt() ?? targetPage;
          _ultimaPagina = (json['last_page'] as num?)?.toInt() ?? 1;
          _total = (json['total'] as num?)?.toInt() ?? _pasos.length;
        });
      } else {
        setState(() {
          _errorMsg = 'Error HTTP ${resp.statusCode} al cargar historial.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMsg = 'No se pudo conectar para cargar el historial: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _cargando = false;
          _cargandoMas = false;
        });
      }
    }
  }

  String _formatFecha(dynamic raw) {
    if (raw == null) return '';
    final dt = DateTime.tryParse(raw.toString())?.toLocal();
    if (dt == null) return raw.toString();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(dt.day)}/${two(dt.month)}/${dt.year} ${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
  }

  Future<void> _confirmarEliminarPaso(Map<String, dynamic> paso) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('¿Eliminar ${paso['placa_normalizada'] ?? 'registro'}?', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: const Text(
          'Se eliminará este registro erróneo del sistema (si se cobró a un vehículo registrado, se reembolsará su saldo).',
          style: TextStyle(fontSize: 12.5),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626), foregroundColor: Colors.white),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      final resp = await http.delete(
        Uri.parse('${widget.baseUrl}/pasos/${paso['id']}'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer ${widget.token}',
        },
      ).timeout(const Duration(seconds: 12));
      if (!mounted) return;
      if (resp.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Registro eliminado correctamente'), duration: Duration(seconds: 2)),
        );
        await _cargarPasos(reiniciar: true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo eliminar (HTTP ${resp.statusCode})')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al eliminar: $e')));
      }
    }
  }

  void _abrirFotoZoom(String url) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          children: [
            InteractiveViewer(
              minScale: 0.8,
              maxScale: 4.0,
              child: Center(
                child: Image.network(url, fit: BoxFit.contain),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                style: IconButton.styleFrom(backgroundColor: Colors.black54),
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Barra superior de filtros y total
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '$_total registro(s) guardados',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 18, color: Color(0xFF475569)),
                    tooltip: 'Actualizar historial',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: _cargando ? null : () => _cargarPasos(reiniciar: true),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final filtro in const [
                      ('Todos', ''),
                      ('Registrada y con paso', 'Registrada y con paso'),
                      ('No registrada', 'Identificada no registrada'),
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: ChoiceChip(
                          label: Text(filtro.$1, style: const TextStyle(fontSize: 11)),
                          selected: _filtroEstado == filtro.$2,
                          onSelected: (_) {
                            setState(() => _filtroEstado = filtro.$2);
                            _cargarPasos(reiniciar: true);
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: Color(0xFFE2E8F0)),

        Expanded(
          child: _cargando
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF0F172A)))
              : RefreshIndicator(
                  onRefresh: () => _cargarPasos(reiniciar: true),
                  child: _errorMsg != null
                      ? ListView(
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(_errorMsg!, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF9F1239), fontSize: 12)),
                            ),
                          ],
                        )
                      : _pasos.isEmpty
                          ? ListView(
                              children: const [
                                Padding(
                                  padding: EdgeInsets.all(36),
                                  child: Text('No hay pasos registrados con este filtro.', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF64748B), fontSize: 12)),
                                ),
                              ],
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.all(12),
                              itemCount: _pasos.length + (_paginaActual < _ultimaPagina ? 1 : 0),
                              itemBuilder: (context, idx) {
                                if (idx == _pasos.length) {
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                    child: OutlinedButton(
                                      onPressed: _cargandoMas ? null : () => _cargarPasos(reiniciar: false),
                                      child: Text(_cargandoMas ? 'Cargando...' : 'Cargar más registros'),
                                    ),
                                  );
                                }

                                final p = _pasos[idx];
                                final bool esValido = p['estado'] == 'Registrada y con paso';
                                final String? imgUrl = _resolverMediaUrl(p['imagen_url']);
                                final double conf = double.tryParse('${p['confianza_ocr'] ?? 0}') ?? 0;
                                final int pasajeros = (p['pasajeros'] as num?)?.toInt() ?? 0;

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: const Color(0xFFE2E8F0)),
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      GestureDetector(
                                        onTap: imgUrl != null ? () => _abrirFotoZoom(imgUrl) : null,
                                        child: Container(
                                          width: 68,
                                          height: 68,
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFF1F5F9),
                                            borderRadius: BorderRadius.circular(10),
                                            border: Border.all(color: const Color(0xFFE2E8F0)),
                                          ),
                                          clipBehavior: Clip.antiAlias,
                                          child: imgUrl != null
                                              ? Image.network(
                                                  imgUrl,
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined, size: 22, color: Color(0xFF94A3B8)),
                                                )
                                              : const Icon(Icons.directions_car_outlined, size: 24, color: Color(0xFF94A3B8)),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    (p['placa_normalizada'] ?? p['placa_leida'] ?? 'SIN PLACA').toString(),
                                                    overflow: TextOverflow.ellipsis,
                                                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, fontFamily: 'monospace', color: Color(0xFF0F172A)),
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                                Flexible(
                                                  child: Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: esValido ? const Color(0xFFECFDF5) : const Color(0xFFFFF1F2),
                                                      borderRadius: BorderRadius.circular(6),
                                                      border: Border.all(color: esValido ? const Color(0xFF6EE7B7) : const Color(0xFFFDA4AF)),
                                                    ),
                                                    child: Text(
                                                      (p['estado'] ?? '').toString(),
                                                      maxLines: 2,
                                                      textAlign: TextAlign.center,
                                                      style: TextStyle(
                                                        fontSize: 9.5,
                                                        fontWeight: FontWeight.w600,
                                                        color: esValido ? const Color(0xFF065F46) : const Color(0xFF9F1239),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              '${(p['categoria_detectada'] ?? 'auto').toString().toUpperCase()} · ${p['ejes_detectados'] ?? 2} ejes · $pasajeros pas. · OCR ${(conf * 100).toStringAsFixed(0)}%',
                                              style: const TextStyle(fontSize: 11, color: Color(0xFF475569), fontWeight: FontWeight.w500),
                                            ),
                                            const SizedBox(height: 4),
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    '${p['caseta']?['nombre'] ?? 'Caseta 1'} · ${_formatFecha(p['created_at'])}',
                                                    overflow: TextOverflow.ellipsis,
                                                    style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8)),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Text(
                                                  'Bs. ${p['monto'] ?? '0.00'}',
                                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF059669)),
                                                ),
                                                if (widget.esAdmin) ...[
                                                  const SizedBox(width: 6),
                                                  InkWell(
                                                    onTap: () => _confirmarEliminarPaso(p),
                                                    borderRadius: BorderRadius.circular(6),
                                                    child: const Padding(
                                                      padding: EdgeInsets.all(4.0),
                                                      child: Icon(Icons.delete_outline, size: 17, color: Color(0xFFE11D48)),
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                ),
        ),
      ],
    );
  }
}

// -------------------------------------------------------------
// MODO CONSULTA (AGENTE CONVERSACIONAL EXCLUSIVO DE PEAJE)
// -------------------------------------------------------------
class ModoConsultaScreen extends StatefulWidget {
  final String token;
  final String baseUrl;
  final List<Map<String, dynamic>> mensajes;
  final VoidCallback onResetMensajes;

  const ModoConsultaScreen({
    super.key,
    required this.token,
    required this.baseUrl,
    required this.mensajes,
    required this.onResetMensajes,
  });

  @override
  State<ModoConsultaScreen> createState() => _ModoConsultaScreenState();
}

class _ModoConsultaScreenState extends State<ModoConsultaScreen> {
  static const int _maxImagenes = 6;
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _picker = ImagePicker();
  bool _loading = false;
  bool _verificandoEstado = false;
  String _estadoVision = 'offline';
  String _estadoOllama = 'offline';
  final List<Uint8List> _imagenesPendientes = [];

  @override
  void initState() {
    super.initState();
    _verificarConexion();
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollAbajo() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _verificarConexion() async {
    if (_verificandoEstado) return;
    setState(() => _verificandoEstado = true);
    try {
      final resp = await http
          .get(
            Uri.parse('${widget.baseUrl}/estado/inferencia'),
            headers: {
              'Accept': 'application/json',
              'Authorization': 'Bearer ${widget.token}',
            },
          )
          .timeout(const Duration(seconds: 8));
      if (!mounted) return;
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        if (data is Map<String, dynamic>) {
          final modelos = data['modelos'];
          final bool ollamaActivo = modelos is Map && modelos['ollama_llm'] == true;
          setState(() {
            _estadoVision = data['status'] == 'online' ? 'online' : 'offline';
            _estadoOllama = (data['ollama_status'] ?? (ollamaActivo ? 'online' : 'offline')).toString();
          });
          return;
        }
      }
      setState(() {
        _estadoVision = 'offline';
        _estadoOllama = 'offline';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _estadoVision = 'offline';
        _estadoOllama = 'offline';
      });
    } finally {
      if (mounted) {
        setState(() => _verificandoEstado = false);
      }
    }
  }

  void _reiniciarChat() {
    widget.onResetMensajes();
    setState(() {
      _imagenesPendientes.clear();
      _textController.clear();
    });
    _scrollAbajo();
  }

  Future<void> _consultar({String? textoOverride}) async {
    final texto = (textoOverride ?? _textController.text).trim();
    final imagenes = List<Uint8List>.from(_imagenesPendientes);

    if (texto.isEmpty && imagenes.isEmpty) return;

    final historial = widget.mensajes
        .reversed
        .take(12)
        .toList()
        .reversed
        .map((m) => {'role': m['role'], 'content': m['text']})
        .toList();

    setState(() {
      _loading = true;
      widget.mensajes.add({
        'role': 'user',
        'text': texto.isNotEmpty
            ? texto
            : 'Analizar ${imagenes.length} imagen(es) vehicular(es)',
        'imagenes': imagenes,
        'fueraDominio': false,
        'analisis': <dynamic>[],
        'resumenLote': null,
      });
      if (textoOverride == null) {
        _textController.clear();
      }
      _imagenesPendientes.clear();
    });
    _scrollAbajo();

    try {
      final body = <String, dynamic>{'historial': historial};
      if (texto.isNotEmpty) {
        body['mensaje'] = texto;
      }
      if (imagenes.isNotEmpty) {
        final listaB64 = imagenes
            .map((bytes) => 'data:image/jpeg;base64,${base64Encode(bytes)}')
            .toList();
        body['imagenes_base64'] = listaB64;
        if (listaB64.length == 1) {
          body['imagen_base64'] = listaB64.first;
        }
      }

      final resp = await http
          .post(
            Uri.parse('${widget.baseUrl}/agente/chat'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              'Authorization': 'Bearer ${widget.token}',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 45));

      dynamic data;
      try {
        data = jsonDecode(resp.body);
      } catch (_) {
        data = null;
      }

      if (!mounted) return;
      if (resp.statusCode >= 400) {
        final msgErr = (data is Map ? (data['respuesta'] ?? data['message']) : null) ??
            'Error HTTP ${resp.statusCode} al consultar el agente.';
        setState(() {
          widget.mensajes.add({
            'role': 'assistant',
            'text': msgErr.toString(),
            'imagenes': <Uint8List>[],
            'fueraDominio': false,
            'analisis': <dynamic>[],
            'resumenLote': null,
          });
        });
        return;
      }

      final mapData = data is Map<String, dynamic> ? data : <String, dynamic>{};
      setState(() {
        widget.mensajes.add({
          'role': 'assistant',
          'text': (mapData['respuesta'] ?? 'Sin respuesta del agente.').toString(),
          'imagenes': <Uint8List>[],
          'fueraDominio': mapData['estado'] == 'Fuera de dominio',
          'analisis': (mapData['analisis_imagenes'] as List<dynamic>?) ?? <dynamic>[],
          'resumenLote': mapData['resumen_lote'],
        });
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        widget.mensajes.add({
          'role': 'assistant',
          'text': 'No se pudo conectar con el agente: $e',
          'imagenes': <Uint8List>[],
          'fueraDominio': false,
          'analisis': <dynamic>[],
          'resumenLote': null,
        });
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
        _scrollAbajo();
      }
    }
  }

  void _mostrarAvisoLimite() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Máximo 6 imágenes por consulta.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _seleccionarVariasImagenes() async {
    final List<XFile> photos = await _picker.pickMultiImage();
    if (photos.isEmpty) return;

    final disponibles = _maxImagenes - _imagenesPendientes.length;
    if (disponibles <= 0) {
      _mostrarAvisoLimite();
      return;
    }

    if (photos.length > disponibles) {
      _mostrarAvisoLimite();
    }

    final lote = photos.take(disponibles);
    final nuevas = <Uint8List>[];
    for (final photo in lote) {
      nuevas.add(await photo.readAsBytes());
    }
    if (!mounted) return;
    setState(() {
      _imagenesPendientes.addAll(nuevas);
    });
  }

  Future<void> _tomarFotoPlaca() async {
    if (_imagenesPendientes.length >= _maxImagenes) {
      _mostrarAvisoLimite();
      return;
    }
    final XFile? photo = await _picker.pickImage(source: ImageSource.camera);
    if (photo == null) return;
    final bytes = await photo.readAsBytes();
    if (!mounted) return;
    setState(() {
      _imagenesPendientes.add(bytes);
    });
  }

  void _abrirZoomImagen(Uint8List bytes) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          children: [
            InteractiveViewer(
              minScale: 0.8,
              maxScale: 4.0,
              child: Center(child: Image.memory(bytes, fit: BoxFit.contain)),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                style: IconButton.styleFrom(backgroundColor: Colors.black54),
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<InlineSpan> _parseFormattedSpans(String text, {required bool isUser}) {
    final baseColor = isUser ? Colors.white : const Color(0xFF334155);
    final codeBg = isUser ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9);
    final codeFg = isUser ? const Color(0xFFE2E8F0) : const Color(0xFF0F172A);
    final baseStyle = TextStyle(fontSize: 13, height: 1.45, color: baseColor);

    final pattern = RegExp(r'\*\*(.+?)\*\*|`([^`]+)`|\*([^*\n]+)\*');
    final spans = <InlineSpan>[];
    int cursor = 0;

    for (final match in pattern.allMatches(text)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, match.start), style: baseStyle));
      }
      if (match.group(1) != null) {
        spans.add(
          TextSpan(
            text: match.group(1),
            style: baseStyle.copyWith(fontWeight: FontWeight.w700),
          ),
        );
      } else if (match.group(2) != null) {
        spans.add(
          TextSpan(
            text: ' ${match.group(2)} ',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              height: 1.45,
              color: codeFg,
              backgroundColor: codeBg,
            ),
          ),
        );
      } else if (match.group(3) != null) {
        spans.add(
          TextSpan(
            text: match.group(3),
            style: baseStyle.copyWith(fontStyle: FontStyle.italic),
          ),
        );
      }
      cursor = match.end;
    }

    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor), style: baseStyle));
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final mensajes = widget.mensajes;
    final totalItems = mensajes.length + (_loading ? 1 : 0);

    return Column(
      children: [
        // Cabecera compacta de estado en vivo
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: const BoxDecoration(
            color: Color(0xFF0F172A),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Agente Exclusivo de Peaje',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 10,
                      runSpacing: 2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _estadoVision == 'online'
                                    ? const Color(0xFF34D399)
                                    : const Color(0xFFFB7185),
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              'Visión M1–M4: ${_estadoVision == 'online' ? 'En línea' : 'Offline'}',
                              style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 11),
                            ),
                          ],
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _estadoOllama == 'online'
                                    ? const Color(0xFF34D399)
                                    : (_estadoOllama == 'sin_modelo'
                                        ? const Color(0xFFFBBF24)
                                        : const Color(0xFFFB7185)),
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              'LLM: ${_estadoOllama == 'online' ? 'Activo' : (_estadoOllama == 'sin_modelo' ? 'Sin modelo' : 'Offline')}',
                              style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 11),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Verificar estado RunPod y Ollama',
                onPressed: _verificandoEstado ? null : _verificarConexion,
                icon: Icon(
                  Icons.refresh,
                  size: 18,
                  color: _verificandoEstado ? const Color(0xFF64748B) : Colors.white,
                ),
              ),
              TextButton(
                onPressed: _loading ? null : _reiniciarChat,
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFCBD5E1),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  minimumSize: Size.zero,
                ),
                child: const Text('Limpiar', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ),

        if (_estadoOllama == 'sin_modelo')
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: const BoxDecoration(
              color: Color(0xFFFFFBEB),
              border: Border(bottom: BorderSide(color: Color(0xFFFDE68A))),
            ),
            child: const Text(
              'Visión M1–M4 y consultas a BD activas en RunPod. Ollama espera modelo (llama3.2:3b) para redacción libre.',
              style: TextStyle(color: Color(0xFF92400E), fontSize: 11),
            ),
          ),

        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final chip in const [
                        ('Tarifas', '¿Cuáles son las tarifas vigentes por categoría y ejes?'),
                        ('Resumen de hoy', 'Dame el resumen de pasos, recaudación y vehículos registrados'),
                        ('Alertas activas', '¿Cuántas alertas pendientes hay y cuáles son?'),
                        ('Modelos M1–M4', 'Explícame cómo funcionan los modelos M1, M2, M3 y M4 en el peaje'),
                      ])
                        Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: ActionChip(
                            label: Text(chip.$1, style: const TextStyle(fontSize: 11)),
                            onPressed: _loading ? null : () => _consultar(textoOverride: chip.$2),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.builder(
                    controller: _scrollController,
                    itemCount: totalItems,
                    itemBuilder: (context, index) {
                      if (_loading && index == mensajes.length) {
                        return TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: 1),
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                          builder: (context, value, child) => Opacity(
                            opacity: value,
                            child: Transform.translate(
                              offset: Offset(0, 8 * (1 - value)),
                              child: child,
                            ),
                          ),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _TypingDotsIndicator(),
                                  SizedBox(width: 8),
                                  Text(
                                    'Analizando en RunPod y consultando peaje...',
                                    style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }

                      final msg = mensajes[index];
                      final isUser = msg['role'] == 'user';
                      final fueraDominio = msg['fueraDominio'] == true;
                      final imgs = (msg['imagenes'] as List<Uint8List>?) ?? <Uint8List>[];
                      final analisis = (msg['analisis'] as List<dynamic>?) ?? <dynamic>[];
                      final resumenLote = msg['resumenLote'];

                      return TweenAnimationBuilder<double>(
                        key: ValueKey('msg_$index'),
                        tween: Tween(begin: 0, end: 1),
                        duration: const Duration(milliseconds: 240),
                        curve: Curves.easeOutCubic,
                        builder: (context, value, child) => Opacity(
                          opacity: value,
                          child: Transform.translate(
                            offset: Offset(0, 10 * (1 - value)),
                            child: child,
                          ),
                        ),
                        child: Align(
                        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.85,
                          ),
                          decoration: BoxDecoration(
                            color: isUser
                                ? const Color(0xFF0F172A)
                                : (fueraDominio ? const Color(0xFFFFFBEB) : Colors.white),
                            borderRadius: BorderRadius.circular(12),
                            border: isUser
                                ? null
                                : Border.all(
                                    color: fueraDominio
                                        ? const Color(0xFFFDE68A)
                                        : const Color(0xFFE2E8F0),
                                  ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (!isUser && fueraDominio)
                                Container(
                                  margin: const EdgeInsets.only(bottom: 6),
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFEF3C7),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text(
                                    'Fuera de dominio',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF92400E),
                                    ),
                                  ),
                                ),
                              if (imgs.isNotEmpty) ...[
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: imgs
                                      .map(
                                        (b) => GestureDetector(
                                          onTap: () => _abrirZoomImagen(b),
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(8),
                                            child: Image.memory(
                                              b,
                                              width: 68,
                                              height: 68,
                                              fit: BoxFit.cover,
                                            ),
                                          ),
                                        ),
                                      )
                                      .toList(),
                                ),
                                const SizedBox(height: 8),
                              ],
                              if (!isUser && analisis.isNotEmpty) ...[
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: analisis.whereType<Map<String, dynamic>>().map((item) {
                                    if (item['exito'] != true) {
                                      return Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFFF1F2),
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: const Color(0xFFFECDD3)),
                                        ),
                                        child: Text(
                                          '#${item['indice']} Error',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Color(0xFF9F1239),
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      );
                                    }
                                    final placa = (item['placa_normalizada'] ?? '').toString().isNotEmpty
                                        ? item['placa_normalizada']
                                        : (item['placa_detectada'] ?? 'N/L');
                                    final tarifa = item['tarifa_estimada'] ?? 0;
                                    return Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF8FAFC),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: const Color(0xFFCBD5E1)),
                                      ),
                                      child: Text(
                                        '#${item['indice']} · $placa · ${item['categoria']} · ${item['ejes']} ejes · ${item['pasajeros']} pas. · Bs. $tarifa',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: Color(0xFF0F172A),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                                if (resumenLote is Map<String, dynamic> && analisis.length > 1) ...[
                                  const SizedBox(height: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFECFDF5),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: const Color(0xFFA7F3D0)),
                                    ),
                                    child: Text(
                                      'Lote ${resumenLote['exitosas']}/${resumenLote['total_imagenes']} · ${resumenLote['total_pasajeros']} pas. · Total Bs. ${resumenLote['total_tarifa_bs']}',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Color(0xFF065F46),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 8),
                              ],
                              RichText(
                                text: TextSpan(
                                  children: _parseFormattedSpans(
                                    (msg['text'] ?? '').toString(),
                                    isUser: isUser,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: _imagenesPendientes.isEmpty
                        ? const SizedBox.shrink()
                        : Container(
                            key: ValueKey('queue_${_imagenesPendientes.length}'),
                            margin: const EdgeInsets.only(top: 6, bottom: 8),
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      '${_imagenesPendientes.length}/$_maxImagenes imágenes listas para analizar',
                                      style: const TextStyle(fontSize: 11, color: Color(0xFF475569)),
                                    ),
                                    GestureDetector(
                                      onTap: _loading ? null : () => setState(() => _imagenesPendientes.clear()),
                                      child: const Text(
                                        'Quitar todas',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Color(0xFFE11D48),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                SizedBox(
                                  height: 64,
                                  child: ListView.separated(
                                    scrollDirection: Axis.horizontal,
                                    itemCount: _imagenesPendientes.length,
                                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                                    itemBuilder: (context, idx) {
                                      return Stack(
                                        children: [
                                          GestureDetector(
                                            onTap: () => _abrirZoomImagen(_imagenesPendientes[idx]),
                                            child: ClipRRect(
                                              borderRadius: BorderRadius.circular(8),
                                              child: Image.memory(
                                                _imagenesPendientes[idx],
                                                width: 62,
                                                height: 62,
                                                fit: BoxFit.cover,
                                              ),
                                            ),
                                          ),
                                          Positioned(
                                            top: 2,
                                            right: 2,
                                            child: GestureDetector(
                                              onTap: () => setState(() => _imagenesPendientes.removeAt(idx)),
                                              child: Container(
                                                width: 18,
                                                height: 18,
                                                decoration: const BoxDecoration(
                                                  color: Colors.black87,
                                                  shape: BoxShape.circle,
                                                ),
                                                child: const Icon(Icons.close, size: 12, color: Colors.white),
                                              ),
                                            ),
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                  ),
                ),
                Row(
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        IconButton(
                          tooltip: 'Subir varias fotos (máx. 6)',
                          style: IconButton.styleFrom(side: const BorderSide(color: Color(0xFFCBD5E1))),
                          icon: const Icon(Icons.photo_library_outlined, size: 18, color: Color(0xFF0F172A)),
                          onPressed: _loading ? null : _seleccionarVariasImagenes,
                        ),
                        if (_imagenesPendientes.isNotEmpty)
                          Positioned(
                            right: -2,
                            top: -2,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: const BoxDecoration(
                                color: Color(0xFF0F172A),
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                '${_imagenesPendientes.length}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      tooltip: 'Tomar foto',
                      style: IconButton.styleFrom(side: const BorderSide(color: Color(0xFFCBD5E1))),
                      icon: const Icon(Icons.camera_alt_outlined, size: 18, color: Color(0xFF0F172A)),
                      onPressed: _loading ? null : _tomarFotoPlaca,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: TextField(
                        controller: _textController,
                        style: const TextStyle(fontSize: 12, color: Color(0xFF0F172A)),
                        onSubmitted: _loading ? null : (_) => _consultar(),
                        decoration: InputDecoration(
                          hintText: 'Consulta placa, tarifas o pregunta...',
                          hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xFF0F172A),
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.send, size: 16),
                      onPressed: _loading ? null : () => _consultar(),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TypingDotsIndicator extends StatefulWidget {
  const _TypingDotsIndicator();

  @override
  State<_TypingDotsIndicator> createState() => _TypingDotsIndicatorState();
}

class _TypingDotsIndicatorState extends State<_TypingDotsIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final t = (_controller.value - i * 0.2).clamp(0.0, 1.0);
            final wave = (t < 0.5 ? t * 2 : (1 - t) * 2).clamp(0.0, 1.0);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1.5),
              child: Transform.translate(
                offset: Offset(0, -3.0 * wave),
                child: Opacity(
                  opacity: 0.35 + 0.65 * wave,
                  child: Container(
                    width: 5,
                    height: 5,
                    decoration: const BoxDecoration(
                      color: Color(0xFF0F172A),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
