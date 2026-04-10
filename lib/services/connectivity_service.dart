import 'dart:async';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';

enum ConnectivityStatus { online, offline }

class ConnectivityService with ChangeNotifier {
  final StreamController<ConnectivityStatus> connectionStatusController = StreamController<ConnectivityStatus>.broadcast();
  bool _hasInternet = true;
  bool _hasPendingUploads = false;
  
  String? userName;
  String? localidadId;
  bool userDataLoaded = false;

  final patenteController = TextEditingController();
  final marcaController = TextEditingController();
  final modeloController = TextEditingController();
  final calleController = TextEditingController();
  final numeroController = TextEditingController();
  final tipoInfraccionController = TextEditingController();
  final observacionesController = TextEditingController();
  XFile? imagenPatente;
  XFile? imagenEntorno;
  String ubicacionGps = "No obtenida";

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  StreamSubscription<QuerySnapshot>? _pendingUploadsSubscription;

  bool get hasInternet => _hasInternet;
  bool get hasPendingUploads => _hasPendingUploads;

  ConnectivityService() {
    _initConnectivityListener();
  }

  void _initConnectivityListener() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      _hasInternet = results.isNotEmpty && !results.contains(ConnectivityResult.none);
      connectionStatusController.add(_hasInternet ? ConnectivityStatus.online : ConnectivityStatus.offline);
      notifyListeners();
      if (_hasInternet && _hasPendingUploads) {
        retryPendingUploads();
      }
    });
  }

  void startPendingUploadsListener() {
    if (localidadId == null) {
      debugPrint("startPendingUploadsListener: localidadId es null, cancelando.");
      return;
    }
    
    debugPrint("Iniciando listener de pendientes para localidad: $localidadId");
    _pendingUploadsSubscription?.cancel();
    _pendingUploadsSubscription = FirebaseFirestore.instance
        .collection('infracciones')
        .where('localidad_id', isEqualTo: localidadId)
        .where('fotos_subidas', isEqualTo: false)
        .snapshots()
        .listen((snapshot) {
          _hasPendingUploads = snapshot.docs.isNotEmpty;
          debugPrint("Pendientes detectadas: ${snapshot.docs.length}");
          notifyListeners();
          if (_hasInternet && _hasPendingUploads) {
            retryPendingUploads();
          }
        }, onError: (error) {
          debugPrint("Error en listener de pendientes: $error");
        });
  }

  Future<void> loadUserData(String uid) async {
    try {
      final doc = await FirebaseFirestore.instance.collection('usuarios').doc(uid).get();
      if (doc.exists) {
        final data = doc.data();
        localidadId = data?['localidad_id'];
        userName = data?['nombre'];
        debugPrint("Usuario cargado: $userName de $localidadId");
        startPendingUploadsListener(); 
      } else {
        debugPrint("El documento de usuario no existe en Firestore.");
      }
      userDataLoaded = true;
      notifyListeners();
    } catch (e) {
      debugPrint("Error Firestore loadUserData: $e");
      userDataLoaded = true;
      notifyListeners();
    }
  }

  void reset() {
    userName = null;
    localidadId = null;
    userDataLoaded = false;
    _pendingUploadsSubscription?.cancel();
    clearForm();
  }

  void clearForm() {
    patenteController.clear();
    marcaController.clear();
    modeloController.clear();
    calleController.clear();
    numeroController.clear();
    tipoInfraccionController.clear();
    observacionesController.clear();
    imagenPatente = null;
    imagenEntorno = null;
    ubicacionGps = "No obtenida";
    notifyListeners();
  }

  Future<void> retryPendingUploads() async {
    if (!_hasInternet || localidadId == null) return;
    debugPrint("Intentando subir infracciones pendientes...");
    try {
      final pendingDocs = await FirebaseFirestore.instance
          .collection('infracciones')
          .where('localidad_id', isEqualTo: localidadId)
          .where('fotos_subidas', isEqualTo: false)
          .get();

      for (var doc in pendingDocs.docs) {
        final data = doc.data();
        final id = doc.id;
        
        final locId = data['localidad_id'] ?? "S_L";
        final fechaCarpeta = data['fecha_carpeta'] ?? "S_F";
        final storagePath = "infracciones/$locId/$fechaCarpeta";
        
        debugPrint("Subiendo acta ID: $id");
        
        try {
          String? urlP, urlE, urlD;
          bool todasSubidas = true;

          // 1. Subir Patente (Obligatoria)
          if (data['ruta_local_patente'] != null) {
            final fileP = File(data['ruta_local_patente']);
            if (await fileP.exists()) {
              final refP = FirebaseStorage.instance.ref().child("$storagePath/${data['nombre_archivo_patente']}");
              await refP.putFile(fileP);
              urlP = await refP.getDownloadURL();
            } else {
              debugPrint("Archivo de patente no encontrado localmente para acta $id");
              todasSubidas = false;
            }
          } else {
             todasSubidas = false;
          }

          // 2. Subir Entorno (Obligatoria)
          if (data['ruta_local_entorno'] != null && todasSubidas) {
            final fileE = File(data['ruta_local_entorno']);
            if (await fileE.exists()) {
              final refE = FirebaseStorage.instance.ref().child("$storagePath/${data['nombre_archivo_entorno']}");
              await refE.putFile(fileE);
              urlE = await refE.getDownloadURL();
            } else {
              debugPrint("Archivo de entorno no encontrado localmente para acta $id");
              todasSubidas = false;
            }
          } else {
             todasSubidas = false;
          }

          // 3. Subir Dato (Opcional/Texto)
          if (data['ruta_local_dato'] != null && todasSubidas) {
            final fileD = File(data['ruta_local_dato']);
            if (await fileD.exists()) {
              final refD = FirebaseStorage.instance.ref().child("$storagePath/${data['nombre_archivo_dato']}");
              await refD.putFile(fileD, SettableMetadata(contentType: 'text/plain'));
              urlD = await refD.getDownloadURL();
            }
          }

          // 4. SOLO actualizar Firestore si las fotos se subieron bien
          if (todasSubidas && urlP != null && urlE != null) {
            await FirebaseFirestore.instance.collection('infracciones').doc(id).update({
              'fotos_subidas': true,
              'foto_patente_url': urlP,
              'foto_entorno_url': urlE,
              'dato_url': urlD,
            });
            debugPrint("Acta $id subida y actualizada con éxito en Firestore.");
          } else {
            debugPrint("No se actualizará Firestore para el acta $id porque faltan archivos o falló la subida.");
          }

        } catch (e) { 
          debugPrint("Error subiendo archivos de acta $id a Storage: $e"); 
          // Si falla el putFile de Storage, salta al catch y NO actualiza Firestore
        }
      }
    } catch (e) {
      debugPrint("Error en retryPendingUploads obteniendo documentos de Firestore: $e");
    }
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    _pendingUploadsSubscription?.cancel();
    connectionStatusController.close();
    super.dispose();
  }
}
