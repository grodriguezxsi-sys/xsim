import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:xsim/services/deteccion_service.dart';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';

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
  bool _patenteDetectadaExito = false;

  final ImagePicker _picker = ImagePicker();
  final DeteccionVehiculoService _deteccionService = DeteccionVehiculoService();

  final Map<String, List<String>> vehiculosSugeridos = {
    'TOYOTA': ['COROLLA', 'HILUX', 'ETIOS', 'YARIS', 'SW4'],
    'FORD': ['RANGER', 'FOCUS', 'FIESTA', 'KA', 'ECOSPORT'],
    'FIAT': ['CRONOS', 'TORO', 'MOBI', 'ARGO', 'STRADA', 'PULSE'],
    'VOLKSWAGEN': ['GOL', 'AMAROK', 'POLO', 'TAOS', 'NIVUS', 'VENTO'],
    'RENAULT': ['SANDERO', 'LOGAN', 'KANGOO', 'ALASKAN', 'DUSTER'],
    'CHEVROLET': ['ONIX', 'CRUZE', 'S10', 'TRACKER', 'JOY'],
    'PEUGEOT': ['208', '2008', '308', 'PARTNER'],
  };

  final List<String> infraccionesSugeridas = [
    'ESTACIONAMIENTO EN DOBLE FILA',
    'ESTACIONAMIENTO SOBRE SENDA PEATONAL',
    'ESTACIONAMIENTO EN OCHAVA',
    'ESTACIONAMIENTO FRENTE A GARAJE',
    'LUGAR PROHIBIDO',
    'OBSTRUCCION DE RAMPA',
    'SIN TICKET DE ESTACIONAMIENTO',
  ];

  @override
  void initState() {
    super.initState();
    _patenteController.addListener(() {
      if (_patenteController.text.isEmpty && _patenteDetectadaExito) {
        setState(() => _patenteDetectadaExito = false);
      }
    });
  }

  @override
  void dispose() {
    _deteccionService.dispose();
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
      if (actualizarDireccion) {
        setState(() { _ubicacionGps = "Obteniendo..."; _calleController.text = "Buscando..."; });
      }
      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 8)),
      );
      if (!mounted) return;
      setState(() => _ubicacionGps = "${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}");
      if (actualizarDireccion) {
        List<Placemark> placemarks = await placemarkFromCoordinates(position.latitude, position.longitude);
        if (placemarks.isNotEmpty && mounted) {
          Placemark place = placemarks[0];
          setState(() { _calleController.text = place.thoroughfare ?? ""; _numeroController.text = place.subThoroughfare ?? ""; });
        }
      }
    } catch (e) { if (mounted) setState(() => _ubicacionGps = "Manual"); }
  }

  Future<void> _pickImage(bool isPatente) async {
    final XFile? image = await _picker.pickImage(source: ImageSource.camera, imageQuality: 50);
    if (image != null) {
      if (isPatente) {
        setState(() { _imagenPatente = image; });
        _obtenerUbicacion(actualizarDireccion: true);
        _ejecutarDeteccionPro(image.path);
      } else {
        setState(() { _imagenEntorno = image; });
      }
    }
  }

  Future<void> _ejecutarDeteccionPro(String path) async {
    setState(() { _estadoSubida = "Procesando vehículo..."; });
    try {
      final resultados = await _deteccionService.procesarYDeteccionDual(path);
      if (!mounted) return;
      setState(() {
        if (resultados['patente'] != null) {
          _patenteController.text = resultados['patente']!;
          _patenteDetectadaExito = true;
        }
        _marcaController.text = resultados['marca'] ?? '';
        _modeloController.text = resultados['modelo'] ?? '';
      });
    } catch (e) { debugPrint("Error OCR: $e"); }
    finally { if (mounted) setState(() => _estadoSubida = ""); }
  }

  Future<void> _registrarInfraccion() async {
    if (!_formKey.currentState!.validate() || _imagenPatente == null || _imagenEntorno == null) {
      _mostrarSnackBar("Faltan fotos o datos", Colors.red);
      return;
    }
    setState(() { _subiendo = true; _estadoSubida = "Generando acta legal..."; });

    try {
      final DateTime now = DateTime.now();
      final String idInfraccion = FirebaseFirestore.instance.collection('infracciones').doc().id;
      final String patenteClean = _patenteController.text.toUpperCase().trim().replaceAll(' ', '');

      final String ts = DateFormat('ddMMyyyy_HHmmss').format(now);
      final String dayFolder = DateFormat('dd-MM-yyyy').format(now);

      final String nameTxt = "${ts}_dato_${idInfraccion}_$patenteClean.txt";
      final String nameEntorno = "${ts}_foto_entorno_${idInfraccion}_$patenteClean.jpg";
      final String namePatente = "${ts}_foto_patente_${idInfraccion}_$patenteClean.jpg";

      final directory = await getApplicationDocumentsDirectory();
      final String localPath = '${directory.path}/evidencia_xsim';
      await Directory(localPath).create(recursive: true);

      final Map<String, dynamic> datosJson = {
        'id_acta': idInfraccion,
        'localidad': widget.localidadId,
        'agente': widget.userName,
        'fecha_hora': ts,
        'patente': patenteClean,
        'marca': _marcaController.text.toUpperCase(),
        'modelo': _modeloController.text.toUpperCase(),
        'calle_ruta': _calleController.text.toUpperCase(),
        'numero_km': _numeroController.text.toUpperCase(),
        'infraccion': _tipoInfraccionController.text.toUpperCase(),
        'gps': _ubicacionGps,
        'observaciones': _observacionesController.text.toUpperCase(),
        'cantidad_fotos': 2,
      };

      final File fileTxt = File('$localPath/$nameTxt');
      await fileTxt.writeAsString(jsonEncode(datosJson));

      final File fileP = await File(_imagenPatente!.path).copy('$localPath/$namePatente');
      final File fileE = await File(_imagenEntorno!.path).copy('$localPath/$nameEntorno');

      final Map<String, dynamic> datosBase = {
        'infraccion_id': idInfraccion,
        'localidad_id': widget.localidadId,
        'fecha': Timestamp.fromDate(now),
        'registrado_por': widget.userName,
        'patente': patenteClean,
        'marca': _marcaController.text.toUpperCase(),
        'modelo': _modeloController.text.toUpperCase(),
        'calle_ruta': _calleController.text.toUpperCase(),
        'numero_km': _numeroController.text.toUpperCase(),
        'tipo_infraccion': _tipoInfraccionController.text.toUpperCase(),
        'observaciones': _observacionesController.text.toUpperCase(),
        'ubicacion_gps': _ubicacionGps,
        'fotos_subidas': false,
        'nombre_txt': nameTxt,
        'nombre_patente': namePatente,
        'nombre_entorno': nameEntorno,
        'fecha_carpeta': dayFolder,
        'ruta_local_txt': fileTxt.path,
        'ruta_local_patente': fileP.path,
        'ruta_local_entorno': fileE.path,
      };

      FirebaseFirestore.instance.collection('infracciones').doc(idInfraccion).set(datosBase);
      _subirEstructurado(idInfraccion, datosBase);

      if (!mounted) return;
      setState(() { _subiendo = false; });
      _limpiarFormulario();

      // CAMBIO AQUÍ: Ahora el mensaje de éxito sale en VERDE
      _mostrarSnackBar("Acta guardada localmente", Colors.green);

      FocusScope.of(context).unfocus();

    } catch (e) {
      if (mounted) setState(() { _subiendo = false; });
    }
  }

  Future<void> _subirEstructurado(String docId, Map<String, dynamic> data) async {
    try {
      final String folder = "infracciones/${data['localidad_id']}/${data['fecha_carpeta']}";
      final refTxt = FirebaseStorage.instance.ref().child("$folder/${data['nombre_txt']}");
      final refPat = FirebaseStorage.instance.ref().child("$folder/${data['nombre_patente']}");
      final refEnt = FirebaseStorage.instance.ref().child("$folder/${data['nombre_entorno']}");

      await Future.wait([
        refTxt.putFile(File(data['ruta_local_txt'])),
        refPat.putFile(File(data['ruta_local_patente'])),
        refEnt.putFile(File(data['ruta_local_entorno'])),
      ]);

      final urls = await Future.wait([
        refPat.getDownloadURL(),
        refEnt.getDownloadURL(),
      ]);

      await FirebaseFirestore.instance.collection('infracciones').doc(docId).update({
        'fotos_subidas': true,
        'foto_patente_url': urls[0],
        'foto_entorno_url': urls[1],
      });
    } catch (e) {
      debugPrint("Storage pendiente");
    }
  }

  void _limpiarFormulario() {
    _patenteController.clear(); _marcaController.clear(); _modeloController.clear();
    _calleController.clear(); _numeroController.clear(); _tipoInfraccionController.clear(); _observacionesController.clear();
    setState(() { _imagenPatente = null; _imagenEntorno = null; _ubicacionGps = "No obtenida"; _patenteDetectadaExito = false; });
  }

  void _mostrarSnackBar(String m, Color c) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(m, style: const TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: c,
          behavior: SnackBarBehavior.floating, // Le da un toque más moderno
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        )
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: naranjaXsim)),
        const SizedBox(height: 4),
        Container(height: 1.5, width: 40, color: naranjaXsim),
      ]),
    );
  }

  Widget _buildField(TextEditingController controller, String label, IconData icon, {TextInputType type = TextInputType.text, Widget? suffix}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TextFormField(
      controller: controller, keyboardType: type, inputFormatters: [UpperCaseTextFormatter()],
      decoration: InputDecoration(
        labelText: label, prefixIcon: Icon(icon, color: naranjaXsim), suffixIcon: suffix,
        filled: true, fillColor: isDark ? Colors.white10 : Colors.grey[100],
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      validator: (v) => v!.isEmpty ? 'Requerido' : null,
    );
  }

  Widget _buildAutocompleteField({required TextEditingController controller, required String label, required List<String> options, IconData? icon}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Autocomplete<String>(
      optionsBuilder: (val) => val.text.isEmpty ? options : options.where((o) => o.contains(val.text.toUpperCase())),
      onSelected: (s) => controller.text = s,
      fieldViewBuilder: (ctx, fieldCtrl, node, submit) {
        if (controller.text != fieldCtrl.text) fieldCtrl.text = controller.text;
        return TextFormField(
          controller: fieldCtrl, focusNode: node, inputFormatters: [UpperCaseTextFormatter()],
          decoration: InputDecoration(
            labelText: label, prefixIcon: icon != null ? Icon(icon, color: naranjaXsim) : null,
            filled: true, fillColor: isDark ? Colors.white10 : Colors.grey[100],
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onChanged: (v) => controller.text = v.toUpperCase(),
          validator: (v) => v!.isEmpty ? 'Requerido' : null,
        );
      },
    );
  }

  Widget _buildImageCard(String label, XFile? image, VoidCallback onTap) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(children: [
      Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      InkWell(
        onTap: onTap,
        child: Container(
          height: 120, width: double.infinity,
          decoration: BoxDecoration(border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(12), color: isDark ? Colors.white10 : Colors.grey[50]),
          child: image == null ? const Icon(Icons.camera_alt, size: 40) : ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.file(File(image.path), fit: BoxFit.cover)),
        ),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    List<String> modelos = (vehiculosSugeridos.containsKey(_marcaController.text)) ? vehiculosSugeridos[_marcaController.text]! : [];

    return Scaffold(
      appBar: AppBar(
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.localidadId.toUpperCase(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: naranjaXsim)),
            Text(widget.userName.isEmpty ? "AGENTE XSIM" : widget.userName.toUpperCase(), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: isDark ? Colors.white : Colors.black87)),
          ],
        ),
        actions: [
          IconButton(onPressed: widget.onThemeToggle, icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode)),
          IconButton(onPressed: _logout, icon: const Icon(Icons.logout))
        ],
      ),
      body: Stack(children: [
        SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(children: [
              Row(children: [
                Expanded(child: _buildImageCard('Patente', _imagenPatente, () => _pickImage(true))),
                const SizedBox(width: 10),
                Expanded(child: _buildImageCard('Entorno', _imagenEntorno, () => _pickImage(false))),
              ]),
              _buildSectionTitle('Vehículo'),
              _buildField(_patenteController, 'Patente', Icons.directions_car, suffix: _patenteDetectadaExito ? const Icon(Icons.check_circle, color: Colors.green) : null),
              const SizedBox(height: 15),
              Row(children: [
                Expanded(child: _buildAutocompleteField(controller: _marcaController, label: 'Marca', options: vehiculosSugeridos.keys.toList(), icon: Icons.branding_watermark)),
                const SizedBox(width: 10),
                Expanded(child: _buildAutocompleteField(controller: _modeloController, label: 'Modelo', options: modelos, icon: Icons.model_training)),
              ]),
              _buildSectionTitle('Ubicación'),
              _buildField(_calleController, 'Calle / Ruta', Icons.map, suffix: IconButton(icon: const Icon(Icons.my_location, color: naranjaXsim), onPressed: () => _obtenerUbicacion())),
              const SizedBox(height: 15),
              _buildField(_numeroController, 'Nro / Km', Icons.location_on, type: TextInputType.number),
              _buildSectionTitle('Infracción'),
              _buildAutocompleteField(controller: _tipoInfraccionController, label: 'Tipo de Infracción', options: infraccionesSugeridas, icon: Icons.warning),
              const SizedBox(height: 15),
              TextFormField(
                controller: _observacionesController, maxLines: 3, inputFormatters: [UpperCaseTextFormatter()],
                decoration: InputDecoration(
                    labelText: 'Observaciones',
                    prefixIcon: const Icon(Icons.edit_note, color: naranjaXsim),
                    filled: true, fillColor: isDark ? Colors.white10 : Colors.grey[100],
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))
                ),
              ),
              const SizedBox(height: 30),
              ElevatedButton(
                onPressed: _subiendo ? null : _registrarInfraccion,
                style: ElevatedButton.styleFrom(backgroundColor: naranjaXsim, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 60), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
                child: const Text('REGISTRAR INFRACCIÓN', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 20),
            ]),
          ),
        ),
        if (_subiendo) Container(color: Colors.black87, child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [const CircularProgressIndicator(color: naranjaXsim), const SizedBox(height: 20), Text(_estadoSubida, style: const TextStyle(color: Colors.white))]))),
      ]),
    );
  }
}

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue old, TextEditingValue newVal) =>
      TextEditingValue(text: newVal.text.toUpperCase(), selection: newVal.selection);
}