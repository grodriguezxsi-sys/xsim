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
import 'package:blue_thermal_printer/blue_thermal_printer.dart'; // IMPORTANTE

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
      title: 'XSIM - Registro de Infracciones',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorSchemeSeed: azulMarinoXsim,
        scaffoldBackgroundColor: Colors.grey[100],
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: azulMarinoXsim,
        scaffoldBackgroundColor: azulMarinoXsim,
        appBarTheme: const AppBarTheme(
          backgroundColor: azulMarinoXsim,
          surfaceTintColor: Colors.transparent,
        ),
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
        return LoginScreen(onThemeToggle: onThemeToggle);
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
  bool _errorCargandoPerfil = false;

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
        if (doc.exists && doc.data()?['localidad_id'] != null) {
          setState(() {
            _localidadId = doc.data()?['localidad_id'];
            _userName = doc.data()?['nombre'] ?? "Inspector";
            _errorCargandoPerfil = false;
          });
        } else {
          setState(() => _errorCargandoPerfil = true);
        }
      }
    } catch (e) {
      setState(() => _errorCargandoPerfil = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_errorCargandoPerfil) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error, color: Colors.red, size: 60),
              const Text('Perfil no configurado en Firestore'),
              const SizedBox(height: 20),
              ElevatedButton(onPressed: () => FirebaseAuth.instance.signOut(), child: const Text('Cerrar Sesión'))
            ],
          ),
        ),
      );
    }

    if (_localidadId == null || _userName == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));

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
          HistorialScreen(
            localidadId: _localidadId!,
          ),
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

class HistorialScreen extends StatefulWidget {
  final String localidadId;
  const HistorialScreen({super.key, required this.localidadId});

  @override
  State<HistorialScreen> createState() => _HistorialScreenState();
}

class _HistorialScreenState extends State<HistorialScreen> {
  BlueThermalPrinter bluetooth = BlueThermalPrinter.instance;
  List<BluetoothDevice> _devices = [];
  BluetoothDevice? _selectedDevice;

  @override
  void initState() {
    super.initState();
    _initBluetooth();
  }

  void _initBluetooth() async {
    try {
      _devices = await bluetooth.getBondedDevices();
      setState(() {});
    } catch (e) {
      debugPrint("Error init bluetooth: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Historial'),
        centerTitle: true,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('infracciones')
            .where('localidad_id', isEqualTo: widget.localidadId)
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
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: isDark ? Colors.white10 : Colors.grey[300]!),
                ),
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.receipt_long)),
                  title: Text('Patente: ${data['patente'] ?? 'S/P'}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('Fecha: ${data['fecha'] != null ? DateFormat('dd/MM/yyyy HH:mm').format((data['fecha'] as Timestamp).toDate()) : 'S/F'}'),
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
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.8,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Detalle del Registro', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  IconButton.filledTonal(
                    onPressed: () => _showPrinterPicker(context, data),
                    icon: const Icon(Icons.print),
                  ),
                ],
              ),
              const Divider(height: 32, color: Colors.white24),
              _detalleItem('ID Infracción', data['infraccion_id'], isDark),
              _detalleItem('Patente', data['patente'], isDark),
              _detalleItem('Marca', data['marca'], isDark),
              _detalleItem('Modelo', data['modelo'], isDark),
              _detalleItem('Calle / Ruta', data['ubicacion']?['calle_ruta'], isDark),
              _detalleItem('Nro / KM', data['ubicacion']?['numero_km'], isDark),
              _detalleItem('Infracción', data['tipo_infraccion'], isDark),
              _detalleItem('Coordenadas GPS', data['ubicacion']?['gps'], isDark),
              _detalleItem('Observaciones', data['observaciones'], isDark),
              _detalleItem('Registrado por', data['registrado_por'], isDark),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  // Selector de impresora antes de imprimir
  void _showPrinterPicker(BuildContext context, Map<String, dynamic> data) async {
    _devices = await bluetooth.getBondedDevices();
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Seleccionar Impresora'),
        content: SizedBox(
          width: double.maxFinite,
          child: _devices.isEmpty
              ? const Text("No hay impresoras vinculadas.")
              : ListView.builder(
            shrinkWrap: true,
            itemCount: _devices.length,
            itemBuilder: (context, i) => ListTile(
              title: Text(_devices[i].name ?? "Unknown"),
              subtitle: Text(_devices[i].address ?? ""),
              onTap: () {
                Navigator.pop(context);
                _imprimirTicketReal(_devices[i], data);
              },
            ),
          ),
        ),
      ),
    );
  }

  void _imprimirTicketReal(BluetoothDevice device, Map<String, dynamic> data) async {
    bool? isConnected = await bluetooth.isConnected;
    if (!isConnected!) {
      await bluetooth.connect(device);
    }

    String fechaStr = data['fecha'] != null
        ? DateFormat('dd/MM/yyyy HH:mm').format((data['fecha'] as Timestamp).toDate())
        : "S/F";

    // FORMATO PARA 56mm (ESC/POS)
    bluetooth.printCustom("CECAITRA - XSIM", 3, 1); // Texto, tamaño, alineación (1=center)
    bluetooth.printNewLine();
    bluetooth.printCustom("REIMPRESION DE TICKET", 1, 1);
    bluetooth.printCustom("ID: ${data['infraccion_id']}", 0, 1);
    bluetooth.printCustom("Fecha: $fechaStr", 0, 1);
    bluetooth.printCustom("--------------------------------", 1, 1);

    bluetooth.printLeftRight("PATENTE:", "${data['patente']}", 1);
    bluetooth.printLeftRight("MARCA:", "${data['marca']}", 1);
    bluetooth.printLeftRight("MODELO:", "${data['modelo']}", 1);
    bluetooth.printNewLine();

    bluetooth.printCustom("UBICACION:", 1, 0);
    bluetooth.printCustom("${data['ubicacion']?['calle_ruta']} ${data['ubicacion']?['numero_km']}", 0, 0);
    bluetooth.printCustom("GPS: ${data['ubicacion']?['gps']}", 0, 0);
    bluetooth.printNewLine();

    bluetooth.printCustom("INFRACCION:", 1, 0);
    bluetooth.printCustom("${data['tipo_infraccion']}", 0, 0);
    bluetooth.printNewLine();

    bluetooth.printCustom("INSPECTOR:", 1, 0);
    bluetooth.printCustom("${data['registrado_por']}", 0, 0);

    bluetooth.printCustom("--------------------------------", 1, 1);
    bluetooth.printCustom("COMPROBANTE NO FISCAL", 0, 1);
    bluetooth.printNewLine();
    bluetooth.printNewLine();
    bluetooth.paperCut();
  }

  Widget _detalleItem(String label, dynamic value, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: isDark ? Colors.white54 : Colors.black54, fontSize: 12)),
          const SizedBox(height: 2),
          Text(value?.toString() ?? 'N/A', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

// RESTO DEL CODIGO (LoginScreen e InfraccionForm)
class LoginScreen extends StatefulWidget {
  final VoidCallback onThemeToggle;
  const LoginScreen({super.key, required this.onThemeToggle});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  Future<void> _login() async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) return;
    setState(() => _isLoading = true);
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
    } on FirebaseAuthException catch (e) {
      String msg = 'Error al iniciar sesión';
      if (e.code == 'user-not-found') msg = 'Usuario no encontrado';
      else if (e.code == 'wrong-password') msg = 'Contraseña incorrecta';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const Color azulMarinoXsim = Color(0xFF00162A);
    return Scaffold(
      backgroundColor: azulMarinoXsim,
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
              _buildPasswordField(),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: _isLoading ? null : _login,
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: azulMarinoXsim,
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                ),
                child: _isLoading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('INGRESAR', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoginField(TextEditingController controller, String label, IconData icon) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextField(
        controller: controller,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
            labelText: label,
            labelStyle: const TextStyle(color: Colors.white70),
            prefixIcon: Icon(icon, color: Colors.white70),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.all(16)
        ),
      ),
    );
  }

  Widget _buildPasswordField() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextField(
        controller: _passwordController,
        obscureText: _obscurePassword,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
            labelText: 'Contraseña',
            labelStyle: const TextStyle(color: Colors.white70),
            prefixIcon: const Icon(Icons.password_outlined, color: Colors.white70),
            suffixIcon: IconButton(
              icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility, color: Colors.white70),
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
            ),
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
  bool _obteniendoGps = false;
  bool _subiendo = false;
  String _estadoCarga = "";
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _requestInitialPermissions();
  }

  Future<void> _requestInitialPermissions() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      await Geolocator.requestPermission();
    }
  }

  Future<void> _logout() async => await FirebaseAuth.instance.signOut();

  Future<void> _obtenerGpsReal() async {
    setState(() { _obteniendoGps = true; _precisionGps = null; });
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) throw 'GPS desactivado';
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 35),
      );
      if (mounted) {
        setState(() {
          _ubicacionGps = "${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}";
          _precisionGps = "${position.accuracy.toStringAsFixed(1)}m";
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _ubicacionGps = "Error: Ubicación no fijada");
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Timeout GPS. Reintente sacando la foto.')));
      }
    } finally {
      if (mounted) setState(() => _obteniendoGps = false);
    }
  }

  Future<void> _pickPatenteAndSetGps() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.camera, imageQuality: 70);
    if (image != null) {
      setState(() => _imagenPatente = image);
      _obtenerGpsReal();
    }
  }

  Future<void> _pickEntorno() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.camera, imageQuality: 70);
    if (image != null) setState(() => _imagenEntorno = image);
  }

  Future<void> _registrarInfraccion() async {
    if (!_formKey.currentState!.validate() || _imagenPatente == null || _imagenEntorno == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Faltan datos o fotos')));
      return;
    }
    if (_precisionGps == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Esperando GPS real...')));
      return;
    }
    setState(() { _subiendo = true; _estadoCarga = "Iniciando subida..."; });
    try {
      final now = DateTime.now();
      final dayFolder = DateFormat('yyyy-MM-dd').format(now);
      final fileTimestamp = DateFormat('yyyyMMdd_HHmmss').format(now);
      final infraccionRef = FirebaseFirestore.instance.collection('infracciones').doc();
      final id = infraccionRef.id;
      final basePath = "infracciones/${widget.localidadId}/$dayFolder";

      final refP = FirebaseStorage.instance.ref().child("$basePath/${fileTimestamp}_patente_$id.jpg");
      await refP.putFile(File(_imagenPatente!.path));
      final urlP = await refP.getDownloadURL();

      final refE = FirebaseStorage.instance.ref().child("$basePath/${fileTimestamp}_entorno_$id.jpg");
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

      String txtContent = const JsonEncoder.withIndent('  ').convert(datos);
      final refTxt = FirebaseStorage.instance.ref().child("$basePath/${fileTimestamp}_dato_$id.txt");
      await refTxt.putString(txtContent, format: PutStringFormat.raw, metadata: SettableMetadata(contentType: 'text/plain'));
      final urlTxt = await refTxt.getDownloadURL();

      await infraccionRef.set({
        ...datos,
        'foto_patente_url': urlP,
        'foto_entorno_url': urlE,
        'txt_url': urlTxt,
        'fecha': FieldValue.serverTimestamp(),
      });

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Registro exitoso')));
      _formKey.currentState!.reset();
      _patenteController.clear(); _marcaController.clear(); _modeloController.clear();
      _calleController.clear(); _numeroController.clear(); _tipoInfraccionController.clear();
      _observacionesController.clear();
      setState(() { _imagenPatente = null; _imagenEntorno = null; _ubicacionGps = "No obtenida"; _precisionGps = null; });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _subiendo = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const Color azulMarinoXsim = Color(0xFF00162A);

    return Scaffold(
      appBar: AppBar(
        title: Column(children: [
          Text(widget.localidadId, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w300)),
          Text(widget.userName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ]),
        centerTitle: true,
        leading: IconButton(icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode), onPressed: widget.onThemeToggle),
        actions: [IconButton(onPressed: _logout, icon: const Icon(Icons.logout))],
      ),
      body: Stack(children: [
        SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(key: _formKey, child: Column(children: [
            _buildField(_patenteController, 'Patente', Icons.directions_car),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: _buildField(_marcaController, 'Marca', null)),
              const SizedBox(width: 16),
              Expanded(child: _buildField(_modeloController, 'Modelo', null)),
            ]),
            const SizedBox(height: 24),
            _buildField(_calleController, 'Calle / Ruta', Icons.map),
            const SizedBox(height: 16),
            _buildField(_numeroController, 'Nro / Km', null, type: TextInputType.number),
            const SizedBox(height: 24),
            _buildField(_tipoInfraccionController, 'Tipo de Infracción', Icons.report_problem),
            const SizedBox(height: 16),
            _buildField(_observacionesController, 'Observaciones', Icons.notes, maxLines: 3),
            const SizedBox(height: 24),
            Row(children: [
              Expanded(child: _buildImageCard('Foto Patente', _imagenPatente, _pickPatenteAndSetGps)),
              const SizedBox(width: 16),
              Expanded(child: _buildImageCard('Foto Entorno', _imagenEntorno, _pickEntorno)),
            ]),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: (_subiendo || _obteniendoGps) ? null : _registrarInfraccion,
              style: ElevatedButton.styleFrom(
                  backgroundColor: isDark ? Colors.white : azulMarinoXsim,
                  foregroundColor: isDark ? azulMarinoXsim : Colors.white,
                  minimumSize: const Size(double.infinity, 56),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
              ),
              child: (_subiendo || _obteniendoGps)
                  ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('REGISTRAR INFRACCIÓN', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 20),
          ])),
        ),
        if (_subiendo) Container(color: Colors.black87, child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          const CircularProgressIndicator(color: Colors.white),
          const SizedBox(height: 20),
          Text(_estadoCarga, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        ]))),
      ]),
    );
  }

  Widget _buildField(TextEditingController controller, String label, IconData? icon, {TextInputType type = TextInputType.text, int maxLines = 1}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TextFormField(
      controller: controller,
      keyboardType: type,
      maxLines: maxLines,
      textCapitalization: TextCapitalization.characters,
      inputFormatters: [UpperCaseTextFormatter()],
      style: TextStyle(color: isDark ? Colors.white : Colors.black),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: isDark ? Colors.white70 : Colors.black54),
        filled: true,
        fillColor: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
        prefixIcon: icon != null ? Icon(icon, color: isDark ? Colors.white70 : Colors.black54) : null,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: isDark ? Colors.white24 : Colors.grey[300]!)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: isDark ? Colors.white24 : Colors.grey[300]!)),
      ),
      validator: (v) => v!.isEmpty ? 'Requerido' : null,
    );
  }

  Widget _buildImageCard(String label, XFile? image, VoidCallback onTap) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(children: [
      Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
      const SizedBox(height: 8),
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 120,
          width: double.infinity,
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
            border: Border.all(color: isDark ? Colors.white24 : Colors.black26, width: 1.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: image == null
              ? Icon(Icons.add_a_photo, color: isDark ? Colors.white54 : Colors.black54)
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

