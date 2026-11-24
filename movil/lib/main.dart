import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
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
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blueAccent,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const AuthGate(),
    );
  }
}

// -------------------------------------------------------------
// CONTROLADOR DE ACCESO CON GOOGLE OAUTH
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

  @override
  void initState() {
    super.initState();
    _checkSavedSession();
  }

  Future<void> _checkSavedSession() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('peaje_token');
    final userRaw = prefs.getString('peaje_user');

    if (token != null && userRaw != null) {
      setState(() {
        _token = token;
        _user = jsonDecode(userRaw);
        _isLoading = false;
      });
    } else {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _onLoginSuccess(String token, Map<String, dynamic> user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('peaje_token', token);
    await prefs.setString('peaje_user', jsonEncode(user));
    setState(() {
      _token = token;
      _user = user;
    });
  }

  void _onLogout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    setState(() {
      _token = null;
      _user = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_token == null) {
      return LoginScreen(onLoginSuccess: _onLoginSuccess);
    }

    return MainHomeScreen(
      user: _user!,
      token: _token!,
      onLogout: _onLogout,
    );
  }
}

// -------------------------------------------------------------
// PANTALLA DE LOGIN CON GOOGLE
// -------------------------------------------------------------
class LoginScreen extends StatefulWidget {
  final Function(String, Map<String, dynamic>) onLoginSuccess;
  const LoginScreen({super.key, required this.onLoginSuccess});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _serverController =
      TextEditingController(text: 'http://10.0.2.2:8000/api/v1');
  bool _loading = false;
  String? _errorMessage;

  Future<void> _loginGoogle(String email) async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final url = Uri.parse('${_serverController.text}/auth/google');
      final resp = await http.post(
        url,
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: jsonEncode({
          'email': email,
          'name': email.split('@')[0],
          'id_token': 'mobile_google_token_$email',
        }),
      );

      final data = jsonDecode(resp.body);

      if (resp.statusCode == 200 && data['success'] == true) {
        widget.onLoginSuccess(data['token'], data['usuario']);
      } else {
        setState(() {
          _errorMessage = data['message'] ?? 'Acceso no autorizado por lista blanca.';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.toll_rounded, size: 70, color: Colors.blueAccent),
              const SizedBox(height: 16),
              const Text(
                'Peaje Inteligente',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const Text(
                'Acceso Operadores y Administradores (Google OAuth)',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.white54),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _serverController,
                decoration: InputDecoration(
                  labelText: 'URL API del Peaje',
                  filled: true,
                  fillColor: const Color(0xFF1E293B),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  prefixIcon: const Icon(Icons.cloud_outlined),
                ),
              ),
              const SizedBox(height: 16),
              if (_errorMessage != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.redAccent.withOpacity(0.4)),
                  ),
                  child: Text(_errorMessage!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
                ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                icon: const Icon(Icons.login, color: Colors.white),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _loading ? null : () => _loginGoogle('operador@peaje.com'),
                label: Text(_loading ? 'Conectando...' : 'Iniciar como Operador'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                icon: const Icon(Icons.admin_panel_settings_outlined),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _loading ? null : () => _loginGoogle('docente@peaje.edu'),
                label: const Text('Iniciar como Docente (Admin)'),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: _loading ? null : () => _loginGoogle('denegado@gmail.com'),
                child: const Text('Probar cuenta no autorizada (Rechazo)', style: TextStyle(color: Colors.white38, fontSize: 12)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// -------------------------------------------------------------
// PANTALLA PRINCIPAL: MODO CASETA & MODO CONSULTA
// -------------------------------------------------------------
class MainHomeScreen extends StatefulWidget {
  final Map<String, dynamic> user;
  final String token;
  final VoidCallback onLogout;

  const MainHomeScreen({
    super.key,
    required this.user,
    required this.token,
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
      ModoCasetaScreen(token: widget.token),
      ModoConsultaScreen(token: widget.token),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(_currentIndex == 0 ? 'Modo Caseta' : 'Modo Consulta'),
        backgroundColor: const Color(0xFF1E293B),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar Sesión',
            onPressed: widget.onLogout,
          ),
        ],
      ),
      body: screens[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (idx) => setState(() => _currentIndex = idx),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.videocam_outlined),
            selectedIcon: Icon(Icons.videocam),
            label: 'Modo Caseta',
          ),
          NavigationDestination(
            icon: Icon(Icons.search_rounded),
            selectedIcon: Icon(Icons.search),
            label: 'Modo Consulta',
          ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------
// 4.1 MODO CASETA: CAPTURA VIDEO/FRAMES -> INFERENCIA -> RESULTADO
// -------------------------------------------------------------
class ModoCasetaScreen extends StatefulWidget {
  final String token;
  const ModoCasetaScreen({super.key, required this.token});

  @override
  State<ModoCasetaScreen> createState() => _ModoCasetaScreenState();
}

class _ModoCasetaScreenState extends State<ModoCasetaScreen> {
  final ImagePicker _picker = ImagePicker();
  Uint8List? _capturedImageBytes;
  bool _processing = false;
  Map<String, dynamic>? _lastResult;
  String _apiBaseUrl = 'http://10.0.2.2:8000/api/v1';

  Future<void> _capturarFrame(ImageSource source) async {
    final XFile? photo = await _picker.pickImage(source: source, maxWidth: 800, imageQuality: 85);
    if (photo == null) return;

    final bytes = await photo.readAsBytes();
    setState(() {
      _capturedImageBytes = bytes;
      _processing = true;
      _lastResult = null;
    });

    try {
      final base64Image = 'data:image/jpeg;base64,${base64Encode(bytes)}';
      final response = await http.post(
        Uri.parse('$_apiBaseUrl/pasos/frame'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer ${widget.token}',
        },
        body: jsonEncode({
          'frame_base64': base64Image,
          'caseta_id': 1,
        }),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 201 && data['success'] == true) {
        setState(() {
          _lastResult = data;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al enviar frame: $e')),
      );
    } finally {
      setState(() {
        _processing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Visor de Cámara / Frame Capturado
          Container(
            height: 240,
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white12),
            ),
            child: _capturedImageBytes != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.memory(_capturedImageBytes!, fit: BoxFit.cover),
                  )
                : const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.camera_alt_outlined, size: 50, color: Colors.white38),
                      SizedBox(height: 8),
                      Text('Captura un vehículo en caseta', style: TextStyle(color: Colors.white54)),
                    ],
                  ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.camera),
                  onPressed: _processing ? null : () => _capturarFrame(ImageSource.camera),
                  label: const Text('Cámara'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.photo_library),
                  onPressed: _processing ? null : () => _capturarFrame(ImageSource.gallery),
                  label: const Text('Galería'),
                ),
              ),
            ],
          ),
          if (_processing) ...[
            const SizedBox(height: 20),
            const Center(child: CircularProgressIndicator()),
            const SizedBox(height: 8),
            const Center(child: Text('Procesando en M1 + M2 + M3...', style: TextStyle(color: Colors.white54))),
          ],
          if (_lastResult != null) ...[
            const SizedBox(height: 20),
            _buildResultCard(_lastResult!['paso']),
          ],
        ],
      ),
    );
  }

  Widget _buildResultCard(Map<String, dynamic> paso) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blueAccent.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.between,
            children: [
              Text(
                paso['placa_normalizada'] ?? 'DESCONOCIDA',
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white, fontFamily: 'monospace'),
              ),
              Chip(
                label: Text(paso['estado'] ?? '', style: const TextStyle(fontSize: 11)),
                backgroundColor: paso['estado'] == 'Registrada y con paso'
                    ? Colors.green.withOpacity(0.2)
                    : Colors.red.withOpacity(0.2),
              ),
            ],
          ),
          const Divider(height: 24),
          Text('• Categoría: ${paso['categoria_detectada']}', style: const TextStyle(fontSize: 15)),
          Text('• Ejes detectados: ${paso['ejes_detectados']}', style: const TextStyle(fontSize: 15)),
          Text('• Tarifa cobrada: Bs. ${paso['monto']}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.greenAccent)),
          Text('• Pasajeros: ${paso['pasajeros']}', style: const TextStyle(fontSize: 14, color: Colors.white60)),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------
// 4.1 MODO CONSULTA: FOTO O TEXTO -> AGENTE CONVERSACIONAL
// -------------------------------------------------------------
class ModoConsultaScreen extends StatefulWidget {
  final String token;
  const ModoConsultaScreen({super.key, required this.token});

  @override
  State<ModoConsultaScreen> createState() => _ModoConsultaScreenState();
}

class _ModoConsultaScreenState extends State<ModoConsultaScreen> {
  final TextEditingController _textController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  String _apiBaseUrl = 'http://10.0.2.2:8000/api/v1';
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
        Uri.parse('$_apiBaseUrl/agente/chat'),
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
        _agentResponse = 'Error consultando agente: $e';
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
                  decoration: InputDecoration(
                    hintText: 'Consultar placa (ej. 4021XYZ)',
                    filled: true,
                    fillColor: const Color(0xFF1E293B),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                icon: const Icon(Icons.send),
                onPressed: _loading ? null : () => _consultar(texto: _textController.text),
              ),
              IconButton.outlined(
                icon: const Icon(Icons.camera_alt),
                tooltip: 'Foto de Placa',
                onPressed: _loading ? null : _subirFotoPlaca,
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (_loading) const Center(child: CircularProgressIndicator()),
          if (_agentResponse != null)
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white12),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    _agentResponse!,
                    style: const TextStyle(fontSize: 15, height: 1.5, color: Colors.white),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
