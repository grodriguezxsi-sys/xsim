import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';

class PrinterService {
  // Genera los bytes del ticket con el formato de CECAITRA
  static Future<List<int>> generateTicket(Map<String, dynamic> data) async {
    final profile = await CapabilityProfile.load();
    final generator = Generator(PaperSize.mm58, profile);
    List<int> bytes = [];

    bytes += generator.text('XSIM - ACTA DE INFRACCION',
        styles: const PosStyles(align: PosAlign.center, bold: true));
    bytes += generator.feed(1);
    bytes += generator.text('Localidad: ${data['localidad_id']}');
    bytes += generator.text('Fecha: ${data['fecha_hora']?.toString().substring(0, 16)}');
    bytes += generator.text('Inspector: ${data['registrado_por']}');
    bytes += generator.hr();
    bytes += generator.text('VEHICULO', styles: const PosStyles(bold: true));
    bytes += generator.text('Patente: ${data['patente']}');
    bytes += generator.text('Marca: ${data['marca']}');
    bytes += generator.hr();
    bytes += generator.text('UBICACION', styles: const PosStyles(bold: true));
    bytes += generator.text('${data['ubicacion']?['calle_ruta'] ?? ''} ${data['ubicacion']?['numero_km'] ?? ''}');
    bytes += generator.feed(2);
    bytes += generator.cut();

    return bytes;
  }

  // Escanea y envía los bytes a la impresora
  static Future<void> sendToPrinter(BluetoothDevice device, List<int> bytes) async {
    try {

      List<BluetoothService> services = await device.discoverServices();
      for (var service in services) {
        for (var characteristic in service.characteristics) {
          if (characteristic.properties.write) {
            await characteristic.write(bytes, allowLongWrite: true);
          }
        }
      }
    } catch (e) {
      print("Error en printer service: $e");
      rethrow;
    }
  }
}