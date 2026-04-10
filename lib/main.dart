import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:xsim/services/connectivity_service.dart';
import 'firebase_options.dart';
import 'screens/login_screen.dart';
import 'screens/infraccion_form.dart';
import 'screens/historial_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint("Error inicializando Firebase: $e");
  }
  runApp(
    ChangeNotifierProvider(
      create: (_) => ConnectivityService(),
      child: const MyApp(),
    ),
  );
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
  // Paleta Dark
  static const Color fondoPrincipalDark = Color(0xFF1A1F2E);
  static const Color fondoAppBarDark = Color(0xFF141824);
  
  // Paleta Light (Mockup)
  static const Color fondoPrincipalLight = Color(0xFFF0F2F5);
  static const Color fondoAppBarLight = Colors.white;
  
  static const Color naranjaAcento = Color(0xFFE8952A);

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
        colorSchemeSeed: naranjaAcento,
        scaffoldBackgroundColor: fondoPrincipalLight,
        appBarTheme: const AppBarTheme(
          backgroundColor: fondoAppBarLight,
          foregroundColor: Color(0xFF1A1F2E),
          elevation: 0.5,
          centerTitle: false,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: naranjaAcento,
        scaffoldBackgroundColor: fondoPrincipalDark,
        appBarTheme: const AppBarTheme(
          backgroundColor: fondoAppBarDark,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: false,
        ),
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
        if (snapshot.hasData && snapshot.data != null) {
          return MainNavigation(uid: snapshot.data!.uid, onThemeToggle: onThemeToggle);
        }
        return const LoginScreen();
      },
    );
  }
}

class MainNavigation extends StatefulWidget {
  final String uid;
  final VoidCallback onThemeToggle;
  const MainNavigation({super.key, required this.uid, required this.onThemeToggle});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ConnectivityService>().loadUserData(widget.uid);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ConnectivityService>(
      builder: (context, state, _) {
        if (!state.userDataLoaded) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        return Scaffold(
          body: PageView(
            children: [
              InfraccionForm(
                localidadId: state.localidadId ?? "S/L",
                userName: state.userName ?? "Inspector",
                onThemeToggle: widget.onThemeToggle,
              ),
              HistorialScreen(
                localidadId: state.localidadId ?? "S/L",
                userName: state.userName ?? "Inspector",
                onThemeToggle: widget.onThemeToggle,
              ),
            ],
          ),
        );
      },
    );
  }
}
