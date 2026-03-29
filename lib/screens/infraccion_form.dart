import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:xsim/services/deteccion_service.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:firebase_auth/firebase_auth.dart';

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

  @override
  void initState() {
    super.initState();
    _patenteController.addListener(_onPatenteChanged);
  }

  void _onPatenteChanged() {
    if (_patenteController.text.isEmpty && _patenteDetectadaExito) {
      setState(() => _patenteDetectadaExito = false);
    }
  }

  @override
  void dispose() {
    _deteccionService.dispose();
    _patenteController.removeListener(_onPatenteChanged);
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
      
      if (permission == LocationPermission.deniedForever) return;

      if (actualizarDireccion) {
        setState(() {
          _ubicacionGps = "Obteniendo...";
          _calleController.text = "Buscando...";
          _numeroController.text = "";
        });
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.bestForNavigation, 
        timeLimit: const Duration(seconds: 15),
      );
      
      if (!mounted) return;
      setState(() => _ubicacionGps = "${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}");

      if (actualizarDireccion) {
        try {
          List<Placemark> placemarks = await placemarkFromCoordinates(position.latitude, position.longitude);
          if (placemarks.isNotEmpty) {
            Placemark place = placemarks[0];
            setState(() {
              _calleController.text = place.thoroughfare ?? "";
              _numeroController.text = place.subThoroughfare ?? "";
            });
          }
        } catch (e) {
          if (mounted) _calleController.clear();
          debugPrint("Error en Geocoding: $e");
        }
      }

    } catch (e) {
      if (mounted) {
        setState(() => _ubicacionGps = "Error al obtener");
        if (actualizarDireccion) _calleController.clear();
      }
      debugPrint("Error GPS: $e");
    }
  }

  Future<void> _pickImage(bool isPatente) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.camera, 
        imageQuality: 60,
      );
      
      if (image != null) {
        if (isPatente) {
          setState(() {
            _imagenPatente = image;
            _calleController.clear();
            _numeroController.clear();
          });
          _obtenerUbicacion(actualizarDireccion: true);
          _ejecutarDeteccionPro(image.path);
        } else {
          setState(() {
            _imagenEntorno = image;
          });
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al abrir la cámara: $e')),
      );
    }
  }

  Future<void> _ejecutarDeteccionPro(String path) async {
    setState(() {
       _estadoSubida = "Analizando vehículo...";
       _patenteDetectadaExito = false;
    });
    try {
      final resultados = await _deteccionService.procesarYDeteccionDual(path);
      if (!mounted) return;
      setState(() {
        if (resultados['patente'] != null && resultados['patente']!.isNotEmpty) {
          _patenteController.text = resultados['patente']!;
          _patenteDetectadaExito = true;
        }
        if (resultados['marca'] != null && resultados['marca']!.isNotEmpty) {
          _marcaController.text = resultados['marca']!;
        }
        if (resultados['modelo'] != null && resultados['modelo']!.isNotEmpty) {
          _modeloController.text = resultados['modelo']!;
        }
      });
    } catch (e) {
      debugPrint("Error en detección: $e");
    } finally {
      if (mounted) setState(() => _estadoSubida = "");
    }
  }

  Future<void> _registrarInfraccion() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() {
      _subiendo = true;
      _estadoSubida = "Guardando infracción...";
    });

    try {
      await FirebaseFirestore.instance.collection('infracciones').add({
        'localidad_id': widget.localidadId,
        'fecha': FieldValue.serverTimestamp(),
        'registrado_por': widget.userName,
        'patente': _patenteController.text.toUpperCase(),
        'marca': _marcaController.text.toUpperCase(),
        'modelo': _modeloController.text.toUpperCase(),
        'ubicacion': {
          'calle_ruta': _calleController.text.toUpperCase(),
          'numero_km': _numeroController.text.toUpperCase(),
        },
        'tipo_infraccion': _tipoInfraccionController.text.toUpperCase(),
        'observaciones': _observacionesController.text.toUpperCase(),
        'ubicacion_gps': _ubicacionGps,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Infracción registrada correctamente')),
      );

      _patenteController.clear();
      _marcaController.clear();
      _modeloController.clear();
      _calleController.clear();
      _numeroController.clear();
      _tipoInfraccionController.clear();
      _observacionesController.clear();
      setState(() {
        _imagenPatente = null;
        _imagenEntorno = null;
        _ubicacionGps = "No obtenida";
        _patenteDetectadaExito = false;
      });

    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al registrar: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _subiendo = false;
          _estadoSubida = "";
        });
      }
    }
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: naranjaXsim,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            height: 1.5,
            width: 40, // Línea corta y fina
            color: naranjaXsim,
          ),
        ],
      ),
    );
  }

  Widget _buildField(TextEditingController controller, String label, IconData? icon, {TextInputType type = TextInputType.text, Widget? suffixIcon}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TextFormField(
      controller: controller,
      keyboardType: type,
      inputFormatters: [UpperCaseTextFormatter()],
      style: const TextStyle(fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
          color: isDark ? Colors.white60 : Colors.black54, // TEXTO MÁS BRILLANTE EN DARK MODE
          fontWeight: FontWeight.normal,
        ),
        filled: true,
        fillColor: isDark ? Colors.white10 : Colors.grey[100],
        prefixIcon: icon != null ? Icon(icon, color: isDark ? Colors.white70 : Colors.black45) : null,
        suffixIcon: suffixIcon,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: naranjaXsim, width: 1.5),
        ),
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
          controller: fieldCtrl,
          focusNode: node,
          inputFormatters: [UpperCaseTextFormatter()],
          style: const TextStyle(fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            labelText: label,
            labelStyle: TextStyle(
              color: isDark ? Colors.white60 : Colors.black54, // TEXTO MÁS BRILLANTE EN DARK MODE
            ),
            filled: true,
            fillColor: isDark ? Colors.white10 : Colors.grey[100],
            prefixIcon: icon != null ? Icon(icon, color: isDark ? Colors.white70 : Colors.black45) : null,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: naranjaXsim, width: 1.5),
            ),
          ),
          onChanged: (v) => controller.text = v.toUpperCase(),
          validator: (v) => v!.isEmpty ? 'Requerido' : null,
        );
      },
    );
  }

  Widget _buildImageCard(String label, XFile? image, VoidCallback onTap, VoidCallback onClear) {
    return Column(children: [
      Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      Stack(
        children: [
          InkWell(
            onTap: image == null ? onTap : null, 
            child: Container(
              height: 120, width: double.infinity,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey), 
                borderRadius: BorderRadius.circular(12),
                color: Theme.of(context).brightness == Brightness.dark ? Colors.white10 : Colors.grey[50],
              ),
              child: image == null 
                  ? const Icon(Icons.add_a_photo, size: 40) 
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(12), 
                      child: Image.file(File(image.path), fit: BoxFit.cover)
                    ),
            ),
          ),
          if (image != null)
            Positioned(
              top: 5,
              right: 5,
              child: InkWell(
                onTap: onClear,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, color: Colors.white, size: 18),
                ),
              ),
            ),
        ],
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
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

    List<String> modelos = (_marcaController.text.isNotEmpty && vehiculosSugeridos.containsKey(_marcaController.text))
        ? vehiculosSugeridos[_marcaController.text]! : [];

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.localidadId, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: naranjaXsim)),
            Text(widget.userName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal, color: naranjaXsim)),
          ],
        ),
        actions: [
          IconButton(onPressed: widget.onThemeToggle, icon: const Icon(Icons.brightness_4)),
          IconButton(onPressed: _logout, icon: const Icon(Icons.logout))
        ],
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              child: Column(children: [
                Row(children: [
                  Expanded(child: _buildImageCard(
                    'Foto Patente', 
                    _imagenPatente, 
                    () => _pickImage(true),
                    () => setState(() {
                      _imagenPatente = null;
                      _patenteDetectadaExito = false;
                    })
                  )),
                  const SizedBox(width: 10),
                  Expanded(child: _buildImageCard(
                    'Foto Entorno', 
                    _imagenEntorno, 
                    () => _pickImage(false),
                    () => setState(() => _imagenEntorno = null)
                  )),
                ]),
                
                _buildSectionTitle('Vehículo'),
                _buildField(
                  _patenteController, 
                  'Patente', 
                  Icons.directions_car,
                  suffixIcon: _patenteDetectadaExito 
                      ? const Icon(Icons.check_circle, color: Colors.green) 
                      : null,
                ),
                const SizedBox(height: 15),
                Row(children: [
                  Expanded(child: _buildAutocompleteField(controller: _marcaController, label: 'Marca', options: vehiculosSugeridos.keys.toList())),
                  const SizedBox(width: 10),
                  Expanded(child: _buildAutocompleteField(controller: _modeloController, label: 'Modelo', options: modelos)),
                ]),

                _buildSectionTitle('Ubicación'),
                _buildField(
                  _calleController, 
                  'Calle / Ruta', 
                  Icons.map,
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.my_location, color: naranjaXsim),
                    onPressed: () => _obtenerUbicacion(actualizarDireccion: true),
                  )
                ),
                const SizedBox(height: 15),
                _buildField(_numeroController, 'Nro / Km', Icons.location_on, type: TextInputType.number),

                _buildSectionTitle('Infracción'),
                _buildAutocompleteField(controller: _tipoInfraccionController, label: 'Tipo de Infracción', options: infraccionesSugeridas, icon: Icons.warning),
                const SizedBox(height: 15),
                TextFormField(
                  controller: _observacionesController,
                  maxLines: 3,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                  decoration: InputDecoration(
                    labelText: 'Observaciones',
                    labelStyle: TextStyle(
                      color: isDark ? Colors.white60 : Colors.black54,
                    ),
                    filled: true,
                    fillColor: isDark ? Colors.white10 : Colors.grey[100],
                    prefixIcon: const Icon(Icons.edit_note),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: naranjaXsim, width: 1.5),
                    ),
                  ),
                ),
                
                const SizedBox(height: 40), 
                
                ElevatedButton(
                  onPressed: _subiendo ? null : _registrarInfraccion,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: naranjaXsim, 
                    foregroundColor: Colors.white, 
                    minimumSize: const Size(double.infinity, 60), 
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    elevation: 5,
                  ),
                  child: _subiendo 
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) 
                      : const Text('REGISTRAR INFRACCIÓN', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                ),
                const SizedBox(height: 40),
              ]),
            ),
          ),
          if (_estadoSubida.isNotEmpty)
            Container(
              color: Colors.black87, 
              child: Center(child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: Colors.white),
                  const SizedBox(height: 20),
                  Text(_estadoSubida, style: const TextStyle(color: Colors.white, fontSize: 18, decoration: TextDecoration.none)),
                ],
              )),
            ),
        ],
      ),
    );
  }
}

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue old, TextEditingValue newVal) =>
      TextEditingValue(text: newVal.text.toUpperCase(), selection: newVal.selection);
}
