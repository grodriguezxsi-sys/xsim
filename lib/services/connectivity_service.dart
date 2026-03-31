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
  bool _hasInternet = false;
  bool _hasPendingUploads = false;
  
  String? userName;
  String? localidadId;
  bool userDataLoaded = false;

  // --- PERSISTENCIA DEL FORMULARIO ---
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

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  StreamSubscription<QuerySnapshot>? _pendingUploadsSubscription;

  static final ConnectivityService _instance = ConnectivityService._internal();
  factory ConnectivityService() => _instance;
  ConnectivityService._internal() {
    _checkInitialConnectivity();
    _initConnectivityListener();
    _initPendingUploadsListener();
  }

  bool get hasInternet => _hasInternet;
  bool get hasPendingUploads => _hasPendingUploads;

  Future<void> _checkInitialConnectivity() async {
    List<ConnectivityResult> results = await Connectivity().checkConnectivity();
    _updateInternetStatus(results);
  }

  void _updateInternetStatus(List<ConnectivityResult> results) {
    _hasInternet = results.isNotEmpty && !results.contains(ConnectivityResult.none);
    connectionStatusController.add(_hasInternet ? ConnectivityStatus.online : ConnectivityStatus.offline);
    notifyListeners();
    if (_hasInternet && _hasPendingUploads) {
      retryPendingUploads();
    }
  }

  void _initConnectivityListener() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      _updateInternetStatus(results);
    });
  }

  void _initPendingUploadsListener() {
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

  Future<void> loadUserData(String uid) async {
    if (userDataLoaded) return;
    try {
      final doc = await FirebaseFirestore.instance.collection('usuarios').doc(uid).get();
      if (doc.exists) {
        localidadId = doc.data()?['localidad_id'] ?? "S/L";
        userName = doc.data()?['nombre'] ?? "Inspector";
        userDataLoaded = true;
        clearForm(); // LIMPIEZA AL INICIAR SESIÓN O APLICACIÓN
        notifyListeners();
      }
    } catch (e) {
      debugPrint("Error cargando perfil: $e");
    }
  }

  void clearUserData() {
    userName = null;
    localidadId = null;
    userDataLoaded = false;
    clearForm(); 
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
        final localidad = data['localidad_id'] ?? data['localidad'];
        final fechaCarpeta = data['fecha_carpeta'];
        final nP = data['nombre_archivo_patente'];
        final nE = data['nombre_archivo_entorno'];
        final nD = data['nombre_archivo_dato'];
        final rP = data['ruta_local_patente'];
        final rE = data['ruta_local_entorno'];
        final rD = data['ruta_local_dato'];

        if (rP == null || rE == null || rD == null) continue;

        try {
          File fileP = File(rP);
          File fileE = File(rE);
          File fileD = File(rD);

          if (!await fileP.exists() || !await fileE.exists() || !await fileD.exists()) {
            await FirebaseFirestore.instance.collection('infracciones').doc(id).update({'fotos_subidas': true});
            continue;
          }

          final storagePath = "infracciones/$localidad/$fechaCarpeta";
          final refP = FirebaseStorage.instance.ref().child("$storagePath/$nP");
          await refP.putFile(fileP);
          final urlP = await refP.getDownloadURL();

          final refE = FirebaseStorage.instance.ref().child("$storagePath/$nE");
          await refE.putFile(fileE);
          final urlE = await refE.getDownloadURL();

          final refD = FirebaseStorage.instance.ref().child("$storagePath/$nD");
          await refD.putFile(fileD, SettableMetadata(contentType: 'text/plain'));
          final urlD = await refD.getDownloadURL();

          await FirebaseFirestore.instance.collection('infracciones').doc(id).update({
            'fotos_subidas': true,
            'foto_patente_url': urlP,
            'foto_entorno_url': urlE,
            'dato_url': urlD,
          });
        } catch (e) {
          debugPrint("Error reintento $id: $e");
        }
      }
    } catch (e) {
      debugPrint("Error al obtener pendientes: $e");
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    _pendingUploadsSubscription?.cancel();
    connectionStatusController.close();
    super.dispose();
  }
}
