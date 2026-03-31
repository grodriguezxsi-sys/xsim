import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../services/connectivity_service.dart';

class InfraccionForm extends StatefulWidget {
  final String localidadId;
  final String userName;
  final VoidCallback onThemeToggle;
  const InfraccionForm({super.key, required this.localidadId, required this.userName, required this.onThemeToggle});

  @override
  State<InfraccionForm> createState() => _InfraccionFormState();
}

class _InfraccionFormState extends State<InfraccionForm> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  static const Color naranjaXsim = Color(0xFFFF8C00);

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
  bool _subiendo = false;
  String _estadoSubida = "";
  final ImagePicker _picker = ImagePicker();
  
  late final AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat(reverse: true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Geolocator.requestPermission();
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    _patenteController.dispose();
    _marcaController.dispose();
    _modeloController.dispose();
    _calleController.dispose();
    _numeroController.dispose();
    _tipoInfraccionController.dispose();
    _observacionesController.dispose();
    super.dispose();
  }

  Future<void> _logout() async => await FirebaseAuth.instance.signOut();

  Future<void> _obtenerUbicacion({bool actualizarDireccion = true}) async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      if (!mounted) return;
      setState(() => _ubicacionGps = "${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}");

      if (actualizarDireccion) {
        List<Placemark> placemarks = await placemarkFromCoordinates(position.latitude, position.longitude);
        if (placemarks.isNotEmpty) {
          Placemark place = placemarks[0];
          setState(() {
            _calleController.text = place.thoroughfare ?? "";
            _numeroController.text = place.subThoroughfare ?? "";
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _pickImage(bool isPatente) async {
    final XFile? image = await _picker.pickImage(source: ImageSource.camera, imageQuality: 70);
    if (image != null) {
      setState(() => isPatente ? _imagenPatente = image : _imagenEntorno = image);
      _obtenerUbicacion(actualizarDireccion: isPatente);
    }
  }

  Future<void> _registrarInfraccion() async {
    if (!_formKey.currentState!.validate() || _imagenPatente == null || _imagenEntorno == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Faltan fotos o datos')));
      return;
    }

    setState(() { _subiendo = true; _estadoSubida = "Asegurando registro local..."; });

    try {
      final now = DateTime.now();
      final idInfraccion = FirebaseFirestore.instance.collection('infracciones').doc().id;
      final dayFolder = DateFormat('dd-MM-yyyy').format(now);
      final timestamp = DateFormat('ddMMyyyyHHmmss').format(now);
      final patente = _patenteController.text.toUpperCase().replaceAll(' ', '');

      final String nameP = "${timestamp}_${idInfraccion}_foto_patente_$patente.jpg";
      final String nameE = "${timestamp}_${idInfraccion}_foto_entorno_$patente.jpg";
      final String nameD = "${timestamp}_${idInfraccion}_dato_$patente.txt";

      final directory = await getApplicationDocumentsDirectory();
      final localPath = Directory('${directory.path}/evidencia/$idInfraccion');
      if (!await localPath.exists()) await localPath.create(recursive: true);

      final File fileP = await File(_imagenPatente!.path).copy('${localPath.path}/$nameP');
      final File fileE = await File(_imagenEntorno!.path).copy('${localPath.path}/$nameE');

      final Map<String, dynamic> datosJson = {
        'id': idInfraccion,
        'localidad_id': widget.localidadId,
        'patente': patente,
        'marca': _marcaController.text.toUpperCase(),
        'modelo': _modeloController.text.toUpperCase(),
        'ubicacion': {'calle': _calleController.text.toUpperCase(), 'nro': _numeroController.text.toUpperCase(), 'gps': _ubicacionGps},
        'infraccion': _tipoInfraccionController.text.toUpperCase(),
        'observaciones': _observacionesController.text.toUpperCase(),
        'fecha_hora': now.toIso8601String(),
        'registrado_por': widget.userName,
      };
      
      final File fileD = File('${localPath.path}/$nameD');
      await fileD.writeAsString(const JsonEncoder.withIndent('  ').convert(datosJson));

      FirebaseFirestore.instance.collection('infracciones').doc(idInfraccion).set({
        ...datosJson,
        'fecha': FieldValue.serverTimestamp(),
        'fotos_subidas': false,
        'ruta_local_patente': fileP.path,
        'ruta_local_entorno': fileE.path,
        'ruta_local_dato': fileD.path,
        'nombre_archivo_patente': nameP,
        'nombre_archivo_entorno': nameE,
        'nombre_archivo_dato': nameD,
        'fecha_carpeta': dayFolder,
      });

      context.read<ConnectivityService>().notifyListeners();

      if (!mounted) return;
      _limpiarFormulario();
      setState(() { _subiendo = false; _estadoSubida = ""; });
      
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Acta guardada correctamente. Se sincronizará automáticamente.'), 
        backgroundColor: Colors.blue,
        duration: Duration(seconds: 3),
      ));
      
    } catch (e) {
      if (mounted) {
        setState(() { _subiendo = false; _estadoSubida = ""; });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al registrar: $e')));
      }
    }
  }

  void _limpiarFormulario() {
    _patenteController.clear();
    _marcaController.clear();
    _modeloController.clear();
    _calleController.clear();
    _numeroController.clear();
    _tipoInfraccionController.clear();
    _observacionesController.clear();
    setState(() { _imagenPatente = null; _imagenEntorno = null; _ubicacionGps = "No obtenida"; });
  }

  // --- UI WIDGETS ---

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: naranjaXsim)),
          const SizedBox(height: 4),
          Container(height: 1.5, width: 40, color: naranjaXsim),
        ],
      ),
    );
  }

  Widget _buildField(TextEditingController controller, String label, IconData icon, {TextInputType type = TextInputType.text, Widget? suffix}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TextFormField(
      controller: controller,
      keyboardType: type,
      inputFormatters: [UpperCaseTextFormatter()],
      enabled: !_subiendo,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: isDark ? Colors.white70 : Colors.black54),
        prefixIcon: Icon(icon, color: naranjaXsim),
        suffixIcon: suffix,
        filled: true,
        fillColor: isDark ? Colors.white.withOpacity(0.05) : Colors.grey[200],
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15), 
          borderSide: BorderSide(color: isDark ? Colors.white24 : Colors.grey[400]!)
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15), 
          borderSide: BorderSide(color: isDark ? Colors.white24 : Colors.grey[400]!)
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15), 
          borderSide: const BorderSide(color: naranjaXsim, width: 1.5)
        ),
      ),
      validator: (v) => v!.isEmpty ? 'Requerido' : null,
    );
  }

  Widget _buildAutocomplete(TextEditingController controller, String label, List<String> options, IconData icon) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Autocomplete<String>(
      optionsBuilder: (val) => val.text.isEmpty ? options : options.where((o) => o.contains(val.text.toUpperCase())),
      onSelected: (s) => controller.text = s,
      fieldViewBuilder: (ctx, ctrl, node, submit) {
        if (controller.text != ctrl.text) ctrl.text = controller.text;
        return TextFormField(
          controller: ctrl,
          focusNode: node,
          inputFormatters: [UpperCaseTextFormatter()],
          enabled: !_subiendo,
          decoration: InputDecoration(
            labelText: label,
            labelStyle: TextStyle(color: isDark ? Colors.white70 : Colors.black54),
            prefixIcon: Icon(icon, color: naranjaXsim),
            filled: true,
            fillColor: isDark ? Colors.white.withOpacity(0.05) : Colors.grey[200],
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15), 
              borderSide: BorderSide(color: isDark ? Colors.white24 : Colors.grey[400]!)
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15), 
              borderSide: BorderSide(color: isDark ? Colors.white24 : Colors.grey[400]!)
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15), 
              borderSide: const BorderSide(color: naranjaXsim, width: 1.5)
            ),
          ),
          onChanged: (v) => controller.text = v.toUpperCase(),
          validator: (v) => v!.isEmpty ? 'Requerido' : null,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.localidadId.toUpperCase(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: naranjaXsim)),
          Text(widget.userName.toUpperCase(), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: isDark ? Colors.white : Colors.black87)),
        ]),
        actions: [
          Consumer<ConnectivityService>(
            builder: (context, connectivityService, child) {
              if (connectivityService.hasInternet && connectivityService.hasPendingUploads) {
                return FadeTransition(
                  opacity: Tween(begin: 0.5, end: 1.0).animate(_animationController),
                  child: IconButton(
                    icon: const Icon(Icons.cloud_upload, color: Colors.blueAccent, size: 28),
                    onPressed: () => connectivityService.retryPendingUploads(),
                  ),
                );
              } else if (connectivityService.hasPendingUploads) {
                return IconButton(
                  icon: const Icon(Icons.cloud_off, color: Colors.orange, size: 28),
                  onPressed: () {},
                );
              }
              return const SizedBox.shrink();
            },
          ),
          IconButton(onPressed: _subiendo ? null : widget.onThemeToggle, icon: const Icon(Icons.brightness_4)), 
          IconButton(onPressed: _subiendo ? null : _logout, icon: const Icon(Icons.logout))
        ],
      ),
      body: Stack(children: [
        SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(key: _formKey, child: Column(children: [
            Row(children: [
              Expanded(child: _buildImageCard('Patente', _imagenPatente, () => _pickImage(true))),
              const SizedBox(width: 10),
              Expanded(child: _buildImageCard('Entorno', _imagenEntorno, () => _pickImage(false))),
            ]),
            _buildSectionTitle('Vehículo'),
            _buildField(_patenteController, 'Patente', Icons.directions_car),
            const SizedBox(height: 15),
            Row(children: [
              Expanded(child: _buildAutocomplete(_marcaController, 'Marca', ['TOYOTA', 'FORD', 'FIAT', 'VOLKSWAGEN', 'CHEVROLET', 'RENAULT', 'PEUGEOT'], Icons.factory)),
              const SizedBox(width: 10),
              Expanded(child: _buildField(_modeloController, 'Modelo', Icons.category)),
            ]),
            _buildSectionTitle('Ubicación'),
            _buildField(_calleController, 'Calle / Ruta', Icons.map, suffix: IconButton(icon: const Icon(Icons.my_location, color: naranjaXsim), onPressed: () => _obtenerUbicacion())),
            const SizedBox(height: 15),
            _buildField(_numeroController, 'Nro / Km', Icons.location_on, type: TextInputType.number),
            _buildSectionTitle('Infracción'),
            _buildAutocomplete(_tipoInfraccionController, 'Infracción', ['DOBLE FILA', 'OCHAVA', 'GARAJE', 'SENDA PEATONAL', 'VEREDA', 'LUGAR PROHIBIDO'], Icons.warning),
            const SizedBox(height: 15),
            _buildField(_observacionesController, 'Observaciones', Icons.edit_note),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: _subiendo ? null : _registrarInfraccion,
              style: ElevatedButton.styleFrom(
                backgroundColor: naranjaXsim,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 60),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                elevation: 5,
              ),
              child: const Text('REGISTRAR INFRACCIÓN', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            )
          ])),
        ),
        if (_subiendo) Container(color: Colors.black54, child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [const CircularProgressIndicator(color: naranjaXsim), const SizedBox(height: 20), Text(_estadoSubida, style: const TextStyle(color: Colors.white))]))),
      ]),
    );
  }

  Widget _buildImageCard(String label, XFile? image, VoidCallback onTap) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(children: [
      Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
      const SizedBox(height: 8),
      InkWell(
        onTap: _subiendo ? null : onTap,
        child: Container(
          height: 120,
          width: double.infinity,
          decoration: BoxDecoration(
            border: Border.all(color: isDark ? Colors.white24 : Colors.grey[400]!),
            borderRadius: BorderRadius.circular(15),
            color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey[100],
          ),
          child: image == null
              ? const Icon(Icons.add_a_photo, color: naranjaXsim, size: 35)
              : ClipRRect(borderRadius: BorderRadius.circular(15), child: Image.file(File(image.path), fit: BoxFit.cover)),
        ),
      ),
    ]);
  }

  Widget _buildImageButton(String label, XFile? image, VoidCallback onTap) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(children: [
      Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
      const SizedBox(height: 8),
      InkWell(
        onTap: _subiendo ? null : onTap, 
        child: Container(
          height: 120, 
          width: double.infinity, 
          decoration: BoxDecoration(
            border: Border.all(color: isDark ? Colors.white24 : Colors.grey[400]!), 
            borderRadius: BorderRadius.circular(15), 
            color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey[100]
          ), 
          child: image == null ? const Icon(Icons.add_a_photo, color: naranjaXsim, size: 35) : ClipRRect(borderRadius: BorderRadius.circular(15), child: Image.file(File(image.path), fit: BoxFit.cover))
        )
      ),
    ]);
  }
}

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue old, TextEditingValue newVal) => TextEditingValue(text: newVal.text.toUpperCase(), selection: newVal.selection);
}
