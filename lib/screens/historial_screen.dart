import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'dart:io';

class HistorialScreen extends StatefulWidget {
  final String localidadId;
  const HistorialScreen({super.key, required this.localidadId});

  @override
  State<HistorialScreen> createState() => _HistorialScreenState();
}

class _HistorialScreenState extends State<HistorialScreen> {
  static const Color naranjaXsim = Color(0xFFFF8C00);

  BluetoothDevice? _selectedDevice;
  bool _isScanning = false;
  bool _isConnected = false;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";

  @override
  void dispose() {
    _searchController.dispose();
    _connectionSubscription?.cancel();
    super.dispose();
  }

  // --- SINCRONIZACIÓN MASIVA ---
  Future<void> _sincronizarTodo() async {
    final query = await FirebaseFirestore.instance
        .collection('infracciones')
        .where('localidad_id', isEqualTo: widget.localidadId)
        .where('fotos_subidas', isEqualTo: false)
        .get();

    if (query.docs.isEmpty) {
      if (!mounted) return;
      _mostrarSnackBar("No hay fotos pendientes", Colors.blue);
      return;
    }

    if (!mounted) return;
    _mostrarSnackBar("Sincronizando ${query.docs.length} actas...", naranjaXsim);

    for (var doc in query.docs) {
      if (!mounted) break;
      await _subirFotosPendientes(doc.data(), doc.id, silencioso: true);
    }

    if (!mounted) return;
    _mostrarSnackBar("Sincronización finalizada", Colors.green);
  }

  // --- VER DETALLE (CAMPO REGISTRADO POR AGREGADO) ---
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
                      _itemDetalle(Icons.badge, "PATENTE", data['patente'] ?? 'N/A'),
                      _itemDetalle(Icons.branding_watermark, "MARCA", data['marca'] ?? 'N/A'),
                      _itemDetalle(Icons.directions_car, "MODELO", data['modelo'] ?? 'N/A'),
                      _itemDetalle(Icons.map, "CALLE/RUTA", data['calle_ruta'] ?? 'N/A'),
                      _itemDetalle(Icons.location_on, "NRO/KM", data['numero_km'] ?? 'N/A'),
                      _itemDetalle(Icons.warning_amber_rounded, "INFRACCION", data['tipo_infraccion'] ?? 'N/A'),
                      _itemDetalle(Icons.comment, "OBSERVACIONES", data['observaciones'] ?? '-'),

                      // CAMPO RECUPERADO
                      _itemDetalle(Icons.person, "REGISTRADO POR", data['registrado_por'] ?? 'S/D'),

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

  Widget _itemDetalle(IconData icono, String titulo, String? valor) {
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
                Text(valor == null || valor.isEmpty ? "N/A" : valor.toUpperCase(),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- SUBIDA DE FOTOS ---
  Future<void> _subirFotosPendientes(Map<String, dynamic> data, String docId, {bool silencioso = false}) async {
    try {
      if (data['ruta_local_patente'] == null) return;
      File fotoP = File(data['ruta_local_patente']);
      File fotoE = File(data['ruta_local_entorno']);
      if (!await fotoP.exists()) return;

      final dayFolder = data['fecha_carpeta'] ?? DateFormat('dd-MM-yyyy').format(DateTime.now());
      final storagePath = "infracciones/${widget.localidadId}/$dayFolder";

      final refP = FirebaseStorage.instance.ref().child("$storagePath/${data['nombre_archivo_patente']}");
      await refP.putFile(fotoP);
      String urlP = await refP.getDownloadURL();

      final refE = FirebaseStorage.instance.ref().child("$storagePath/${data['nombre_archivo_entorno']}");
      await refE.putFile(fotoE);
      String urlE = await refE.getDownloadURL();

      if (!mounted) return;

      await FirebaseFirestore.instance.collection('infracciones').doc(docId).update({
        'fotos_subidas': true,
        'foto_patente_url': urlP,
        'foto_entorno_url': urlE,
      });

      if (!silencioso && mounted) {
        _mostrarSnackBar("Fotos sincronizadas", Colors.green);
      }
    } catch (e) {
      if (!silencioso && mounted) {
        _mostrarSnackBar("Error al sincronizar fotos", Colors.red);
      }
    }
  }

  void _mostrarSnackBar(String mensaje, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensaje), backgroundColor: color, duration: const Duration(seconds: 2)),
    );
  }

  // --- IMPRESIÓN ---
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
        bytes += generator.text('Lugar: ${data['calle_ruta']} ${data['numero_km']}');
        bytes += generator.text('Falta: ${data['tipo_infraccion']}');
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
        if (mounted) _mostrarSnackBar("Error de impresión", Colors.red);
      }
    } else {
      if (mounted) _showBluetoothDialog(data, docId: docId);
    }
  }

  void _showBluetoothDialog(Map<String, dynamic> data, {String? docId}) {
    if (!_isScanning) {
      FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));
      _isScanning = true;
    }
    showDialog(
      context: context,
      builder: (context) {
        final dialogNavigator = Navigator.of(context);
        return AlertDialog(
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
                          if (!mounted) return;
                          setState(() { _selectedDevice = device; _isConnected = true; });
                          dialogNavigator.pop();
                          if (data.isNotEmpty) _printTicket(data, docId: docId);
                        } catch (e) {
                          if (mounted) _mostrarSnackBar("Error al conectar", Colors.red);
                        }
                      },
                    );
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Historial Infracciones'),
        actions: [
          IconButton(
            icon: const Icon(Icons.cloud_sync, color: naranjaXsim, size: 28),
            onPressed: _sincronizarTodo,
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
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: const BorderSide(color: naranjaXsim, width: 2.0),
                ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(30)),
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
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

                var filteredDocs = snapshot.data!.docs.where((doc) {
                  var patente = (doc['patente'] ?? "").toString().toUpperCase();
                  return patente.contains(_searchQuery);
                }).toList();

                return ListView.builder(
                  itemCount: filteredDocs.length,
                  itemBuilder: (context, index) {
                    var doc = filteredDocs[index];
                    var data = doc.data() as Map<String, dynamic>;
                    bool isSincronizado = !doc.metadata.hasPendingWrites;

                    String fechaTarjeta = 'S/F';
                    if (data['fecha'] != null) {
                      fechaTarjeta = DateFormat('dd-MM-yyyy HH:mm').format((data['fecha'] as Timestamp).toDate());
                    }

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(15),
                        onTap: () => _verDetalleInfraccion(data, doc.id),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(data['patente'] ?? 'S/P',
                                        style: const TextStyle(color: naranjaXsim, fontSize: 18, fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 2),
                                    Text(data['tipo_infraccion'] ?? '',
                                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                                        maxLines: 1, overflow: TextOverflow.ellipsis),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        const Icon(Icons.access_time, size: 12, color: Colors.grey),
                                        const SizedBox(width: 4),
                                        Text(fechaTarjeta, style: const TextStyle(fontSize: 14, color: Colors.grey)),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    isSincronizado ? Icons.check_circle : Icons.access_time_filled,
                                    color: isSincronizado ? Colors.green : Colors.orange,
                                    size: 22,
                                  ),
                                  const SizedBox(height: 8),
                                  if (data['fotos_subidas'] == false)
                                    IconButton(
                                      constraints: const BoxConstraints(),
                                      padding: EdgeInsets.zero,
                                      icon: const Icon(Icons.cloud_upload, color: Colors.redAccent, size: 24),
                                      onPressed: () => _subirFotosPendientes(data, doc.id),
                                    )
                                  else
                                    const Icon(Icons.cloud_done, color: Colors.blue, size: 20),
                                ],
                              ),
                            ],
                          ),
                        ),
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