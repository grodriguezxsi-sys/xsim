import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:xsim/services/connectivity_service.dart';
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
  runApp(
    ChangeNotifierProvider(
      create: (context) => ConnectivityService(),
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
      home: const AuthWrapper(),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = FirebaseAuth.instance;
    final state = context.read<ConnectivityService>();

    return StreamBuilder<User?>(
      stream: auth.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasData && snapshot.data != null) {
          state.loadUserData(snapshot.data!.uid);
          return MainNavigation(onThemeToggle: () {}); 
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

class _MainNavigationState extends State<MainNavigation> with SingleTickerProviderStateMixin {
  final PageController _pageController = PageController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ConnectivityService>().connectionStatusController.stream.listen((status) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        if (status == ConnectivityStatus.offline) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Modo offline activado.'), backgroundColor: Colors.orange)
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Conexión recuperada.'), backgroundColor: Colors.green)
          );
        }
      });
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<bool> _handlePop() async {
    final connectivityService = context.read<ConnectivityService>();
    
    // Si hay pendientes, preguntamos si subir
    if (connectivityService.hasPendingUploads && connectivityService.hasInternet) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Infracciones Pendientes'),
          content: const Text('¿Deseas subirlas antes de salir?'),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('NO')),
            ElevatedButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('SI')),
          ],
        ),
      );
      if (confirm == true) {
        await connectivityService.retryPendingUploads();
      }
    }

    // SIEMPRE LIMPIAMOS EL FORMULARIO AL SALIR DE LA APP
    connectivityService.clearForm();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final onThemeToggle = context.findAncestorStateOfType<_ThemeManagerState>()?._toggleTheme ?? () {};

    return Consumer<ConnectivityService>(
      builder: (context, appState, child) {
        if (!appState.userDataLoaded) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) async {
            if (didPop) return;
            if (await _handlePop() && context.mounted) {
              SystemNavigator.pop();
            }
          },
          child: Scaffold(
            body: PageView(
              controller: _pageController,
              children: [
                InfraccionForm(
                  localidadId: appState.localidadId!,
                  userName: appState.userName!,
                  onThemeToggle: onThemeToggle,
                ),
                HistorialScreen(
                  localidadId: appState.localidadId!,
                  userName: appState.userName!,
                  onThemeToggle: onThemeToggle,
                ),
              ],
            ),
          ),
        );
      }
    );
  }
}
