import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'screens/login_screen.dart';
import 'screens/infraccion_form.dart';
import 'screens/historial_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint("Error inicializando Firebase: $e");
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const ThemeManager();
  }
}

class ThemeManager extends StatefulWidget {
  const ThemeManager({super.key});

  @override
  State<ThemeManager> createState() => _ThemeManagerState();
}

class _ThemeManagerState extends State<ThemeManager> {
  static const Color azulMarinoXsim = Color(0xFF00162A);
  ThemeMode _themeMode = ThemeMode.dark;

  void _toggleTheme() {
    setState(() {
      _themeMode = _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'XSIM',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorSchemeSeed: azulMarinoXsim,
        scaffoldBackgroundColor: Colors.white,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: azulMarinoXsim,
        scaffoldBackgroundColor: azulMarinoXsim,
        appBarTheme: const AppBarTheme(backgroundColor: azulMarinoXsim),
      ),
      themeMode: _themeMode,
      home: AuthWrapper(onThemeToggle: _toggleTheme),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  final VoidCallback onThemeToggle;
  const AuthWrapper({super.key, required this.onThemeToggle});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasData) {
          return MainNavigation(onThemeToggle: onThemeToggle);
        }
        return const LoginScreen();
      },
    );
  }
}

class MainNavigation extends StatefulWidget {
  final VoidCallback onThemeToggle;
  const MainNavigation({super.key, required this.onThemeToggle});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  final PageController _pageController = PageController();
  int _currentIndex = 0;
  String? _localidadId;
  String? _userName;

  @override
  void initState() {
    super.initState();
    _fetchUserData();
  }

  Future<void> _fetchUserData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final doc = await FirebaseFirestore.instance.collection('usuarios').doc(user.uid).get();
        if (doc.exists) {
          if (!mounted) return;
          setState(() {
            _localidadId = doc.data()?['localidad_id'] ?? "S/L";
            _userName = doc.data()?['nombre'] ?? "Inspector";
          });
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_localidadId == null || _userName == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          InfraccionForm(
            localidadId: _localidadId!,
            userName: _userName!,
            onThemeToggle: widget.onThemeToggle,
          ),
          HistorialScreen(localidadId: _localidadId!),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() => _currentIndex = index);
          _pageController.jumpToPage(index);
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.edit_document), label: 'Formulario'),
          NavigationDestination(icon: Icon(Icons.history), label: 'Historial'),
        ],
      ),
    );
  }
}
