import 'dart:io';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

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
      // 1. Cargar y REDIMENSIONAR la imagen (Clave para evitar crash y mejorar velocidad)
      final bytes = await File(imagePath).readAsBytes();
      img.Image? image = img.decodeImage(bytes);
      if (image == null) return {};

      // Reducimos a un ancho máximo de 800px (suficiente para OCR y muy liviano)
      if (image.width > 800) {
        image = img.copyResize(image, width: 800);
      }

      // 2. Pre-procesamiento ligero para resaltar texto
      image = img.grayscale(image);
      // Aplicamos un contraste moderado
      image = img.adjustColor(image, contrast: 1.5);

      // 3. Guardar imagen temporal optimizada
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/ocr_temp.jpg');
      await tempFile.writeAsBytes(img.encodeJpg(image, quality: 85));

      // 4. Ejecutar ML Kit sobre la imagen optimizada
      final inputImage = InputImage.fromFilePath(tempFile.path);
      final RecognizedText recognizedText = await _textRecognizer.processImage(inputImage);

      // RegEx para Patentes Argentinas (Viejas: AAA111 y Nuevas: AA111AA)
      final regexPatente = RegExp(r'([A-Z]{2}\d{3}[A-Z]{2})|([A-Z]{3}\d{3})');

      for (TextBlock block in recognizedText.blocks) {
        for (TextLine line in block.lines) {
          String textoRaw = line.text.toUpperCase().trim();
          // Limpiamos ruidos comunes del OCR (espacios, guiones, puntos)
          String textoSoloAlphaNum = textoRaw.replaceAll(RegExp(r'[^A-Z0-9]'), '');

          // Buscamos Patente
          if (patenteDetectada == null) {
            final match = regexPatente.firstMatch(textoSoloAlphaNum);
            if (match != null) {
              patenteDetectada = match.group(0);
            }
          }

          // Buscamos Marca/Modelo
          List<String> palabras = textoRaw.split(RegExp(r'\s+'));
          for (String palabra in palabras) {
            if (modeloDetectado == null && modeloAMarca.containsKey(palabra)) {
              modeloDetectado = palabra;
              marcaDetectada = modeloAMarca[palabra]!;
            }
          }
        }
      }
      
      // Limpieza de archivo temporal
      if (await tempFile.exists()) await tempFile.delete();

    } catch (e) {
      debugPrint('Error en DeteccionService mejorado: $e');
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
