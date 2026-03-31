import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'dart:io';
import 'package:provider/provider.dart';
import '../services/connectivity_service.dart';

class HistorialScreen extends StatefulWidget {
  final String localidadId;
  final String userName;
  final VoidCallback onThemeToggle;

  const HistorialScreen({
    super.key,
    required this.localidadId,
    required this.userName,
    required this.onThemeToggle,
  });

  @override
  State<HistorialScreen> createState() => _HistorialScreenState();
}

class _HistorialScreenState extends State<HistorialScreen> with SingleTickerProviderStateMixin {
  static const Color naranjaXsim = Color(0xFFFF8C00);

  BluetoothDevice? _selectedDevice;
  bool _isScanning = false;
  bool _isConnected = false;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";
  
  late final AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _animationController.dispose();
    _searchController.dispose();
    _connectionSubscription?.cancel();
    super.dispose();
  }

  void _verDetalleInfraccion(Map<String, dynamic> data, String docId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
          ),
          child: SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(width: 50, height: 5, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.all(24.0),
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text("Detalle de Acta", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: naranjaXsim)),
                          IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                        ],
                      ),
                      const Divider(),
                      _itemDetalle(Icons.tag, "ID", docId),
                      _itemDetalle(Icons.badge, "PATENTE", data['patente']),
                      _itemDetalle(Icons.branding_watermark, "MARCA", data['marca']),
                      _itemDetalle(Icons.directions_car, "MODELO", data['modelo']),
                      _itemDetalle(Icons.map, "CALLE/RUTA", data['ubicacion']?['calle'] ?? data['calle_ruta']),
                      _itemDetalle(Icons.location_on, "NRO/KM", data['ubicacion']?['nro'] ?? data['numero_km']),
                      _itemDetalle(Icons.warning_amber_rounded, "INFRACCION", data['infraccion'] ?? data['tipo_infraccion']),
                      _itemDetalle(Icons.comment, "OBSERVACIONES", data['observaciones']),
                      _itemDetalle(Icons.person, "REGISTRADO POR", data['registrado_por']),
                      _itemDetalle(Icons.gps_fixed, "GPS", data['ubicacion']?['gps'] ?? data['ubicacion_gps']),
                      const SizedBox(height: 30),
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _printTicket(data, docId: docId);
                        },
                        icon: const Icon(Icons.print),
                        label: const Text('IMPRIMIR TICKET', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: naranjaXsim,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(double.infinity, 60),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                          elevation: 4,
                        ),
                      ),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _itemDetalle(IconData icono, String titulo, dynamic valor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, color: naranjaXsim, size: 22),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo, style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(valor?.toString() ?? "N/A", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _printTicket(Map<String, dynamic> data, {String? docId}) async {
    if (_selectedDevice != null && _isConnected) {
      try {
        final profile = await CapabilityProfile.load();
        final generator = Generator(PaperSize.mm58, profile);
        List<int> bytes = [];
        bytes += generator.text('XSIM - INFRACCION', styles: const PosStyles(align: PosAlign.center, bold: true));
        bytes += generator.text('ID: $docId');
        bytes += generator.text('Patente: ${data['patente']}', styles: const PosStyles(bold: true));
        bytes += generator.text('Vehiculo: ${data['marca']} ${data['modelo']}');
        bytes += generator.text('Lugar: ${data['ubicacion']?['calle'] ?? data['calle_ruta']}');
        bytes += generator.text('Falta: ${data['infraccion'] ?? data['tipo_infraccion']}');
        bytes += generator.text('Agente: ${data['registrado_por']}');
        bytes += generator.feed(3);
        bytes += generator.cut();

        List<BluetoothService> services = await _selectedDevice!.discoverServices();
        for (var service in services) {
          for (var characteristic in service.characteristics) {
            if (characteristic.properties.write) {
              await characteristic.write(bytes, allowLongWrite: true);
            }
          }
        }
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Error de impresión")));
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
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Seleccionar Impresora"),
        content: SizedBox(
          width: double.maxFinite,
          height: 250,
          child: StreamBuilder<List<ScanResult>>(
            stream: FlutterBluePlus.scanResults,
            builder: (ctx, snapshot) {
              final results = snapshot.data ?? [];
              return ListView.builder(
                itemCount: results.length,
                itemBuilder: (ctx, i) {
                  final device = results[i].device;
                  return ListTile(
                    leading: const Icon(Icons.print),
                    title: Text(device.platformName.isEmpty ? "Impresora" : device.platformName),
                    onTap: () async {
                      try {
                        await device.connect();
                        setState(() { _selectedDevice = device; _isConnected = true; });
                        Navigator.pop(context);
                        if (data.isNotEmpty) _printTicket(data, docId: docId);
                      } catch (_) {}
                    },
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Historial de Registros', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          // INDICADOR DE SINCRONIZACIÓN
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
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Sin conexión. Se subirá automáticamente al tener señal.'), backgroundColor: Colors.orange)
                    );
                  },
                );
              }
              return const SizedBox.shrink();
            },
          ),
          IconButton(
            icon: Icon(Icons.bluetooth, color: _isConnected ? Colors.green : Colors.red),
            onPressed: () => _showBluetoothDialog({}),
          )
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Buscar patente...',
                prefixIcon: const Icon(Icons.search, color: naranjaXsim),
                filled: true,
                fillColor: isDark ? Colors.white10 : Colors.grey[100],
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
              ),
              onChanged: (value) => setState(() => _searchQuery = value.toUpperCase()),
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
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text("No se encontraron registros"));
                
                var filteredDocs = snapshot.data!.docs.where((doc) {
                  return (doc['patente'] ?? "").toString().contains(_searchQuery);
                }).toList();

                if (filteredDocs.isEmpty) return const Center(child: Text("No coinciden patentes con la búsqueda"));

                return ListView.builder(
                  itemCount: filteredDocs.length,
                  padding: const EdgeInsets.only(bottom: 20),
                  itemBuilder: (context, index) {
                    var doc = filteredDocs[index];
                    var data = doc.data() as Map<String, dynamic>;
                    bool subido = data['fotos_subidas'] ?? false;

                    String displayDate = 'S/F';
                    try {
                      if (data['fecha'] != null && data['fecha'] is Timestamp) {
                        displayDate = DateFormat('dd-MM-yyyy HH:mm').format((data['fecha'] as Timestamp).toDate());
                      } else if (data['fecha_hora'] != null) {
                        displayDate = data['fecha_hora'].toString().substring(0, 16).replaceAll('T', ' ');
                      }
                    } catch (_) {}

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      elevation: 2,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      color: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        title: Text(data['patente'] ?? 'S/P', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: naranjaXsim)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(data['infraccion'] ?? data['tipo_infraccion'] ?? 'S/I', style: const TextStyle(fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 4),
                            Text(displayDate, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                          ],
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(subido ? Icons.cloud_done : Icons.cloud_off, color: subido ? Colors.blue : Colors.orange, size: 24),
                            const SizedBox(height: 4),
                            Text(subido ? "OK" : "Pte", style: TextStyle(fontSize: 10, color: subido ? Colors.blue : Colors.orange, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        onTap: () => _verDetalleInfraccion(data, doc.id),
                      ),
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
}
