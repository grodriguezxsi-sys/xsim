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
import '../services/deteccion_service.dart';

class InfraccionForm extends StatefulWidget {
  final String localidadId;
  final String userName;
  final VoidCallback onThemeToggle;
  const InfraccionForm({super.key, required this.localidadId, required this.userName, required this.onThemeToggle});

  @override
  State<InfraccionForm> createState() => _InfraccionFormState();
}

class _InfraccionFormState extends State<InfraccionForm> with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  final _formKey = GlobalKey<FormState>();
  static const Color naranjaXsim = Color(0xFFFF8C00);

  bool _subiendo = false;
  String _estadoSubida = "";
  final ImagePicker _picker = ImagePicker();
  final DeteccionVehiculoService _deteccionService = DeteccionVehiculoService();
  
  late final AnimationController _animationController;

  final List<String> _infraccionesSugeridas = [
    'OBSTRUCCIÓN DE RAMPA',
    'SENDA PEATONAL',
    'DOBLE FILA',
    'ENTRADA DE GARAJE',
    'PARADAS DE COLECTIVO Y TAXIS',
    'OCHAVA',
    'LUGAR RESERVADO (SERVICIOS DE EMERGENCIA)',
    'ESTACIONAMIENTO INDEBIDO',
  ];

  @override
  bool get wantKeepAlive => true;

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
    _deteccionService.dispose();
    super.dispose();
  }

  Future<void> _logout() async => await FirebaseAuth.instance.signOut();

  Future<void> _obtenerUbicacion({bool actualizarDireccion = true}) async {
    final state = context.read<ConnectivityService>();
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      if (!mounted) return;
      setState(() => state.ubicacionGps = "${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}");

      if (actualizarDireccion) {
        List<Placemark> placemarks = await placemarkFromCoordinates(position.latitude, position.longitude);
        if (placemarks.isNotEmpty) {
          Placemark place = placemarks[0];
          setState(() {
            state.calleController.text = place.thoroughfare ?? "";
            state.numeroController.text = place.subThoroughfare ?? "";
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _pickImage(bool isPatente) async {
    final state = context.read<ConnectivityService>();
    final XFile? image = await _picker.pickImage(source: ImageSource.camera, imageQuality: 70);
    if (image != null) {
      setState(() => isPatente ? state.imagenPatente = image : state.imagenEntorno = image);
      _obtenerUbicacion(actualizarDireccion: isPatente);
      
      if (isPatente) {
        _ejecutarDeteccionOCR(image.path);
      }
    }
  }

  Future<void> _ejecutarDeteccionOCR(String path) async {
    final state = context.read<ConnectivityService>();
    setState(() => _estadoSubida = "Analizando patente...");
    
    try {
      final resultados = await _deteccionService.procesarYDeteccionDual(path);
      if (!mounted) return;
      
      setState(() {
        if (resultados['patente'] != null) {
          state.patenteController.text = resultados['patente']!;
        }
        if (resultados['marca'] != null) {
          state.marcaController.text = resultados['marca']!;
        }
        if (resultados['modelo'] != null) {
          state.modeloController.text = resultados['modelo']!;
        }
      });
    } catch (e) {
      debugPrint("Error en OCR: $e");
    } finally {
      if (mounted) setState(() => _estadoSubida = "");
    }
  }

  Future<void> _registrarInfraccion() async {
    final state = context.read<ConnectivityService>();
    if (!_formKey.currentState!.validate() || state.imagenPatente == null || state.imagenEntorno == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Faltan fotos o datos')));
      return;
    }

    setState(() { _subiendo = true; _estadoSubida = "Asegurando registro local..."; });

    try {
      final now = DateTime.now();
      final idInfraccion = FirebaseFirestore.instance.collection('infracciones').doc().id;
      final dayFolder = DateFormat('dd-MM-yyyy').format(now);
      final timestamp = DateFormat('ddMMyyyyHHmmss').format(now);
      final patente = state.patenteController.text.toUpperCase().replaceAll(' ', '');

      final String nameP = "${timestamp}_${idInfraccion}_foto_patente_$patente.jpg";
      final String nameE = "${timestamp}_${idInfraccion}_foto_entorno_$patente.jpg";
      final String nameD = "${timestamp}_${idInfraccion}_dato_$patente.txt";

      final directory = await getApplicationDocumentsDirectory();
      final localPath = Directory('${directory.path}/evidencia/$idInfraccion');
      if (!await localPath.exists()) await localPath.create(recursive: true);

      final File fileP = await File(state.imagenPatente!.path).copy('${localPath.path}/$nameP');
      final File fileE = await File(state.imagenEntorno!.path).copy('${localPath.path}/$nameE');

      final Map<String, dynamic> datosJson = {
        'id': idInfraccion,
        'localidad_id': widget.localidadId,
        'patente': patente,
        'marca': state.marcaController.text.toUpperCase(),
        'modelo': state.modeloController.text.toUpperCase(),
        'ubicacion': {'calle': state.calleController.text.toUpperCase(), 'nro': state.numeroController.text.toUpperCase(), 'gps': state.ubicacionGps},
        'infraccion': state.tipoInfraccionController.text.toUpperCase(),
        'observaciones': state.observacionesController.text.toUpperCase(),
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

      state.notifyListeners();

      if (!mounted) return;
      
      state.clearForm();
      setState(() { _subiendo = false; _estadoSubida = ""; });
      
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Acta guardada correctamente. Se sincronizará automáticamente.'), 
        backgroundColor: Colors.green, // CAMBIADO A VERDE
        duration: Duration(seconds: 3),
      ));
      
    } catch (e) {
      if (mounted) {
        setState(() { _subiendo = false; _estadoSubida = ""; });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al registrar: $e')));
      }
    }
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
        fillColor: isDark ? Colors.white.withOpacity(0.05) : Colors.grey[100],
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
            fillColor: isDark ? Colors.white.withOpacity(0.05) : Colors.grey[100],
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
    super.build(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final state = context.watch<ConnectivityService>();

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
              Expanded(child: _buildImageCard('Patente', state.imagenPatente, () => _pickImage(true))),
              const SizedBox(width: 10),
              Expanded(child: _buildImageButton('Entorno', state.imagenEntorno, () => _pickImage(false))),
            ]),
            _buildSectionTitle('Vehículo'),
            _buildField(state.patenteController, 'Patente', Icons.directions_car),
            const SizedBox(height: 15),
            Row(children: [
              Expanded(child: _buildAutocomplete(state.marcaController, 'Marca', ['TOYOTA', 'FORD', 'FIAT', 'VOLKSWAGEN', 'CHEVROLET', 'RENAULT', 'PEUGEOT'], Icons.factory)),
              const SizedBox(width: 10),
              Expanded(child: _buildField(state.modeloController, 'Modelo', Icons.category)),
            ]),
            _buildSectionTitle('Ubicación'),
            _buildField(state.calleController, 'Calle / Ruta', Icons.map, suffix: IconButton(icon: const Icon(Icons.my_location, color: naranjaXsim), onPressed: () => _obtenerUbicacion())),
            const SizedBox(height: 15),
            _buildField(state.numeroController, 'Nro / Km', Icons.location_on, type: TextInputType.number),
            _buildSectionTitle('Infracción'),
            _buildAutocomplete(state.tipoInfraccionController, 'Infracción', _infraccionesSugeridas, Icons.warning),
            const SizedBox(height: 15),
            _buildField(state.observacionesController, 'Observaciones', Icons.edit_note),
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
