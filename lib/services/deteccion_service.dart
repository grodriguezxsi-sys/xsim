import 'dart:io';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:flutter/foundation.dart';

class DeteccionVehiculoService {
  final TextRecognizer _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

  final Map<String, String> modeloAMarca = {
    'COROLLA': 'TOYOTA', 'HILUX': 'TOYOTA', 'ETIOS': 'TOYOTA', 'YARIS': 'TOYOTA', 'SW4': 'TOYOTA',
    'RANGER': 'FORD', 'FOCUS': 'FORD', 'FIESTA': 'FORD', 'KA': 'FORD', 'ECOSPORT': 'FORD',
    'CRONOS': 'FIAT', 'TORO': 'FIAT', 'MOBI': 'FIAT', 'ARGO': 'FIAT', 'STRADA': 'FIAT',
    'GOL': 'VOLKSWAGEN', 'AMAROK': 'VOLKSWAGEN', 'POLO': 'VOLKSWAGEN', 'TAOS': 'VOLKSWAGEN',
    'SANDERO': 'RENAULT', 'LOGAN': 'RENAULT', 'KANGOO': 'RENAULT', 'DUSTER': 'RENAULT',
    'ONIX': 'CHEVROLET', 'CRUZE': 'CHEVROLET', 'S10': 'CHEVROLET', 'TRACKER': 'CHEVROLET',
    '208': 'PEUGEOT', '2008': 'PEUGEOT', '308': 'PEUGEOT', 'PARTNER': 'PEUGEOT',
  };

  Future<Map<String, String?>> procesarYDeteccionDual(String imagePath) async {
    String? patenteDetectada;
    String? modeloDetectado;
    String? marcaDetectada;

    try {
      // Usamos el archivo original directamente primero para evitar el pesado procesamiento de imagen que causa el crash
      final inputImage = InputImage.fromFilePath(imagePath);
      final RecognizedText recognizedText = await _textRecognizer.processImage(inputImage);

      final regexPatente = RegExp(r'([A-Z]{2}\d{3}[A-Z]{2})|([A-Z]{3}\d{3})');

      for (TextBlock block in recognizedText.blocks) {
        for (TextLine line in block.lines) {
          String textoRaw = line.text.toUpperCase().trim();
          String textoSoloAlphaNum = textoRaw.replaceAll(RegExp(r'[^A-Z0-9]'), '');

          if (patenteDetectada == null && regexPatente.hasMatch(textoSoloAlphaNum)) {
            patenteDetectada = textoSoloAlphaNum;
          }

          List<String> palabras = textoRaw.split(' ');
          for (String palabra in palabras) {
            if (modeloDetectado == null && modeloAMarca.containsKey(palabra)) {
              modeloDetectado = palabra;
              marcaDetectada = modeloAMarca[palabra]!;
              break;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error en DeteccionService: $e');
    }

    return {
      'patente': patenteDetectada,
      'marca': marcaDetectada,
      'modelo': modeloDetectado,
    };
  }

  void dispose() {
    _textRecognizer.close();
  }
}
