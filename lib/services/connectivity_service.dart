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
    // No iniciamos Firestore aquí para no bloquear el login
  }

  void _initConnectivityListener() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      _hasInternet = results.isNotEmpty && !results.contains(ConnectivityResult.none);
      connectionStatusController.add(_hasInternet ? ConnectivityStatus.online : ConnectivityStatus.offline);
      notifyListeners();
    });
  }

  Future<void> loadUserData(String uid) async {
    try {
      final doc = await FirebaseFirestore.instance.collection('usuarios').doc(uid).get();
      if (doc.exists) {
        localidadId = doc.data()?['localidad_id'];
        userName = doc.data()?['nombre'];
      }
      
      // Iniciamos los listeners de subidas solo después de tener éxito con Firestore
      _initPendingUploadsListener();
      
      userDataLoaded = true;
      notifyListeners();
    } catch (e) {
      debugPrint("Error Firestore: $e");
      userDataLoaded = true;
      notifyListeners();
    }
  }

  void _initPendingUploadsListener() {
    _pendingUploadsSubscription?.cancel();
    _pendingUploadsSubscription = FirebaseFirestore.instance
        .collection('infracciones')
        .where('fotos_subidas', isEqualTo: false)
        .snapshots()
        .listen((snapshot) {
          _hasPendingUploads = snapshot.docs.isNotEmpty;
          notifyListeners();
          if (_hasInternet && _hasPendingUploads) {
            retryPendingUploads();
          }
        });
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
    if (!_hasInternet) return;
    try {
      final pendingDocs = await FirebaseFirestore.instance
          .collection('infracciones')
          .where('fotos_subidas', isEqualTo: false)
          .get();

      for (var doc in pendingDocs.docs) {
        final data = doc.data();
        final id = doc.id;
        final storagePath = "infracciones/${data['localidad_id']}/${data['fecha_carpeta']}";
        
        try {
          if (data['ruta_local_patente'] != null) {
            await FirebaseStorage.instance.ref().child("$storagePath/${data['nombre_archivo_patente']}").putFile(File(data['ruta_local_patente']));
          }
          if (data['ruta_local_entorno'] != null) {
            await FirebaseStorage.instance.ref().child("$storagePath/${data['nombre_archivo_entorno']}").putFile(File(data['ruta_local_entorno']));
          }
          if (data['ruta_local_dato'] != null) {
            await FirebaseStorage.instance.ref().child("$storagePath/${data['nombre_archivo_dato']}").putFile(File(data['ruta_local_dato']), SettableMetadata(contentType: 'text/plain'));
          }
          await FirebaseFirestore.instance.collection('infracciones').doc(id).update({'fotos_subidas': true});
        } catch (e) { debugPrint("Error upload: $e"); }
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    _pendingUploadsSubscription?.cancel();
    connectionStatusController.close();
    super.dispose();
  }
}
