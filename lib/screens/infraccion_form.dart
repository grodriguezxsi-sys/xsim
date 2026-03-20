import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
  String _estadoSubida = "";
  final ImagePicker _picker = ImagePicker();

  final Map<String, List<String>> _vehiculosSugeridos = {
    'TOYOTA': ['COROLLA', 'HILUX', 'ETIOS', 'YARIS', 'SW4', 'PRIUS'],
    'FORD': ['RANGER', 'FOCUS', 'FIESTA', 'KA', 'ECOSPORT', 'TERRITORY', 'F-150'],
    'FIAT': ['CRONOS', 'TORO', 'MOBI', 'ARGO', 'PALIO', 'UNO', 'STRADA', 'PULSE'],
    'VOLKSWAGEN': ['GOL', 'AMAROK', 'POLO', 'VIRTUS', 'T-CROSS', 'TAOS', 'NIVUS', 'VENTO'],
    'RENAULT': ['SANDERO', 'LOGAN', 'KANGOO', 'ALASKAN', 'DUSTER', 'KWID', 'STEPWAY', 'OROCH'],
    'CHEVROLET': ['ONIX', 'CRUZE', 'S10', 'TRACKER', 'JOY', 'SPIN', 'EQUINOX'],
    'PEUGEOT': ['208', '2008', '308', '408', 'PARTNER', '3008', '5008'],
    'CITROEN': ['C3', 'C4 CACTUS', 'BERLINGO', 'C5 AIRCROSS'],
    'HONDA': ['CIVIC', 'HR-V', 'FIT', 'CR-V', 'CITY'],
    'NISSAN': ['FRONTIER', 'VERSA', 'KICKS', 'SENTRA', 'X-TRAIL'],
    'HYUNDAI': ['TUCSON', 'CRETA', 'HB20', 'KONA'],
    'JEEP': ['RENEGADE', 'COMPASS', 'COMMANDER', 'WRANGLER'],
    'MERCEDES-BENZ': ['CLASE A', 'CLASE C', 'CLASE E', 'SPRINTER', 'GLC', 'GLE'],
    'AUDI': ['A1', 'A3', 'A4', 'A5', 'Q2', 'Q3', 'Q5'],
    'BMW': ['SERIE 1', 'SERIE 3', 'SERIE 5', 'X1', 'X3', 'X5'],
    'KIA': ['RIO', 'PICANTO', 'SPORTAGE', 'SORENTO', 'CERATO'],
    'CHERY': ['TIGGO 2', 'TIGGO 3', 'TIGGO 4', 'QQ'],
  };

  final List<String> _infraccionesSugeridas = [
    'ESTACIONAMIENTO EN DOBLE FILA',
    'ESTACIONAMIENTO SOBRE SENDA PEATONAL',
    'ESTACIONAMIENTO EN OCHAVA',
    'ESTACIONAMIENTO FRENTE A GARAJE/COCHERA',
    'ESTACIONAMIENTO EN LUGAR PROHIBIDO',
    'ESTACIONAMIENTO SOBRE VEREDA',
    'ESTACIONAMIENTO EN RESERVADO DISCAPACITADOS',
    'ESTACIONAMIENTO EN RESERVADO CARGA Y DESCARGA',
    'ESTACIONAMIENTO EN SENTIDO CONTRARIO',
    'OBSTRUCCIÓN DE RAMPA PARA DISCAPACITADOS',
    'SIN TICKET DE ESTACIONAMIENTO MEDIDO',
    'TICKET DE ESTACIONAMIENTO VENCIDO',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Geolocator.requestPermission();
    });
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
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate() || _imagenPatente == null || _imagenEntorno == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Faltan datos o fotos')));
      return;
    }

    setState(() {
      _subiendo = true;
      _estadoSubida = "Iniciando proceso...";
    });

    try {
      final now = DateTime.now();

      // Formateo de nombres y carpetas según requerimiento
      final dayFolder = DateFormat('dd-MM-yyyy').format(now);
      final timestamp = DateFormat('ddMMyyyyHHmmss').format(now);
      final patenteValue = _patenteController.text.toUpperCase().replaceAll(' ', '');

      // ID único de la infracción para Firebase
      final idInfraccion = FirebaseFirestore.instance.collection('infracciones').doc().id;

      // Ruta de almacenamiento: infracciones / localidad_id / dia / (archivos sueltos aquí)
      final storagePath = "infracciones/${widget.localidadId}/$dayFolder";

      // 1. Subir Foto Patente
      setState(() => _estadoSubida = "Subiendo foto de patente...");
      final nameFotoPatente = "${timestamp}_${idInfraccion}_foto_patente_$patenteValue.jpg";
      final refP = FirebaseStorage.instance.ref().child("$storagePath/$nameFotoPatente");
      await refP.putFile(File(_imagenPatente!.path));
      final urlP = await refP.getDownloadURL();

      // 2. Subir Foto Entorno
      setState(() => _estadoSubida = "Subiendo foto de entorno...");
      final nameFotoEntorno = "${timestamp}_${idInfraccion}_foto_entorno_$patenteValue.jpg";
      final refE = FirebaseStorage.instance.ref().child("$storagePath/$nameFotoEntorno");
      await refE.putFile(File(_imagenEntorno!.path));
      final urlE = await refE.getDownloadURL();

      // Preparar datos para el archivo .txt y Firestore
      final Map<String, dynamic> datos = {
        'infraccion_id': idInfraccion,
        'localidad_id': widget.localidadId,
        'patente': patenteValue,
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

      // 3. Subir Archivo de Datos (.txt)
      setState(() => _estadoSubida = "Generando archivo de datos...");
      String txtContent = const JsonEncoder.withIndent('  ').convert(datos);
      final nameArchivoDato = "${timestamp}_${idInfraccion}_dato_$patenteValue.txt";
      final refTxt = FirebaseStorage.instance.ref().child("$storagePath/$nameArchivoDato");
      await refTxt.putString(txtContent, format: PutStringFormat.raw, metadata: SettableMetadata(contentType: 'text/plain'));
      final urlTxt = await refTxt.getDownloadURL();

      // 4. Registrar en Firestore (Base de Datos)
      setState(() => _estadoSubida = "Finalizando registro en base de datos...");
      await FirebaseFirestore.instance.collection('infracciones').doc(idInfraccion).set({
        ...datos,
        'foto_patente_url': urlP,
        'foto_entorno_url': urlE,
        'txt_url': urlTxt,
        'nombre_archivo_patente': nameFotoPatente,
        'nombre_archivo_entorno': nameFotoEntorno,
        'nombre_archivo_dato': nameArchivoDato,
        'fecha': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Registro exitoso')));

      // Limpiar formulario al finalizar
      _formKey.currentState!.reset();
      setState(() {
        _imagenPatente = null;
        _imagenEntorno = null;
        _ubicacionGps = "No obtenida";
        _patenteController.clear();
        _marcaController.clear();
        _modeloController.clear();
        _calleController.clear();
        _numeroController.clear();
        _tipoInfraccionController.clear();
        _observacionesController.clear();
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _subiendo = false);
    }
  }

  Widget _buildAutocompleteField({
    required TextEditingController controller,
    required String label,
    required List<String> options,
    Function(String)? onChanged,
    IconData? icon,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Autocomplete<String>(
      optionsBuilder: (TextEditingValue textEditingValue) {
        if (textEditingValue.text.isEmpty) return options;
        return options.where((String option) => option.contains(textEditingValue.text.toUpperCase()));
      },
      onSelected: (String selection) {
        controller.text = selection;
        if (onChanged != null) onChanged(selection);
      },
      fieldViewBuilder: (context, textController, focusNode, onFieldSubmitted) {
        if (controller.text != textController.text) textController.text = controller.text;
        return TextFormField(
          controller: textController,
          focusNode: focusNode,
          inputFormatters: [UpperCaseTextFormatter()],
          decoration: InputDecoration(
            labelText: label,
            filled: true,
            fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
            prefixIcon: icon != null ? Icon(icon) : null,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: isDark ? Colors.white24 : Colors.grey[300] ?? Colors.grey)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: isDark ? Colors.white24 : Colors.grey[300] ?? Colors.grey)),
          ),
          onChanged: (value) {
            controller.text = value.toUpperCase();
            if (onChanged != null) onChanged(value.toUpperCase());
          },
          validator: (v) => v!.isEmpty ? 'Requerido' : null,
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: MediaQuery.of(context).size.width * 0.85,
              constraints: const BoxConstraints(maxHeight: 250),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final String option = options.elementAt(index);
                  return ListTile(
                    title: Text(option, style: const TextStyle(fontSize: 13)),
                    onTap: () => onSelected(option),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    List<String> modelosDisponibles = [];
    if (_marcaController.text.isNotEmpty && _vehiculosSugeridos.containsKey(_marcaController.text)) {
      modelosDisponibles = _vehiculosSugeridos[_marcaController.text]!;
    }

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
          onPressed: _subiendo ? null : widget.onThemeToggle,
        ),
        actions: [IconButton(onPressed: _subiendo ? null : _logout, icon: const Icon(Icons.logout))],
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Form(
              key: _formKey,
              child: Column(children: [
                _buildField(_patenteController, 'Patente', Icons.directions_car),
                const SizedBox(height: 16),
                Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _buildAutocompleteField(controller: _marcaController, label: 'Marca', options: _vehiculosSugeridos.keys.toList(), onChanged: (val) => setState(() {}), icon: Icons.factory)),
                      const SizedBox(width: 16),
                      Expanded(child: _buildAutocompleteField(controller: _modeloController, label: 'Modelo', options: modelosDisponibles, icon: Icons.category)),
                    ]),
                const SizedBox(height: 24),
                _buildField(_calleController, 'Calle/Ruta', Icons.map),
                const SizedBox(height: 16),
                _buildField(_numeroController, 'Nro/Km', Icons.numbers, type: TextInputType.number),
                const SizedBox(height: 24),
                Row(children: [
                  Expanded(child: _buildImageCard('Foto Patente', _imagenPatente, () => _pickImage(true))),
                  const SizedBox(width: 16),
                  Expanded(child: _buildImageCard('Foto Entorno', _imagenEntorno, () => _pickImage(false))),
                ]),
                const SizedBox(height: 24),
                _buildAutocompleteField(controller: _tipoInfraccionController, label: 'Tipo de Infracción', options: _infraccionesSugeridas, icon: Icons.report_problem),
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
                  child: _subiendo ? const SizedBox.shrink() : const Text('REGISTRAR INFRACCIÓN'),
                ),
              ]),
            ),
          ),

          if (_subiendo) ...[
            const ModalBarrier(dismissible: false, color: Colors.black54),
            Center(
              child: Container(
                padding: const EdgeInsets.all(24),
                margin: const EdgeInsets.symmetric(horizontal: 40),
                decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF00162A) : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, spreadRadius: 2)]
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 24),
                    Text(
                        _estadoSubida,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)
                    ),
                    const SizedBox(height: 8),
                    const Text("Por favor, no cierre la aplicación", style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildField(TextEditingController controller, String label, IconData? icon, {TextInputType type = TextInputType.text, int maxLines = 1}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TextFormField(
      controller: controller,
      keyboardType: type,
      maxLines: maxLines,
      enabled: !_subiendo,
      inputFormatters: [UpperCaseTextFormatter()],
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
        prefixIcon: icon != null ? Icon(icon) : null,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: isDark ? Colors.white24 : Colors.grey[300] ?? Colors.grey)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: isDark ? Colors.white24 : Colors.grey[300] ?? Colors.grey)),
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
        onTap: _subiendo ? null : onTap,
        child: Container(
          height: 130,
          width: double.infinity,
          decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
              border: Border.all(color: isDark ? Colors.white24 : Colors.grey[300] ?? Colors.grey),
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