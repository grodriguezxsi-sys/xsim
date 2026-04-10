import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

class ConfirmacionScreen extends StatelessWidget {
  final Map<String, dynamic> data;
  final XFile imagenPatente;
  final XFile imagenEntorno;
  final VoidCallback onConfirm;

  const ConfirmacionScreen({
    super.key,
    required this.data,
    required this.imagenPatente,
    required this.imagenEntorno,
    required this.onConfirm,
  });

  static const Color naranjaXsim = Color(0xFFE8952A);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // Colores según mockup
    final Color fondo = isDark ? const Color(0xFF1A1F2E) : const Color(0xFFF0F2F5);
    final Color fondoTarjeta = isDark ? const Color(0xFF222839) : Colors.white;
    final Color textoPri = isDark ? Colors.white : const Color(0xFF1A1F2E);
    final Color textoSec = isDark ? Colors.white38 : Colors.black38;

    return Scaffold(
      backgroundColor: fondo,
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF141824) : Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: naranjaXsim, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Confirmar Infracción', style: TextStyle(color: textoPri, fontSize: 18, fontWeight: FontWeight.bold)),
            Text('Revisá antes de enviar', style: TextStyle(color: textoSec, fontSize: 12)),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ALERTA NARANJA
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: naranjaXsim.withAlpha(20),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: naranjaXsim.withAlpha(100)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: naranjaXsim, size: 20),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Una vez registrada no puede eliminarse. Verificá los datos.',
                      style: TextStyle(color: naranjaXsim, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 25),

            _sectionTitle('FOTOS', textoSec),
            Row(children: [
              Expanded(child: _photoThumbnail('Patente', imagenPatente, fondoTarjeta, naranjaXsim)),
              const SizedBox(width: 15),
              Expanded(child: _photoThumbnail('Entorno - 2', imagenEntorno, fondoTarjeta, naranjaXsim)),
            ]),
            const SizedBox(height: 25),

            _sectionTitle('VEHÍCULO', naranjaXsim),
            _dataCard(fondoTarjeta, [
              _dataRow(Icons.badge, 'Patente', data['patente'], textoSec, textoPri, isBadge: true),
              const Divider(color: Colors.white10),
              _dataRow(Icons.directions_car, 'Vehículo', '${data['marca']} - ${data['modelo']}', textoSec, textoPri),
            ]),

            const SizedBox(height: 25),
            _sectionTitle('UBICACIÓN', naranjaXsim),
            _dataCard(fondoTarjeta, [
              _dataRow(Icons.map, 'Calle / Ruta', data['ubicacion']['calle'], textoSec, textoPri),
              const Divider(color: Colors.white10),
              _dataRow(Icons.pin_drop, 'Altura / Km', data['ubicacion']['nro'], textoSec, textoPri),
              const Divider(color: Colors.white10),
              _dataRow(Icons.location_on, 'GPS', data['ubicacion']['gps'], textoSec, const Color(0xFF2E7D32)),
            ]),

            const SizedBox(height: 25),
            _sectionTitle('INFRACCIÓN', naranjaXsim),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF2D1B20) : const Color(0xFFFFEBEE),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.redAccent.withAlpha(50)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(data['infraccion'], style: TextStyle(color: textoPri, fontWeight: FontWeight.bold, fontSize: 15)),
                  if (data['observaciones'].isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(data['observaciones'], style: TextStyle(color: textoSec, fontSize: 13)),
                  ]
                ],
              ),
            ),

            const SizedBox(height: 30),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Inspector', style: TextStyle(color: textoSec, fontSize: 12)),
                Text(data['registrado_por'], style: TextStyle(color: textoPri, fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Fecha y hora', style: TextStyle(color: textoSec, fontSize: 12)),
                Text(DateFormat('dd/MM/yyyy - HH:mm').format(DateTime.parse(data['fecha_hora'])), style: TextStyle(color: textoPri, fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 40),

            // BOTONES
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    side: BorderSide(color: isDark ? Colors.white10 : Colors.black.withAlpha(26)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  ),
                  child: Text('‹ Volver', style: TextStyle(color: textoPri)),
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: onConfirm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: naranjaXsim,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    elevation: 5,
                  ),
                  child: const Text('Registrar ✓', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ),
            ]),
            const SizedBox(height: 20),
            const Center(
              child: Text(
                'Al confirmar queda asentado con validez legal.',
                style: TextStyle(color: Colors.black26, fontSize: 11),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: color, letterSpacing: 0.5)),
    );
  }

  Widget _photoThumbnail(String label, XFile image, Color fondo, Color naranja) {
    return Container(
      height: 100,
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withAlpha(10)),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          ClipRRect(borderRadius: BorderRadius.circular(11), child: Image.file(File(image.path), fit: BoxFit.cover, width: double.infinity)),
          Positioned(
            bottom: 8,
            child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, shadows: [Shadow(blurRadius: 4, color: Colors.black)])),
          ),
          const Positioned(
            top: 8, right: 8,
            child: Icon(Icons.check_circle, color: Colors.greenAccent, size: 18),
          )
        ],
      ),
    );
  }

  Widget _dataCard(Color fondo, List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withAlpha(10)),
      ),
      child: Column(children: children),
    );
  }

  Widget _dataRow(IconData icon, String label, String value, Color colorSec, Color colorPri, {bool isBadge = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Icon(icon, size: 16, color: naranjaXsim.withAlpha(150)),
          const SizedBox(width: 12),
          Text(label, style: TextStyle(color: colorSec, fontSize: 13)),
          const Spacer(),
          if (isBadge)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: naranjaXsim, borderRadius: BorderRadius.circular(6)),
              child: Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
            )
          else
            Text(value, style: TextStyle(color: colorPri, fontWeight: FontWeight.w600, fontSize: 14)),
        ],
      ),
    );
  }
}
