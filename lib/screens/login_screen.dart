import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import '../services/connectivity_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscureText = true;

  Future<void> _login() async {
    final connectivity = context.read<ConnectivityService>();
    
    if (!connectivity.hasInternet) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Se requiere conexión a internet para el ingreso inicial.'),
        backgroundColor: Colors.orange,
      ));
      return;
    }

    setState(() => _isLoading = true);
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${e.message}')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const Color fondoOscuro = Color(0xFF00162A);

    return Theme(
      data: ThemeData.dark().copyWith(scaffoldBackgroundColor: fondoOscuro),
      child: Scaffold(
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Image.asset('assets/icon/app_icon.png', height: 160, errorBuilder: (c, e, s) => const Icon(Icons.lock_person, size: 80, color: Colors.white)),
                const SizedBox(height: 24),
                const Text('XSIM', textAlign: TextAlign.center, style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 40),
                _buildLoginField(_emailController, 'Correo Electrónico', Icons.email_outlined),
                const SizedBox(height: 16),
                _buildLoginField(
                  _passwordController,
                  'Contraseña',
                  Icons.lock_outline,
                  isPassword: true,
                  onToggleVisibility: () => setState(() => _obscureText = !_obscureText),
                  obscureText: _obscureText,
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: _isLoading ? null : _login,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: fondoOscuro,
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                  ),
                  child: _isLoading ? const CircularProgressIndicator(color: fondoOscuro) : const Text('INGRESAR'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoginField(
      TextEditingController controller,
      String label,
      IconData icon,
      {bool isPassword = false, VoidCallback? onToggleVisibility, bool obscureText = false}
      ) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextField(
        controller: controller,
        obscureText: isPassword ? obscureText : false,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
            labelText: label,
            labelStyle: const TextStyle(color: Colors.white70),
            prefixIcon: Icon(icon, color: Colors.white70),
            suffixIcon: isPassword
                ? IconButton(
              icon: Icon(obscureText ? Icons.visibility_off : Icons.visibility, color: Colors.white70),
              onPressed: onToggleVisibility,
            )
                : null,
            border: InputBorder.none,
            contentPadding: const EdgeInsets.all(16)
        ),
      ),
    );
  }
}
