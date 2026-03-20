import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const ThemeManager();
  }
}

class ThemeManager extends StatefulWidget {
  const ThemeManager({super.key});

  @override
  State<ThemeManager> createState() => _ThemeManagerState();
}

class _ThemeManagerState extends State<ThemeManager> {
  static const Color azulMarinoXsim = Color(0xFF00162A);
  ThemeMode _themeMode = ThemeMode.dark;

  void _toggleTheme() {
    setState(() {
      _themeMode = _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'XSIM',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorSchemeSeed: azulMarinoXsim,
        scaffoldBackgroundColor: Colors.white,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: azulMarinoXsim,
        scaffoldBackgroundColor: azulMarinoXsim,
        appBarTheme: const AppBarTheme(backgroundColor: azulMarinoXsim),
      ),
      themeMode: _themeMode,
      home: AuthWrapper(onThemeToggle: _toggleTheme),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  final VoidCallback onThemeToggle;
  const AuthWrapper({super.key, required this.onThemeToggle});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasData) {
          return MainNavigation(onThemeToggle: onThemeToggle);
        }
        return const LoginScreen();
      },
    );
  }
}

class MainNavigation extends StatefulWidget {
  final VoidCallback onThemeToggle;
  const MainNavigation({super.key, required this.onThemeToggle});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  final PageController _pageController = PageController();
  int _currentIndex = 0;
  String? _localidadId;
  String? _userName;

  @override
  void initState() {
    super.initState();
    _fetchUserData();
  }

  Future<void> _fetchUserData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final doc = await FirebaseFirestore.instance.collection('usuarios').doc(user.uid).get();
        if (doc.exists) {
          if (!mounted) return;
          setState(() {
            _localidadId = doc.data()?['localidad_id'] ?? "S/L";
            _userName = doc.data()?['nombre'] ?? "Inspector";
          });
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_localidadId == null || _userName == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          InfraccionForm(
            localidadId: _localidadId!,
            userName: _userName!,
            onThemeToggle: widget.onThemeToggle,
          ),
          HistorialScreen(localidadId: _localidadId!),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() => _currentIndex = index);
          _pageController.jumpToPage(index);
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.edit_document), label: 'Formulario'),
          NavigationDestination(icon: Icon(Icons.history), label: 'Historial'),
        ],
      ),
    );
  }
}

class HistorialScreen extends StatelessWidget {
  final String localidadId;
  const HistorialScreen({super.key, required this.localidadId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Historial'),
        centerTitle: true,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('infracciones')
            .where('localidad_id', isEqualTo: localidadId)
            .orderBy('fecha', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (snapshot.data!.docs.isEmpty) return const Center(child: Text('No hay multas registradas'));

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: snapshot.data!.docs.length,
            itemBuilder: (context, index) {
              var doc = snapshot.data!.docs[index];
              var data = doc.data() as Map<String, dynamic>;
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.receipt_long)),
                  title: Text('Patente: ${data['patente'] ?? 'S/P'}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('Fecha: ${data['fecha'] != null ? (data['fecha'] as Timestamp).toDate().toString().substring(0, 16) : 'S/F'}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showDetalle(context, data),
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _showDetalle(BuildContext context, Map<String, dynamic> data) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF00162A) : Colors.white,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Detalle del Registro', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const Divider(height: 32, color: Colors.white24),
              _detalleItem('ID Infracción', data['infraccion_id'], isDark),
              _detalleItem('Patente', data['patente'], isDark),
              _detalleItem('Marca', data['marca'], isDark),
              _detalleItem('Modelo', data['modelo'], isDark),
              _detalleItem('Infracción', data['tipo_infraccion'], isDark),
              _detalleItem('Calle / Ruta', data['ubicacion']?['calle_ruta'], isDark),
              _detalleItem('Nro / KM', data['ubicacion']?['numero_km'], isDark),
              _detalleItem('Coordenadas GPS', data['ubicacion']?['gps'], isDark),
              _detalleItem('Registrado por', data['registrado_por'], isDark),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detalleItem(String label, dynamic value, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: isDark ? Colors.white54 : Colors.black54, fontSize: 12)),
          Text(value?.toString() ?? 'N/A', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscureText = true;

  Future<void> _login() async {
    setState(() => _isLoading = true);
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${e.message}')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const Color fondoOscuro = Color(0xFF00162A);

    return Theme(
      data: ThemeData.dark().copyWith(scaffoldBackgroundColor: fondoOscuro),
      child: Scaffold(
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Image.asset('assets/icon/app_icon.png', height: 160, errorBuilder: (c, e, s) => const Icon(Icons.lock_person, size: 80, color: Colors.white)),
                const SizedBox(height: 24),
                const Text('XSIM', textAlign: TextAlign.center, style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 40),
                _buildLoginField(_emailController, 'Correo Electrónico', Icons.email_outlined),
                const SizedBox(height: 16),
                _buildLoginField(
                  _passwordController,
                  'Contraseña',
                  Icons.lock_outline,
                  isPassword: true,
                  onToggleVisibility: () => setState(() => _obscureText = !_obscureText),
                  obscureText: _obscureText,
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: _isLoading ? null : _login,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: fondoOscuro,
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                  ),
                  child: _isLoading ? const CircularProgressIndicator(color: fondoOscuro) : const Text('INGRESAR'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoginField(
      TextEditingController controller,
      String label,
      IconData icon,
      {bool isPassword = false, VoidCallback? onToggleVisibility, bool obscureText = false}
      ) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1), // Corregido: withValues
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextField(
        controller: controller,
        obscureText: isPassword ? obscureText : false,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
            labelText: label,
            labelStyle: const TextStyle(color: Colors.white70),
            prefixIcon: Icon(icon, color: Colors.white70),
            suffixIcon: isPassword
                ? IconButton(
              icon: Icon(obscureText ? Icons.visibility_off : Icons.visibility, color: Colors.white70),
              onPressed: onToggleVisibility,
            )
                : null,
            border: InputBorder.none,
            contentPadding: const EdgeInsets.all(16)
        ),
      ),
    );
  }
}

class InfraccionForm extends StatefulWidget {
  final String localidadId;
  final String userName;
  final VoidCallback onThemeToggle;
  const InfraccionForm({super.key, required this.localidadId, required this.userName, required this.onThemeToggle});

  @override
  State<InfraccionForm> createState() => _InfraccionFormState();
}

class _InfraccionFormState extends State<InfraccionForm> {
  final _formKey = GlobalKey<FormState>();
  final _patenteController = TextEditingController();
  final _marcaController = TextEditingController();
  final _modeloController = TextEditingController();
  final _calleController = TextEditingController();
  final _numeroController = TextEditingController();
  final _tipoInfraccionController = TextEditingController();
  final _observacionesController = TextEditingController();

  XFile? _imagenPatente;
  XFile? _imagenEntorno;
  String _ubicacionGps = "No obtenida";
  String? _precisionGps;
  bool _subiendo = false;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    Geolocator.requestPermission();
  }

  Future<void> _logout() async => await FirebaseAuth.instance.signOut();

  Future<void> _obtenerUbicacion() async {
    try {
      Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      if (!mounted) return;
      setState(() {
        _ubicacionGps = "${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}";
        _precisionGps = "${position.accuracy.toStringAsFixed(1)}m";
      });
    } catch (_) {
      if (mounted) setState(() => _ubicacionGps = "Error GPS");
    }
  }

  Future<void> _pickImage(bool isPatente) async {
    final XFile? image = await _picker.pickImage(source: ImageSource.camera, imageQuality: 70);
    if (image != null) {
      if (!mounted) return;
      setState(() => isPatente ? _imagenPatente = image : _imagenEntorno = image);
      _obtenerUbicacion();
    }
  }

  Future<void> _registrarInfraccion() async {
    if (!_formKey.currentState!.validate() || _imagenPatente == null || _imagenEntorno == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Faltan datos o fotos')));
      return;
    }
    setState(() => _subiendo = true);
    try {
      final now = DateTime.now();
      final dayFolder = DateFormat('yyyy-MM-dd').format(now);
      final id = FirebaseFirestore.instance.collection('infracciones').doc().id;
      final path = "infracciones/${widget.localidadId}/$dayFolder/$id";

      final refP = FirebaseStorage.instance.ref().child("$path/patente.jpg");
      await refP.putFile(File(_imagenPatente!.path));
      final urlP = await refP.getDownloadURL();

      final refE = FirebaseStorage.instance.ref().child("$path/entorno.jpg");
      await refE.putFile(File(_imagenEntorno!.path));
      final urlE = await refE.getDownloadURL();

      final Map<String, dynamic> datos = {
        'infraccion_id': id,
        'localidad_id': widget.localidadId,
        'patente': _patenteController.text.toUpperCase(),
        'marca': _marcaController.text.toUpperCase(),
        'modelo': _modeloController.text.toUpperCase(),
        'ubicacion': {
          'calle_ruta': _calleController.text.toUpperCase(),
          'numero_km': _numeroController.text.toUpperCase(),
          'gps': _ubicacionGps,
          'precision': _precisionGps
        },
        'tipo_infraccion': _tipoInfraccionController.text.toUpperCase(),
        'observaciones': _observacionesController.text.toUpperCase(),
        'fecha_hora': now.toIso8601String(),
        'registrado_por': widget.userName,
      };

      String txt = const JsonEncoder.withIndent('  ').convert(datos);
      final refTxt = FirebaseStorage.instance.ref().child("$path/datos.txt");
      await refTxt.putString(txt, format: PutStringFormat.raw, metadata: SettableMetadata(contentType: 'text/plain'));

      await FirebaseFirestore.instance.collection('infracciones').doc(id).set({
        ...datos,
        'foto_patente_url': urlP,
        'foto_entorno_url': urlE,
        'txt_url': await refTxt.getDownloadURL(),
        'fecha': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Registro exitoso')));
      _formKey.currentState!.reset();
      setState(() { _imagenPatente = null; _imagenEntorno = null; _ubicacionGps = "No obtenida"; });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _subiendo = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          children: [
            Text(widget.localidadId, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w300)),
            Text(widget.userName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        centerTitle: true,
        leading: IconButton(
          icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode),
          onPressed: widget.onThemeToggle,
        ),
        actions: [IconButton(onPressed: _logout, icon: const Icon(Icons.logout))],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(children: [
            _buildField(_patenteController, 'Patente', Icons.directions_car),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: _buildField(_marcaController, 'Marca', null)),
              const SizedBox(width: 16),
              Expanded(child: _buildField(_modeloController, 'Modelo', null)),
            ]),
            const SizedBox(height: 24),
            _buildField(_calleController, 'Calle/Ruta', Icons.map),
            const SizedBox(height: 16),
            _buildField(_numeroController, 'Nro/Km', null, type: TextInputType.number),
            const SizedBox(height: 24),
            Row(children: [
              Expanded(child: _buildImageCard('Foto Patente', _imagenPatente, () => _pickImage(true))),
              const SizedBox(width: 16),
              Expanded(child: _buildImageCard('Foto Entorno', _imagenEntorno, () => _pickImage(false))),
            ]),
            const SizedBox(height: 24),
            _buildField(_tipoInfraccionController, 'Tipo de Infracción', Icons.report_problem),
            const SizedBox(height: 16),
            _buildField(_observacionesController, 'Observaciones', Icons.notes, maxLines: 3),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _subiendo ? null : _registrarInfraccion,
              style: ElevatedButton.styleFrom(
                  backgroundColor: isDark ? Colors.white : const Color(0xFF00162A),
                  foregroundColor: isDark ? const Color(0xFF00162A) : Colors.white,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: _subiendo ? const CircularProgressIndicator() : const Text('REGISTRAR INFRACCIÓN'),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildField(TextEditingController controller, String label, IconData? icon, {TextInputType type = TextInputType.text, int maxLines = 1}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TextFormField(
      controller: controller,
      keyboardType: type,
      maxLines: maxLines,
      inputFormatters: [UpperCaseTextFormatter()],
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white, // Corregido: withValues
        prefixIcon: icon != null ? Icon(icon) : null,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: isDark ? Colors.white24 : Colors.grey[300]!)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: isDark ? Colors.white24 : Colors.grey[300]!)),
      ),
      validator: (v) => v!.isEmpty ? 'Requerido' : null,
    );
  }

  Widget _buildImageCard(String label, XFile? image, VoidCallback onTap) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(children: [
      Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
      const SizedBox(height: 8),
      InkWell(
        onTap: onTap,
        child: Container(
          height: 130,
          width: double.infinity,
          decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white, // Corregido: withValues
              border: Border.all(color: isDark ? Colors.white24 : Colors.grey[300]!),
              borderRadius: BorderRadius.circular(12)
          ),
          child: image == null
              ? const Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.add_a_photo, size: 32), SizedBox(height: 8), Text('Capturar', style: TextStyle(fontSize: 12))])
              : ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.file(File(image.path), fit: BoxFit.cover)),
        ),
      ),
    ]);
  }
}

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    return TextEditingValue(text: newValue.text.toUpperCase(), selection: newValue.selection);
  }
}