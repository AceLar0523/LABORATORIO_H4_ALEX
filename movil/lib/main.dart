import 'dart:async';
import 'dart:convert';
import 'dart:io' show File;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:camera/camera.dart';
import 'package:video_player/video_player.dart';

List<CameraDescription> gAvailableCameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb) {
    try {
      gAvailableCameras = await availableCameras();
    } catch (_) {
      gAvailableCameras = [];
    }
  }
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
    // Detección automática de IP según entorno de ejecución:
    // - En Web: localhost (mismo navegador)
    // - En Emulador Android Studio: 10.0.2.2 (alias hacia el localhost del PC)
    // - En Celular Físico: IP de red Wi-Fi
    if (kIsWeb) {
      _baseUrl = 'http://localhost:8000/api/v1';
    } else if (defaultTargetPlatform == TargetPlatform.android) {
      _baseUrl = 'http://10.0.2.2:8000/api/v1';
    } else {
      _baseUrl = 'http://192.168.1.207:8000/api/v1';
    }
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
  late final TextEditingController _serverController;
  final TextEditingController _emailController = TextEditingController(text: 'admin@peaje.com');
  final TextEditingController _passwordController = TextEditingController(text: 'admin123');
  bool _loading = false;
  String? _errorMessage;
  bool _modoCredenciales = false;
  bool _probandoConexion = false;
  String? _testConexionResult;
  bool _testConexionOk = false;

  @override
  void initState() {
    super.initState();
    _serverController = TextEditingController(text: widget.initialBaseUrl);
  }

  Future<void> _probarConexion() async {
    setState(() {
      _probandoConexion = true;
      _testConexionResult = null;
      _testConexionOk = false;
    });

    try {
      final base = _serverController.text.trim();
      final url = Uri.parse('$base/ping');
      final res = await http.get(url).timeout(const Duration(seconds: 4));

      if (res.statusCode == 200) {
        setState(() {
          _testConexionOk = true;
          _testConexionResult = '¡Conexión exitosa con el servidor! (HTTP 200)';
        });
      } else {
        setState(() {
          _testConexionOk = false;
          _testConexionResult = 'Servidor respondió con código HTTP ${res.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        _testConexionOk = false;
        _testConexionResult = 'No se pudo conectar: verifica que el backend esté corriendo en el puerto 8000';
      });
    } finally {
      setState(() {
        _probandoConexion = false;
      });
    }
  }

  Future<void> _loginCredenciales() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final url = Uri.parse('${_serverController.text.trim()}/auth/login');
      final resp = await http.post(
        url,
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: jsonEncode({
          'email': _emailController.text.trim(),
          'password': _passwordController.text.trim(),
        }),
      ).timeout(const Duration(seconds: 6));

      final data = jsonDecode(resp.body);

      if (resp.statusCode == 200 && data['success'] == true) {
        widget.onLoginSuccess(data['token'], data['usuario'], _serverController.text.trim());
      } else {
        setState(() {
          _errorMessage = data['message'] ?? 'Credenciales inválidas.';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error conectando al servidor: $e';
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _loginGoogle(String email) async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final url = Uri.parse('${_serverController.text.trim()}/auth/google');
      final resp = await http.post(
        url,
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: jsonEncode({
          'email': email,
          'name': email.split('@')[0],
          'id_token': 'mobile_google_token_$email',
        }),
      ).timeout(const Duration(seconds: 6));

      final data = jsonDecode(resp.body);

      if (resp.statusCode == 200 && data['success'] == true) {
        widget.onLoginSuccess(data['token'], data['usuario'], _serverController.text.trim());
      } else {
        setState(() {
          _errorMessage = data['message'] ?? 'Acceso denegado. Cuenta no autorizada.';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error conectando al servidor: $e';
      });
    } finally {
      setState(() {
        _loading = false;
      });
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
                  // Logo e Identidad
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

                  // Configuración de Servidor en Dev
                  Container(
                    padding: const EdgeInsets.all(12),
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
                            const Text(
                              'Servidor API (Dev)',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
                            ),
                            InkWell(
                              onTap: _probandoConexion ? null : _probarConexion,
                              child: Text(
                                _probandoConexion ? 'Probando...' : 'Probar conexión',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF2563EB)),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _serverController,
                          style: const TextStyle(fontSize: 12, color: Color(0xFF0F172A), fontFamily: 'monospace'),
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            fillColor: Colors.white,
                            filled: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: [
                            ActionChip(
                              avatar: const Icon(Icons.android, size: 14),
                              label: const Text('Emulador (10.0.2.2)', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                              padding: EdgeInsets.zero,
                              visualDensity: VisualDensity.compact,
                              onPressed: () {
                                setState(() {
                                  _serverController.text = 'http://10.0.2.2:8000/api/v1';
                                });
                                _probarConexion();
                              },
                            ),
                            ActionChip(
                              avatar: const Icon(Icons.language, size: 14),
                              label: const Text('Web / Localhost', style: TextStyle(fontSize: 10)),
                              padding: EdgeInsets.zero,
                              visualDensity: VisualDensity.compact,
                              onPressed: () {
                                setState(() {
                                  _serverController.text = 'http://localhost:8000/api/v1';
                                });
                                _probarConexion();
                              },
                            ),
                            ActionChip(
                              avatar: const Icon(Icons.wifi, size: 14),
                              label: const Text('Wi-Fi Celular (192.168.1.207)', style: TextStyle(fontSize: 10)),
                              padding: EdgeInsets.zero,
                              visualDensity: VisualDensity.compact,
                              onPressed: () {
                                setState(() {
                                  _serverController.text = 'http://192.168.1.207:8000/api/v1';
                                });
                                _probarConexion();
                              },
                            ),
                          ],
                        ),
                        if (_testConexionResult != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            _testConexionResult!,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              color: _testConexionOk ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

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

                  // Selector de Pestañas: Google OAuth 2.0 (Principal) o Usuario & Contraseña
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.all(3),
                    child: Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () => setState(() => _modoCredenciales = false),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: !_modoCredenciales ? Colors.white : Colors.transparent,
                                borderRadius: BorderRadius.circular(6),
                                boxShadow: !_modoCredenciales ? const [BoxShadow(color: Color(0x0A000000), blurRadius: 4)] : null,
                              ),
                              child: Text(
                                'Google OAuth 2.0',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: !_modoCredenciales ? const Color(0xFF0F172A) : const Color(0xFF64748B),
                                  fontSize: 12,
                                  fontWeight: !_modoCredenciales ? FontWeight.w600 : FontWeight.normal,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: InkWell(
                            onTap: () => setState(() => _modoCredenciales = true),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: _modoCredenciales ? Colors.white : Colors.transparent,
                                borderRadius: BorderRadius.circular(6),
                                boxShadow: _modoCredenciales ? const [BoxShadow(color: Color(0x0A000000), blurRadius: 4)] : null,
                              ),
                              child: Text(
                                'Usuario & Clave',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: _modoCredenciales ? const Color(0xFF0F172A) : const Color(0xFF64748B),
                                  fontSize: 12,
                                  fontWeight: _modoCredenciales ? FontWeight.w600 : FontWeight.normal,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // CONTENIDO 1: GOOGLE OAUTH 2.0 (OPCIÓN PRINCIPAL)
                  if (!_modoCredenciales) ...[
                    // Botón Principal Estilo Google
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        backgroundColor: Colors.white,
                        side: const BorderSide(color: Color(0xFFCBD5E1), width: 1.2),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: _loading ? null : () => _loginGoogle('docente@peaje.edu'),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildGoogleIcon(),
                          const SizedBox(width: 10),
                          const Text(
                            'Continuar con Google',
                            style: TextStyle(
                              color: Color(0xFF0F172A),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Acceso directo Operador
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F172A),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: _loading ? null : () => _loginGoogle('operador@peaje.com'),
                      child: Text(
                        _loading ? 'Autenticando...' : 'Acceder como Operador de Caseta',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Botón de prueba de rechazo para el evaluador / docente
                    TextButton(
                      onPressed: _loading ? null : () => _loginGoogle('noautorizado@gmail.com'),
                      child: const Text(
                        'Probar rechazo de cuenta ajena (Demostración Lista Blanca)',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, decoration: TextDecoration.underline),
                      ),
                    ),
                  ] else ...[
                    // CONTENIDO 2: CREDENCIALES DIRECTAS
                    TextField(
                      controller: _emailController,
                      style: const TextStyle(fontSize: 12, color: Color(0xFF0F172A)),
                      decoration: InputDecoration(
                        labelText: 'Correo Electrónico',
                        labelStyle: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _passwordController,
                      obscureText: true,
                      style: const TextStyle(fontSize: 12, color: Color(0xFF0F172A)),
                      decoration: InputDecoration(
                        labelText: 'Contraseña',
                        labelStyle: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                      ),
                    ),
                    const SizedBox(height: 14),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F172A),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: _loading ? null : _loginCredenciales,
                      child: Text(
                        _loading ? 'Autenticando...' : 'Iniciar Sesión',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
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
// PANTALLA PRINCIPAL CON NAVEGACIÓN
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

  @override
  Widget build(BuildContext context) {
    final screens = [
      ModoCasetaScreen(token: widget.token, baseUrl: widget.baseUrl),
      ModoConsultaScreen(token: widget.token, baseUrl: widget.baseUrl),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(_currentIndex == 0 ? 'Caseta de Peaje' : 'Consulta Vehicular'),
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
            icon: Icon(Icons.search_outlined, size: 20),
            selectedIcon: Icon(Icons.search, size: 20, color: Color(0xFF0F172A)),
            label: 'Modo Consulta',
          ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------
// MODO CASETA (Saca Foto, Sube Foto, Video y Cámara en Live)
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
  bool _processing = false;
  Map<String, dynamic>? _lastResult;

  // Video Controller
  VideoPlayerController? _videoController;
  bool _isPlayingVideo = false;

  // Live Camera Controller & Scanner Timer
  CameraController? _cameraController;
  bool _isLiveScanning = false;
  Timer? _liveScanTimer;
  bool _isCameraInitialized = false;

  @override
  void initState() {
    super.initState();
    _initLiveCamera();
  }

  Future<void> _initLiveCamera() async {
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
    _cameraController?.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  // Toggle Live Mode
  void _toggleLiveMode() {
    setState(() {
      _isLiveScanning = !_isLiveScanning;
    });

    if (_isLiveScanning) {
      // Iniciar temporizador cada 2.5 segundos para captura y reconocimiento en tiempo real
      _liveScanTimer = Timer.periodic(const Duration(milliseconds: 2500), (timer) {
        if (!_processing && _cameraController != null && _cameraController!.value.isInitialized) {
          _capturarFrameLive();
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🟢 Modo Live Activo: Detectando vehículos automáticamente...'),
          duration: Duration(seconds: 2),
        ),
      );
    } else {
      _liveScanTimer?.cancel();
      _liveScanTimer = null;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⏹ Modo Live Pausado'),
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
      if (mounted) {
        setState(() {
          _capturedImageBytes = bytes;
        });
      }
      await _enviarFrameAI(bytes, esLive: true);
    } catch (_) {}
  }

  // Subir o Sacar Foto
  Future<void> _capturarFoto(ImageSource source) async {
    if (_isLiveScanning) {
      _toggleLiveMode(); // Pausar live si toma foto manual
    }
    _videoController?.pause();

    final XFile? photo = await _picker.pickImage(source: source, maxWidth: 900, imageQuality: 85);
    if (photo == null) return;

    final bytes = await photo.readAsBytes();
    setState(() {
      _capturedImageBytes = bytes;
    });

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
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_isPlayingVideo ? 'Video cargado en reproducción. Puedes pausar o sacar captura.' : 'Video listo.'),
      ),
    );
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
        }),
      ).timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);
      if (response.statusCode == 201 && data['success'] == true) {
        if (mounted) {
          setState(() {
            _lastResult = data;
          });
        }
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

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // VISOR PRINCIPAL (Cámara Live, Video o Imagen Capturada)
          Container(
            height: 250,
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _isLiveScanning ? const Color(0xFF10B981) : const Color(0xFFE2E8F0),
                width: _isLiveScanning ? 2.5 : 1,
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
                    CameraPreview(_cameraController!)
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
                      child: AspectRatio(
                        aspectRatio: _videoController!.value.aspectRatio,
                        child: VideoPlayer(_videoController!),
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

                  // Overlay Badge en Modo Live
                  if (_isLiveScanning)
                    Positioned(
                      top: 12,
                      left: 12,
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
                            Icon(Icons.fiber_manual_record, color: Colors.white, size: 12),
                            SizedBox(width: 6),
                            Text(
                              'EN VIVO • ESCANEANDO IA',
                              style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // Overlay si está procesando
                  if (_processing)
                    Positioned(
                      bottom: 12,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                            SizedBox(width: 8),
                            Text('Analizando M1..M4...', style: TextStyle(color: Colors.white, fontSize: 10)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 14),

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

          // Botón secundario: Cargar Video
          OutlinedButton.icon(
            icon: const Icon(Icons.video_library_outlined, size: 18, color: Color(0xFF475569)),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 10),
              side: const BorderSide(color: Color(0xFFE2E8F0)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: _seleccionarVideo,
            label: const Text(
              'Cargar y Reproducir Video de Caseta (Demostración)',
              style: TextStyle(fontSize: 12, color: Color(0xFF475569)),
            ),
          ),

          // TARJETA DE RESULTADO DE DETECCIÓN IA
          if (_lastResult != null) ...[
            const SizedBox(height: 16),
            _buildResultCard(_lastResult!['paso'], _lastResult!['latencia_ms']),
          ],
        ],
      ),
    );
  }

  Widget _buildResultCard(Map<String, dynamic> paso, dynamic latencia) {
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('PLACA RECONOCIDA (M1 + OCR)', style: TextStyle(fontSize: 10, color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    paso['placa_normalizada'] ?? 'DESCONOCIDA',
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF0F172A), letterSpacing: 1.5, fontFamily: 'monospace'),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: esValido ? const Color(0xFFECFDF5) : const Color(0xFFFFF1F2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: esValido ? const Color(0xFF6EE7B7) : const Color(0xFFFDA4AF)),
                ),
                child: Text(
                  paso['estado'] ?? '',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: esValido ? const Color(0xFF065F46) : const Color(0xFF9F1239),
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
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '• Caseta: ${paso['caseta']?['nombre'] ?? 'Principal 1'}',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                ),
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

// -------------------------------------------------------------
// MODO CONSULTA (AGENTE CONVERSACIONAL)
// -------------------------------------------------------------
class ModoConsultaScreen extends StatefulWidget {
  final String token;
  final String baseUrl;
  const ModoConsultaScreen({super.key, required this.token, required this.baseUrl});

  @override
  State<ModoConsultaScreen> createState() => _ModoConsultaScreenState();
}

class _ModoConsultaScreenState extends State<ModoConsultaScreen> {
  final TextEditingController _textController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  bool _loading = false;
  String? _agentResponse;

  Future<void> _consultar({String? texto, Uint8List? imagenBytes}) async {
    setState(() {
      _loading = true;
      _agentResponse = null;
    });

    try {
      final body = <String, dynamic>{};
      if (texto != null && texto.isNotEmpty) {
        body['mensaje'] = texto;
      }
      if (imagenBytes != null) {
        body['imagen_base64'] = 'data:image/jpeg;base64,${base64Encode(imagenBytes)}';
      }

      final resp = await http.post(
        Uri.parse('${widget.baseUrl}/agente/chat'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer ${widget.token}',
        },
        body: jsonEncode(body),
      );

      final data = jsonDecode(resp.body);
      setState(() {
        _agentResponse = data['respuesta'];
      });
    } catch (e) {
      setState(() {
        _agentResponse = 'No se pudo conectar con el agente: $e';
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _subirFotoPlaca() async {
    final XFile? photo = await _picker.pickImage(source: ImageSource.gallery);
    if (photo == null) return;
    final bytes = await photo.readAsBytes();
    _consultar(imagenBytes: bytes);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _textController,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF0F172A)),
                  decoration: InputDecoration(
                    hintText: 'Ingresa placa (ej. 4021XYZ)',
                    hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                style: IconButton.styleFrom(backgroundColor: const Color(0xFF0F172A), foregroundColor: Colors.white),
                icon: const Icon(Icons.send, size: 16),
                onPressed: _loading ? null : () => _consultar(texto: _textController.text),
              ),
              IconButton(
                style: IconButton.styleFrom(side: const BorderSide(color: Color(0xFFCBD5E1))),
                icon: const Icon(Icons.camera_alt_outlined, size: 18, color: Color(0xFF0F172A)),
                onPressed: _loading ? null : _subirFotoPlaca,
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_loading) const Center(child: CircularProgressIndicator(color: Color(0xFF0F172A))),
          if (_agentResponse != null)
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    _agentResponse!,
                    style: const TextStyle(fontSize: 13, height: 1.5, color: Color(0xFF334155)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
