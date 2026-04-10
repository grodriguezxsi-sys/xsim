import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
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

class _HistorialScreenState extends State<HistorialScreen> {
  static const Color naranjaXsim = Color(0xFFE8952A);

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";
  String _filtroActual = "Todos";

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // Colores dinámicos
    final Color fondoMokup = isDark ? const Color(0xFF1A1F2E) : const Color(0xFFF0F2F5);
    final Color fondoTarjeta = isDark ? const Color(0xFF222839) : Colors.white;
    final Color textoPri = isDark ? Colors.white : const Color(0xFF1A1F2E);
    final Color textoSec = isDark ? Colors.white38 : Colors.black38;

    return Scaffold(
      backgroundColor: fondoMokup,
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF141824) : Colors.white,
        elevation: 0,
        title: Row(
          children: [
            Text('Historial', style: TextStyle(color: textoPri, fontWeight: FontWeight.bold)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF2E7D32).withAlpha(40),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  const CircleAvatar(backgroundColor: Color(0xFF2E7D32), radius: 3),
                  const SizedBox(width: 5),
                  const Text('Sincronizado', style: TextStyle(color: Color(0xFF2E7D32), fontSize: 10, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // DASHBOARD DE MÉTRICAS
          _buildDashboard(widget.localidadId, fondoTarjeta, textoPri, textoSec),
          
          // BUSCADOR Y FILTROS
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                _buildSearchBar(isDark, fondoTarjeta, textoSec),
                const SizedBox(height: 15),
                _buildQuickFilters(textoSec),
              ],
            ),
          ),

          // LISTADO DE INFRACCIONES
          Expanded(
            child: _buildInfraccionesList(fondoTarjeta, textoPri, textoSec, isDark),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboard(String localidadId, Color fondo, Color textoPri, Color textoSec) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('infracciones')
          .where('localidad_id', isEqualTo: localidadId)
          .snapshots(),
      builder: (context, snapshot) {
        int hoy = 0;
        int pendientes = 0;
        int mes = 0;

        if (snapshot.hasData) {
          final now = DateTime.now();
          for (var doc in snapshot.data!.docs) {
            final data = doc.data() as Map<String, dynamic>;
            final DateTime? fecha = (data['fecha'] as Timestamp?)?.toDate();
            if (fecha != null) {
              if (fecha.day == now.day && fecha.month == now.month && fecha.year == now.year) hoy++;
              if (fecha.month == now.month && fecha.year == now.year) mes++;
            }
            if (data['fotos_subidas'] == false) pendientes++;
          }
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Expanded(child: _metricCard(hoy.toString(), 'Hoy', fondo, textoPri, textoSec)),
              const SizedBox(width: 10),
              Expanded(child: _metricCard(pendientes.toString(), 'Pendiente', fondo, textoPri, textoSec, isAlert: pendientes > 0)),
              const SizedBox(width: 10),
              Expanded(child: _metricCard(mes.toString(), 'Este mes', fondo, textoPri, textoSec)),
            ],
          ),
        );
      },
    );
  }

  Widget _metricCard(String value, String label, Color fondo, Color textoPri, Color textoSec, {bool isAlert = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 15),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: isAlert ? naranjaXsim.withAlpha(100) : Colors.black.withAlpha(10)),
      ),
      child: Column(
        children: [
          Text(value, style: TextStyle(color: isAlert ? naranjaXsim : textoPri, fontSize: 22, fontWeight: FontWeight.bold)),
          Text(label, style: TextStyle(color: textoSec, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildSearchBar(bool isDark, Color fondo, Color textoSec) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.black.withAlpha(10)),
      ),
      child: Row(
        children: [
          Icon(Icons.search, color: naranjaXsim.withAlpha(150), size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _searchQuery = v.toUpperCase()),
              style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Buscar patente...',
                hintStyle: TextStyle(color: textoSec, fontSize: 14),
                border: InputBorder.none,
              ),
            ),
          ),
          Text('Filtrar', style: TextStyle(color: naranjaXsim, fontSize: 12, fontWeight: FontWeight.bold)),
          const Icon(Icons.arrow_drop_down, color: naranjaXsim),
        ],
      ),
    );
  }

  Widget _buildQuickFilters(Color textoSec) {
    final filtros = ["Todos", "Hoy", "Pendientes", "Esta semana", "Este mes"];
    return SizedBox(
      height: 35,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: filtros.length,
        itemBuilder: (context, i) {
          bool selected = _filtroActual == filtros[i];
          return GestureDetector(
            onTap: () => setState(() => _filtroActual = filtros[i]),
            child: Container(
              margin: const EdgeInsets.only(right: 10),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: selected ? naranjaXsim : Colors.white.withAlpha(10),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                filtros[i],
                style: TextStyle(color: selected ? Colors.white : textoSec, fontSize: 12, fontWeight: selected ? FontWeight.bold : FontWeight.normal),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildInfraccionesList(Color fondo, Color textoPri, Color textoSec, bool isDark) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('infracciones')
          .where('localidad_id', isEqualTo: widget.localidadId)
          .orderBy('fecha', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text("No hay registros"));

        var docs = snapshot.data!.docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final patente = (data['patente'] ?? "").toString().toUpperCase();
          final bool matchSearch = patente.contains(_searchQuery);
          
          if (!matchSearch) return false;

          if (_filtroActual == "Pendientes") return data['fotos_subidas'] == false;
          if (_filtroActual == "Hoy") {
            final now = DateTime.now();
            final fecha = (data['fecha'] as Timestamp?)?.toDate();
            return fecha != null && fecha.day == now.day && fecha.month == now.month;
          }
          return true;
        }).toList();

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final data = docs[i].data() as Map<String, dynamic>;
            final DateTime? fecha = (data['fecha'] as Timestamp?)?.toDate();
            final bool showHeader = i == 0 || _isDifferentDay(fecha, (docs[i-1].data() as Map)['fecha']);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showHeader) _buildDateHeader(fecha, textoSec),
                _buildHistoryCard(data, fondo, textoPri, textoSec, isDark),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildDateHeader(DateTime? fecha, Color textoSec) {
    if (fecha == null) return const SizedBox.shrink();
    final now = DateTime.now();
    final bool isHoy = fecha.day == now.day && fecha.month == now.month;
    final String label = isHoy ? "Hoy - ${DateFormat('dd-MM-yyyy').format(fecha)}" : DateFormat('dd-MM-yyyy').format(fecha);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 15),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: const Color(0xFF1E3A8A).withAlpha(40), borderRadius: BorderRadius.circular(4)),
        child: Text(label, style: const TextStyle(color: Color(0xFF60A5FA), fontSize: 11, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildHistoryCard(Map<String, dynamic> data, Color fondo, Color textoPri, Color textoSec, bool isDark) {
    final bool subido = data['fotos_subidas'] ?? false;
    final String hora = data['fecha_hora'] != null ? data['fecha_hora'].toString().substring(11, 16) : "--:--";

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: subido ? Colors.black.withAlpha(10) : naranjaXsim.withAlpha(100)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(data['patente'] ?? 'S/P', style: TextStyle(color: subido ? const Color(0xFF60A5FA) : naranjaXsim, fontSize: 18, fontWeight: FontWeight.bold)),
                Text(data['infraccion'] ?? 'Infracción', style: TextStyle(color: textoPri, fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Text("$hora hs", style: TextStyle(color: textoSec, fontSize: 11)),
              ],
            ),
          ),
          Column(
            children: [
              Icon(subido ? Icons.cloud_done : Icons.hourglass_empty, color: subido ? const Color(0xFF60A5FA) : naranjaXsim, size: 24),
              const SizedBox(height: 4),
              Text(subido ? "Sync OK" : "Pendiente", style: TextStyle(color: subido ? const Color(0xFF2E7D32) : naranjaXsim, fontSize: 10, fontWeight: FontWeight.bold)),
            ],
          )
        ],
      ),
    );
  }

  bool _isDifferentDay(DateTime? d1, dynamic d2) {
    if (d1 == null || d2 == null) return false;
    final DateTime date2 = (d2 as Timestamp).toDate();
    return d1.day != date2.day || d1.month != date2.month;
  }
}
