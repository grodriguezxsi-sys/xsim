import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'dart:async';

class HistorialScreen extends StatefulWidget {
  final String localidadId;
  const HistorialScreen({super.key, required this.localidadId});

  @override
  State<HistorialScreen> createState() => _HistorialScreenState();
}

class _HistorialScreenState extends State<HistorialScreen> {
  static const Color naranjaXsim = Color(0xFFFF8C00); 
  List<ScanResult> _scanResults = [];
  BluetoothDevice? _selectedDevice;
  bool _isScanning = false;
  bool _isConnected = false;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;
  
  // Controlador para el buscador
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";

  @override
  void initState() {
    super.initState();
    _initBluetooth();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _connectionSubscription?.cancel();
    super.dispose();
  }

  void _initBluetooth() {
    FlutterBluePlus.adapterState.listen((state) {
      if (mounted) setState(() {});
    });
  }

  void _monitorConnection(BluetoothDevice device) {
    _connectionSubscription?.cancel();
    _connectionSubscription = device.connectionState.listen((state) {
      if (mounted) {
        setState(() {
          _isConnected = state == BluetoothConnectionState.connected;
          if (!_isConnected) _selectedDevice = null;
        });
      }
    });
  }

  // Generador de Ticket Profesional para XSIM
  Future<List<int>> _generateTicketBytes(Map<String, dynamic> data, {String? docId}) async {
    final profile = await CapabilityProfile.load();
    final generator = Generator(PaperSize.mm58, profile);
    List<int> bytes = [];

    bytes += generator.text('XSIM - ACTA DE INFRACCION',
        styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2));
    bytes += generator.feed(1);
    
    if (docId != null) {
      bytes += generator.text('ID ACTA: $docId', styles: const PosStyles(bold: true));
    }
    
    bytes += generator.text('Localidad: ${data['localidad_id'] ?? 'N/A'}');
    bytes += generator.text('Fecha: ${data['fecha'] != null ? (data['fecha'] as Timestamp).toDate().toString().substring(0, 16) : 'S/F'}');
    bytes += generator.hr();
    
    bytes += generator.text('VEHICULO', styles: const PosStyles(bold: true));
    bytes += generator.text('Patente: ${data['patente'] ?? 'S/P'}');
    bytes += generator.text('Marca: ${data['marca'] ?? '-'}');
    bytes += generator.text('Modelo: ${data['modelo'] ?? '-'}');
    bytes += generator.hr();
    
    bytes += generator.text('UBICACION', styles: const PosStyles(bold: true));
    bytes += generator.text('Calle: ${data['ubicacion']?['calle_ruta'] ?? ''}');
    bytes += generator.text('Nro/Km: ${data['ubicacion']?['numero_km'] ?? ''}');
    bytes += generator.text('GPS: ${data['ubicacion_gps'] ?? 'N/A'}');
    bytes += generator.hr();
    
    bytes += generator.text('INFRACCION', styles: const PosStyles(bold: true));
    bytes += generator.text(data['tipo_infraccion'] ?? 'No especificada');
    bytes += generator.feed(1);
    
    bytes += generator.text('Registrado por: ${data['registrado_por'] ?? 'N/A'}');
    
    bytes += generator.feed(2);
    bytes += generator.text('--------------------------------', styles: const PosStyles(align: PosAlign.center));
    bytes += generator.text('Firma Inspector', styles: const PosStyles(align: PosAlign.center));
    bytes += generator.feed(3);
    bytes += generator.cut();

    return bytes;
  }

  void _printTicket(Map<String, dynamic> data, {String? docId}) async {
    if (_selectedDevice != null && _isConnected) {
      try {
        final bytes = await _generateTicketBytes(data, docId: docId);

        List<BluetoothService> services = await _selectedDevice!.discoverServices();
        for (var service in services) {
          for (var characteristic in service.characteristics) {
            if (characteristic.properties.write) {
              await characteristic.write(bytes, allowLongWrite: true);
            }
          }
        }
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Imprimiendo ticket...')));
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error de conexión: $e')));
      }
    } else {
      _showBluetoothDialog(data, docId: docId);
    }
  }

  void _showBluetoothDialog(Map<String, dynamic> data, {String? docId}) {
    if (!_isScanning) {
      FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));
      _isScanning = true;
    }

    FlutterBluePlus.scanResults.listen((results) {
      if (mounted) setState(() => _scanResults = results);
    });

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text("Seleccionar Impresora"),
          content: SizedBox(
            width: double.maxFinite,
            height: 250,
            child: ListView.builder(
              itemCount: _scanResults.length,
              itemBuilder: (context, i) {
                final device = _scanResults[i].device;
                return ListTile(
                  leading: const Icon(Icons.print),
                  title: Text(device.platformName.isEmpty ? "Impresora Genérica" : device.platformName),
                  subtitle: Text(device.remoteId.toString()),
                  onTap: () async {
                    try {
                      await device.connect();
                      setState(() {
                        _selectedDevice = device;
                        _isConnected = true;
                      });
                      _monitorConnection(device);
                      Navigator.pop(context);
                      if (data.isNotEmpty) _printTicket(data, docId: docId);
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al conectar: $e')));
                    }
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
                onPressed: () {
                  _isScanning = false;
                  Navigator.pop(context);
                },
                child: const Text("Cerrar")
            )
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Historial Infracciones'),
        centerTitle: true,
        actions: [
          IconButton(
            padding: const EdgeInsets.only(right: 12), // Padding derecho para el icono de la barra
            icon: Icon(
              _isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
              color: _isConnected ? Colors.green : Colors.red,
            ),
            onPressed: () => _showBluetoothDialog({}),
          )
        ],
      ),
      body: Column(
        children: [
          // BARRA DE BÚSQUEDA MEJORADA CON BORDES DINÁMICOS
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Buscar por patente...',
                prefixIcon: const Icon(Icons.search, color: naranjaXsim),
                suffixIcon: _searchQuery.isNotEmpty 
                  ? IconButton(
                      icon: const Icon(Icons.clear), 
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = "");
                      }
                    ) 
                  : null,
                filled: true,
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.3), width: 1),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: const BorderSide(color: naranjaXsim, width: 1.5),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              ),
              onChanged: (value) {
                setState(() => _searchQuery = value.toUpperCase());
              },
            ),
          ),
          
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('infracciones')
                  .where('localidad_id', isEqualTo: widget.localidadId)
                  .orderBy('fecha', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                if (snapshot.data!.docs.isEmpty) return const Center(child: Text('No hay multas registradas'));

                var filteredDocs = snapshot.data!.docs.where((doc) {
                  var data = doc.data() as Map<String, dynamic>;
                  var patente = (data['patente'] ?? "").toString().toUpperCase();
                  return patente.contains(_searchQuery);
                }).toList();

                if (filteredDocs.isEmpty) return const Center(child: Text('No se encontraron patentes coincidentes'));

                return ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: filteredDocs.length,
                  separatorBuilder: (context, index) => const Divider(height: 1, indent: 16),
                  itemBuilder: (context, index) {
                    var doc = filteredDocs[index];
                    var data = doc.data() as Map<String, dynamic>;
                    bool isSincronizado = !doc.metadata.hasPendingWrites;

                    return ListTile(
                      contentPadding: const EdgeInsets.fromLTRB(16, 8, 8, 8), // Más espacio a la izquierda, menos a la derecha para equilibrar
                      title: Row(
                        children: [
                          Expanded(
                            child: RichText(
                              text: TextSpan(
                                text: 'Patente: ',
                                style: TextStyle(
                                  color: Theme.of(context).brightness == Brightness.dark ? Colors.white70 : Colors.black54,
                                  fontWeight: FontWeight.normal,
                                  fontSize: 14
                                ),
                                children: [
                                  TextSpan(
                                    text: data['patente'] ?? 'S/P',
                                    style: const TextStyle(
                                      color: naranjaXsim,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(right: 8.0), // Padding derecho para el check verde/naranja
                            child: Icon(
                              isSincronizado ? Icons.check_circle : Icons.access_time_filled,
                              color: isSincronizado ? Colors.green : Colors.orange,
                              size: 18,
                            ),
                          ),
                        ],
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Fecha: ${data['fecha'] != null ? (data['fecha'] as Timestamp).toDate().toString().substring(0, 16) : 'S/F'}',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      trailing: Padding(
                        padding: const EdgeInsets.only(right: 4.0), // Padding derecho para el botón de impresión
                        child: IconButton(
                          icon: const Icon(Icons.print, color: Colors.blue, size: 24),
                          onPressed: () => _printTicket(data, docId: doc.id),
                        ),
                      ),
                      onTap: () => _showDetalle(context, data, doc.id),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showDetalle(BuildContext context, Map<String, dynamic> data, String docId) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF00162A) : Colors.white,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.8,
        minChildSize: 0.5,
        maxChildSize: 0.95,
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
                  const Text('Detalle de Acta', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  IconButton(
                    icon: const Icon(Icons.print, size: 30, color: Colors.blue),
                    onPressed: () {
                      Navigator.pop(context);
                      _printTicket(data, docId: docId);
                    },
                  )
                ],
              ),
              const Divider(height: 32, color: Colors.white24),
              _detalleItem('ID Infracción', docId, isDark),
              _detalleItem('Patente', data['patente'], isDark, isHighlighted: true),
              _detalleItem('Marca', data['marca'], isDark),
              _detalleItem('Modelo', data['modelo'], isDark),
              _detalleItem('Calle / Ruta', data['ubicacion']?['calle_ruta'], isDark),
              _detalleItem('Nro / Km', data['ubicacion']?['numero_km'], isDark),
              _detalleItem('Infracción', data['tipo_infraccion'], isDark),
              _detalleItem('Coordenadas GPS', data['ubicacion_gps'], isDark),
              _detalleItem('Registrado por', data['registrado_por'], isDark),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detalleItem(String label, dynamic value, bool isDark, {bool isHighlighted = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: isDark ? Colors.white54 : Colors.black54, fontSize: 12)),
          Text(
            value?.toString() ?? 'N/A', 
            style: TextStyle(
              fontSize: isHighlighted ? 20 : 16, 
              fontWeight: isHighlighted ? FontWeight.bold : FontWeight.w500,
              color: isHighlighted ? naranjaXsim : (isDark ? Colors.white : Colors.black87),
            )
          ),
        ],
      ),
    );
  }
}
