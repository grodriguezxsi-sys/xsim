import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:flutter/foundation.dart';
import '../services/connectivity_service.dart';
import '../services/deteccion_service.dart';
import 'confirmacion_screen.dart'; // Importada

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
  
  static const Color naranjaXsim = Color(0xFFE8952A);

  bool _subiendo = false;
  String _estadoSubida = "";
  final ImagePicker _picker = ImagePicker();
  final DeteccionVehiculoService _deteccionService = DeteccionVehiculoService();
  bool _ocrDetectado = false;
  
  late final AnimationController _animationController;

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

  Future<void> _logout() async {
    final state = context.read<ConnectivityService>();
    await FirebaseAuth.instance.signOut();
    state.reset();
  }

  Future<void> _obtenerUbicacion({bool actualizarDireccion = true}) async {
    final state = context.read<ConnectivityService>();
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      
      LocationSettings locationSettings;
      if (defaultTargetPlatform == TargetPlatform.android) {
        locationSettings = AndroidSettings(accuracy: LocationAccuracy.high, distanceFilter: 10);
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        locationSettings = AppleSettings(accuracy: LocationAccuracy.high, distanceFilter: 10);
      } else {
        locationSettings = LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 10);
      }
      
      Position position = await Geolocator.getCurrentPosition(locationSettings: locationSettings);
      if (!mounted) return;
      setState(() {
        state.ubicacionGps = "${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}";
      });

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
          _ocrDetectado = true;
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

  // AHORA ESTA FUNCIÓN SE LLAMA DESDE LA PANTALLA DE CONFIRMACIÓN
  Future<void> _finalizarYRegistrar(Map<String, dynamic> datosCompletos) async {
    final state = context.read<ConnectivityService>();
    setState(() { _subiendo = true; _estadoSubida = "Asegurando registro local..."; });

    try {
      final idInfraccion = FirebaseFirestore.instance.collection('infracciones').doc().id;
      final dayFolder = DateFormat('dd-MM-yyyy').format(DateTime.now());
      final timestamp = DateFormat('ddMMyyyyHHmmss').format(DateTime.now());
      final patente = state.patenteController.text.toUpperCase().replaceAll(' ', '');

      final String nameP = "${timestamp}_${idInfraccion}_foto_patente_$patente.jpg";
      final String nameE = "${timestamp}_${idInfraccion}_foto_entorno_$patente.jpg";
      final String nameD = "${timestamp}_${idInfraccion}_dato_$patente.txt";

      final directory = await getApplicationDocumentsDirectory();
      final localPath = Directory('${directory.path}/evidencia/$idInfraccion');
      if (!await localPath.exists()) await localPath.create(recursive: true);

      final File fileP = await File(state.imagenPatente!.path).copy('${localPath.path}/$nameP');
      final File fileE = await File(state.imagenEntorno!.path).copy('${localPath.path}/$nameE');

      // Agregamos las rutas locales al mapa de datos que vino de ConfirmacionScreen
      datosCompletos['id'] = idInfraccion;
      datosCompletos['fecha_carpeta'] = dayFolder;
      datosCompletos['nombre_archivo_patente'] = nameP;
      datosCompletos['nombre_archivo_entorno'] = nameE;
      datosCompletos['nombre_archivo_dato'] = nameD;
      datosCompletos['ruta_local_patente'] = fileP.path;
      datosCompletos['ruta_local_entorno'] = fileE.path;
      datosCompletos['ruta_local_dato'] = '${localPath.path}/$nameD';
      datosCompletos['dato_url'] = '';
      datosCompletos['foto_entorno_url'] = '';
      datosCompletos['foto_patente_url'] = '';
      datosCompletos['fotos_subidas'] = false;
      
      final File fileD = File('${localPath.path}/$nameD');
      await fileD.writeAsString(const JsonEncoder.withIndent('  ').convert(datosCompletos));

      final Map<String, dynamic> firestoreData = Map.from(datosCompletos);
      firestoreData['fecha'] = FieldValue.serverTimestamp(); // Obligatorio para Firestore

      await FirebaseFirestore.instance.collection('infracciones').doc(idInfraccion).set(firestoreData);

      if (!mounted) return;
      
      state.clearForm();
      setState(() { _subiendo = false; _estadoSubida = ""; _ocrDetectado = false; });
      
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Acta guardada correctamente. Se sincronizará automáticamente.'), 
        backgroundColor: Colors.green,
        duration: Duration(seconds: 3),
      ));
      
      Navigator.pop(context); // Volver al formulario (que ya estará limpio)

    } catch (e) {
      if (mounted) {
        setState(() { _subiendo = false; _estadoSubida = ""; });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al registrar: $e')));
      }
    }
  }

  void _abrirConfirmacion() {
    final state = context.read<ConnectivityService>();
    if (!_formKey.currentState!.validate() || state.imagenPatente == null || state.imagenEntorno == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Faltan fotos o datos')));
      return;
    }

    // Buscamos la infracción seleccionada en el catálogo
    final infraccionSeleccionada = state.catalogoInfracciones.firstWhere(
      (inf) => inf['titulo'] == state.tipoInfraccionController.text,
      orElse: () => {}
    );

    double montoTotal = 0.0;
    if (state.valorizacionActiva && infraccionSeleccionada.isNotEmpty) {
      final double ufMinimas = (infraccionSeleccionada['uf_minimas'] ?? 0).toDouble();
      montoTotal = ufMinimas * state.valorUf;
    }

    // Estructura oficial limpia y estandarizada
    final datosEstandar = {
      'id': '', // Se asignará en _finalizarYRegistrar
      'localidad_id': widget.localidadId,
      'patente': state.patenteController.text.toUpperCase().replaceAll(' ', ''),
      'infraccion': state.tipoInfraccionController.text.toUpperCase(),
      'infraccion_codigo': infraccionSeleccionada['codigo'] ?? '',
      'infraccion_uf': infraccionSeleccionada['uf_minimas'] ?? 0,
      'valor_uf_aplicado': state.valorUf,
      'monto_total_calculado': montoTotal,
      'fecha': '', // FieldValue.serverTimestamp() se añade al guardar
      'fecha_carpeta': '',
      'fecha_hora': DateTime.now().toIso8601String(),
      'marca': state.marcaController.text.toUpperCase(),
      'modelo': state.modeloController.text.toUpperCase(),
      'ubicacion': {
        'calle': state.calleController.text.toUpperCase(), 
        'nro': state.numeroController.text.toUpperCase(), 
        'gps': state.ubicacionGps
      },
      'observaciones': state.observacionesController.text.toUpperCase(),
      'registrado_por': widget.userName,
      // Los campos de archivos se llenan en _finalizarYRegistrar
    };

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ConfirmacionScreen(
          data: datosEstandar,
          imagenPatente: state.imagenPatente!,
          imagenEntorno: state.imagenEntorno!,
          onConfirm: () => _finalizarYRegistrar(datosEstandar),
        ),
      ),
    );
  }

  bool get _isFormComplete {
    final state = context.read<ConnectivityService>();
    return state.imagenPatente != null &&
           state.imagenEntorno != null &&
           state.patenteController.text.trim().isNotEmpty &&
           state.marcaController.text.trim().isNotEmpty &&
           state.modeloController.text.trim().isNotEmpty &&
           state.calleController.text.trim().isNotEmpty &&
           state.numeroController.text.trim().isNotEmpty &&
           state.tipoInfraccionController.text.trim().isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final state = context.watch<ConnectivityService>();
    final formComplete = _isFormComplete;
    
    // Variables de estilo dinámicas
    final Color fondoTarjeta = isDark ? const Color(0xFF222839) : Colors.white;
    final Color colorTextoPrimario = isDark ? Colors.white : const Color(0xFF1A1F2E);
    final Color colorTextoSecundario = isDark ? Colors.white38 : Colors.black38;

    // A prueba de fallos: Filtramos los nulls y nos aseguramos de que sean Strings válidos
    final List<String> opcionesInfraccion = state.catalogoInfracciones
        .map((inf) => inf['titulo'])
        .where((titulo) => titulo != null && titulo.toString().trim().isNotEmpty)
        .map((titulo) => titulo.toString())
        .toList();

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 80,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.localidadId.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: naranjaXsim, letterSpacing: 1.2)),
            Text(widget.userName, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: colorTextoPrimario, letterSpacing: -0.5)),
          ],
        ),
        actions: [
          IconButton(onPressed: _subiendo ? null : widget.onThemeToggle, icon: Icon(Icons.brightness_4, color: colorTextoPrimario.withAlpha(180))), 
          IconButton(onPressed: _subiendo ? null : _logout, icon: Icon(Icons.logout, color: colorTextoPrimario.withAlpha(180)))
        ],
      ),
      body: Stack(children: [
        SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Form(key: _formKey, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: _buildPhotoCard('PATENTE', state.imagenPatente, () => _pickImage(true), fondoTarjeta, colorTextoSecundario)),
              const SizedBox(width: 15),
              Expanded(child: _buildPhotoCard('ENTORNO', state.imagenEntorno, () => _pickImage(false), fondoTarjeta, colorTextoSecundario)),
            ]),
            const SizedBox(height: 30),
            
            _buildHeaderTitle('VEHÍCULO', isDark),
            _buildPatenteField(state.patenteController, fondoTarjeta),
            const SizedBox(height: 15),
            _buildDropdown(state.marcaController, 'Marca', ['TOYOTA', 'FORD', 'FIAT', 'VOLKSWAGEN', 'CHEVROLET', 'RENAULT', 'PEUGEOT'], Icons.factory, fondoTarjeta, colorTextoSecundario, colorTextoPrimario, bordeColor: naranjaXsim.withAlpha(80)),
            const SizedBox(height: 15),
            _buildField(state.modeloController, 'Modelo', Icons.category, fondoTarjeta, colorTextoSecundario, colorTextoPrimario, label: 'Modelo', bordeColor: naranjaXsim.withAlpha(80)),
            const SizedBox(height: 30),

            _buildHeaderTitle('UBICACIÓN', isDark),
            _buildLocationField(state.calleController, 'Calle / Ruta', Icons.public, fondoTarjeta, colorTextoSecundario, colorTextoPrimario),
            const SizedBox(height: 15),
            _buildField(state.numeroController, 'Nro de calle o km de ruta', Icons.pin_drop, fondoTarjeta, colorTextoSecundario, colorTextoPrimario, label: 'Altura / Km', bordeColor: const Color(0xFF2E7D32).withAlpha(80)),
            const SizedBox(height: 30),

            _buildHeaderTitle('INFRACCIÓN', isDark),
            // Si la lista está vacía, mostramos un mensaje de advertencia seguro
            _buildInfraccionDropdown(state.tipoInfraccionController, 'Seleccionar infracción', opcionesInfraccion.isNotEmpty ? opcionesInfraccion : ['(Sin infracciones cargadas)'], fondoTarjeta, colorTextoSecundario, colorTextoPrimario),
            const SizedBox(height: 15),
            _buildObservationsField(state.observacionesController, 'Añadir observaciones adicionales...', fondoTarjeta, colorTextoPrimario, colorTextoSecundario),
            
            const SizedBox(height: 40),

            _buildStepIndicator(formComplete, isDark),
            const SizedBox(height: 15),
            
            _buildConfirmButton(formComplete, isDark),
            const SizedBox(height: 30),
          ])),
        ),
        if (_subiendo) Container(color: isDark ? Colors.black87 : Colors.white70, child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [const CircularProgressIndicator(color: naranjaXsim), const SizedBox(height: 20), Text(_estadoSubida, style: TextStyle(color: colorTextoPrimario, fontWeight: FontWeight.bold))]))),
      ]),
    );
  }

  Widget _buildStepIndicator(bool complete, bool isDark) {
    return Row(
      children: List.generate(4, (index) => Expanded(
        child: Container(
          height: 4,
          margin: EdgeInsets.only(right: index == 3 ? 0 : 8),
          decoration: BoxDecoration(
            color: (index < (complete ? 4 : 2)) ? naranjaXsim : (isDark ? Colors.white12 : Colors.black.withAlpha(20)),
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      )),
    );
  }

  Widget _buildHeaderTitle(String title, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: naranjaXsim, letterSpacing: 0.5)),
          const SizedBox(width: 15),
          Expanded(child: Divider(color: isDark ? Colors.white.withAlpha(20) : Colors.black.withAlpha(20), thickness: 1)),
        ],
      ),
    );
  }

  Widget _buildPhotoCard(String label, XFile? image, VoidCallback onTap, Color fondo, Color textoSec) {
    return GestureDetector(
      onTap: _subiendo ? null : onTap,
      child: Container(
        height: 140,
        decoration: BoxDecoration(
          color: fondo,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: image != null ? naranjaXsim : naranjaXsim.withAlpha(80), 
            width: 1.5
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (image != null)
              ClipRRect(borderRadius: BorderRadius.circular(13), child: Image.file(File(image.path), fit: BoxFit.cover, width: double.infinity, height: double.infinity)),
            if (image == null)
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(label == 'PATENTE' ? Icons.directions_car : Icons.camera_alt, color: textoSec, size: 40),
                  const SizedBox(height: 8),
                  Text(label == 'PATENTE' ? 'Patente' : 'Entorno (0/3)', style: TextStyle(color: textoSec, fontSize: 12)),
                ],
              ),
            if (image != null)
              Positioned(
                top: 8, right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: naranjaXsim, borderRadius: BorderRadius.circular(20)),
                  child: const Text('1 foto', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              )
          ],
        ),
      ),
    );
  }

  Widget _buildPatenteField(TextEditingController controller, Color fondo) {
    return Container(
      decoration: BoxDecoration(
        color: fondo, 
        borderRadius: BorderRadius.circular(12), 
        border: Border.all(color: naranjaXsim.withAlpha(100), width: 1.5)
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const Icon(Icons.directions_car, color: naranjaXsim, size: 20),
          const SizedBox(width: 15),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: naranjaXsim, borderRadius: BorderRadius.circular(8)),
            child: SizedBox(
              width: 100,
              child: TextFormField(
                controller: controller,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                inputFormatters: [UpperCaseTextFormatter()],
                decoration: const InputDecoration(border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.zero),
                onChanged: (v) => setState(() {}),
              ),
            ),
          ),
          const Spacer(),
          if (_ocrDetectado)
            const Row(children: [
              Icon(Icons.check, color: Colors.greenAccent, size: 14),
              SizedBox(width: 4),
              Text('OCR detectado', style: TextStyle(color: Colors.greenAccent, fontSize: 11)),
            ]),
        ],
      ),
    );
  }

  Widget _buildLocationField(TextEditingController controller, String label, IconData icon, Color fondo, Color textoSec, Color textoPri) {
    final Color colorGps = const Color(0xFF2E7D32);
    return Container(
      decoration: BoxDecoration(
        color: fondo, 
        borderRadius: BorderRadius.circular(12), 
        border: Border.all(color: colorGps.withAlpha(100), width: 1.5)
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(icon, color: naranjaXsim, size: 20),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: textoSec, fontSize: 10)),
                TextFormField(
                  controller: controller,
                  style: TextStyle(color: textoPri, fontWeight: FontWeight.w600),
                  decoration: const InputDecoration(border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.only(top: 4)),
                  onChanged: (v) => setState(() {}),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: colorGps.withAlpha(40), borderRadius: BorderRadius.circular(20)),
            child: Row(children: [
              CircleAvatar(backgroundColor: colorGps, radius: 3),
              const SizedBox(width: 5),
              Text('GPS', style: TextStyle(color: colorGps, fontSize: 10, fontWeight: FontWeight.bold)),
            ]),
          )
        ],
      ),
    );
  }

  Widget _buildField(TextEditingController controller, String placeholder, IconData icon, Color fondo, Color textoSec, Color textoPri, {String? label, Color? bordeColor}) {
    return Container(
      decoration: BoxDecoration(
        color: fondo, 
        borderRadius: BorderRadius.circular(12), 
        border: Border.all(color: bordeColor ?? Colors.black.withAlpha(15), width: 1.5)
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(icon, color: textoSec, size: 20),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (label != null) Text(label, style: TextStyle(color: textoSec, fontSize: 10)),
                TextFormField(
                  controller: controller,
                  inputFormatters: label == 'Modelo' ? [UpperCaseTextFormatter()] : null,
                  style: TextStyle(color: textoPri, fontWeight: FontWeight.w500),
                  decoration: InputDecoration(
                    hintText: placeholder,
                    hintStyle: TextStyle(color: textoSec.withAlpha(100), fontSize: 14),
                    border: InputBorder.none, 
                    isDense: true, 
                    contentPadding: const EdgeInsets.only(top: 4)
                  ),
                  onChanged: (v) => setState(() {}),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdown(TextEditingController controller, String label, List<String> options, IconData icon, Color fondo, Color textoSec, Color textoPri, {Color? bordeColor}) {
    return Container(
      decoration: BoxDecoration(
        color: fondo, 
        borderRadius: BorderRadius.circular(12), 
        border: Border.all(color: bordeColor ?? Colors.black.withAlpha(15), width: 1.5)
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(children: [
        Icon(icon, color: textoSec, size: 20),
        const SizedBox(width: 15),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(color: textoSec, fontSize: 10)),
              DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: options.contains(controller.text) && controller.text.isNotEmpty ? controller.text : null,
                  dropdownColor: fondo,
                  icon: const Icon(Icons.arrow_drop_down, color: naranjaXsim),
                  items: options.map((s) => DropdownMenuItem(value: s, child: Text(s, style: TextStyle(color: textoPri, fontSize: 14)))).toList(),
                  onChanged: (v) => setState(() => controller.text = v!),
                ),
              ),
            ],
          ),
        )
      ]),
    );
  }

  Widget _buildInfraccionDropdown(TextEditingController controller, String label, List<String> options, Color fondo, Color textoSec, Color textoPri) {
    bool hasValue = options.contains(controller.text) && controller.text.isNotEmpty;
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    
    final Color fondoInfraccion = hasValue 
      ? (isDark ? const Color(0xFF2D1B20) : const Color(0xFFFFEBEE)) 
      : fondo;
    final Color colorBorde = hasValue 
      ? Colors.redAccent.withAlpha(150) 
      : Colors.redAccent.withAlpha(50);

    return Container(
      decoration: BoxDecoration(
        color: fondoInfraccion,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorBorde, width: 1.5)
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(children: [
        const CircleAvatar(backgroundColor: Colors.redAccent, radius: 4),
        const SizedBox(width: 15),
        Expanded(
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              hint: Text(label, style: TextStyle(color: textoSec, fontSize: 14)),
              value: hasValue ? controller.text : null,
              dropdownColor: fondo,
              icon: Icon(Icons.arrow_drop_down, color: textoSec),
              items: options.map((s) => DropdownMenuItem(
                value: s, 
                child: Text(s, style: TextStyle(color: textoPri, fontSize: 14, fontWeight: FontWeight.bold))
              )).toList(),
              onChanged: (v) => setState(() => controller.text = v!),
            ),
          ),
        )
      ]),
    );
  }

  Widget _buildObservationsField(TextEditingController controller, String hint, Color fondo, Color textoPri, Color textoSec) {
    return Container(
      decoration: BoxDecoration(
        color: fondo, 
        borderRadius: BorderRadius.circular(12), 
        border: Border.all(color: Colors.black.withAlpha(15), width: 1.5)
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.note_alt, color: textoSec, size: 20),
          const SizedBox(width: 15),
          Expanded(
            child: TextFormField(
              controller: controller,
              maxLines: 4,
              enabled: !_subiendo,
              style: TextStyle(color: textoPri.withAlpha(200), fontSize: 14),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(color: textoSec.withAlpha(100), fontSize: 13),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfirmButton(bool complete, bool isDark) {
    return ElevatedButton(
      onPressed: (_subiendo || !complete) ? null : _abrirConfirmacion,
      style: ElevatedButton.styleFrom(
        backgroundColor: complete ? naranjaXsim : (isDark ? const Color(0xFF1A2838) : Colors.black.withAlpha(20)),
        foregroundColor: Colors.white,
        disabledBackgroundColor: isDark ? const Color(0xFF1A2838) : Colors.black.withAlpha(20),
        disabledForegroundColor: Colors.white.withAlpha(100),
        minimumSize: const Size(double.infinity, 65),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15), 
          side: BorderSide(color: isDark ? Colors.white.withAlpha(10) : Colors.black.withAlpha(10))
        ),
        elevation: complete ? 8 : 0,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('Revisar y confirmar', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(width: 15),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(40), 
              borderRadius: BorderRadius.circular(20)
            ),
            child: Text(complete ? 'paso 4/4' : 'incompleto', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
          )
        ],
      ),
    );
  }
}

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue old, TextEditingValue newVal) => TextEditingValue(text: newVal.text.toUpperCase(), selection: newVal.selection);
}
