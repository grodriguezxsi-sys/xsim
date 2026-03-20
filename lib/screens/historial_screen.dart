import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:blue_thermal_printer/blue_thermal_printer.dart';

class HistorialScreen extends StatefulWidget {
  final String localidadId;
  const HistorialScreen({super.key, required this.localidadId});

  @override
  State<HistorialScreen> createState() => _HistorialScreenState();
}

class _HistorialScreenState extends State<HistorialScreen> {
  BlueThermalPrinter bluetooth = BlueThermalPrinter.instance;
  bool _connected = false;
  List<BluetoothDevice> _devices = [];
  BluetoothDevice? _selectedDevice;

  @override
  void initState() {
    super.initState();
    _initBluetooth();
  }

  Future<void> _initBluetooth() async {
    try {
      bool? isConnected = await bluetooth.isConnected;
      List<BluetoothDevice> devices = await bluetooth.getBondedDevices();
      setState(() {
        _devices = devices;
        _connected = isConnected ?? false;
      });
    } catch (_) {}
  }

  void _printTicket(Map<String, dynamic> data) async {
    if (_connected) {
      try {
        bluetooth.printCustom("XSIM - ACTA DE INFRACCION", 3, 1);
        bluetooth.printNewLine();
        bluetooth.printCustom("Localidad: ${data['localidad_id']}", 1, 0);
        bluetooth.printCustom("Fecha: ${data['fecha_hora']?.substring(0,16)}", 1, 0);
        bluetooth.printCustom("Inspector: ${data['registrado_por']}", 1, 0);
        bluetooth.printNewLine();
        bluetooth.printCustom("VEHICULO", 2, 1);
        bluetooth.printCustom("Patente: ${data['patente']}", 1, 0);
        bluetooth.printCustom("Marca: ${data['marca']}", 1, 0);
        bluetooth.printCustom("Modelo: ${data['modelo']}", 1, 0);
        bluetooth.printNewLine();
        bluetooth.printCustom("INFRACCION", 2, 1);
        bluetooth.printCustom(data['tipo_infraccion'], 1, 0);
        bluetooth.printNewLine();
        bluetooth.printCustom("UBICACION", 2, 1);
        bluetooth.printCustom("${data['ubicacion']?['calle_ruta']} ${data['ubicacion']?['numero_km']}", 1, 0);
        bluetooth.printNewLine();
        bluetooth.printCustom("Firma Inspector", 1, 1);
        bluetooth.printNewLine();
        bluetooth.printNewLine();
        bluetooth.paperCut();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Imprimiendo...')));
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al imprimir: $e')));
      }
    } else {
      _showBluetoothDialog(data);
    }
  }

  void _showBluetoothDialog(Map<String, dynamic> data) {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text("Conectar Impresora"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButton<BluetoothDevice>(
                isExpanded: true,
                value: _selectedDevice,
                items: _devices.map((d) => DropdownMenuItem(value: d, child: Text(d.name ?? ""))).toList(),
                onChanged: (d) => setDialogState(() => _selectedDevice = d),
                hint: const Text("Seleccionar dispositivo"),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _selectedDevice == null ? null : () async {
                  try {
                    await bluetooth.connect(_selectedDevice!);
                    setDialogState(() => _connected = true);
                    setState(() => _connected = true);
                    if (mounted) Navigator.pop(context);
                    _printTicket(data);
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
                  }
                },
                child: const Text("Conectar e Imprimir"),
              )
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Historial'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(_connected ? Icons.bluetooth_connected : Icons.bluetooth_disabled, color: _connected ? Colors.blue : null),
            onPressed: _initBluetooth,
          )
        ],
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
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.receipt_long)),
                  title: Text('Patente: ${data['patente'] ?? 'S/P'}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('Fecha: ${data['fecha'] != null ? (data['fecha'] as Timestamp).toDate().toString().substring(0, 16) : 'S/F'}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.print, color: Colors.blue),
                    onPressed: () => _printTicket(data),
                  ),
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
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
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
                  IconButton(
                    icon: const Icon(Icons.print, size: 30, color: Colors.blue),
                    onPressed: () {
                      Navigator.pop(context);
                      _printTicket(data);
                    },
                  )
                ],
              ),
              const Divider(height: 32, color: Colors.white24),
              _detalleItem('ID Infracción', data['infraccion_id'], isDark),
              _detalleItem('Patente', data['patente'], isDark),
              _detalleItem('Marca', data['marca'], isDark),
              _detalleItem('Modelo', data['modelo'], isDark),
              _detalleItem('Infracción', data['tipo_infraccion'], isDark),
              _detalleItem('Calle / Ruta', data['ubicacion']?['calle_ruta'], isDark),
              _detalleItem('Nro / KM', data['ubicacion']?['numero_km'], isDark),
              _detalleItem('Coordenadas GPS', data['ubicacion']?['gps'], isDark),
              _detalleItem('Registrado por', data['registrado_por'], isDark),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detalleItem(String label, dynamic value, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: isDark ? Colors.white54 : Colors.black54, fontSize: 12)),
          Text(value?.toString() ?? 'N/A', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
