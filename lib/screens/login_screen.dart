import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

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

  // Paleta de colores solicitada
  static const Color fondoPrincipal = Color(0xFF1A1F2E);
  static const Color fondoCampo = Color(0xFF222839);
  static const Color rojoAcento = Color(0xFFE8341A);

  Future<void> _login() async {
    setState(() => _isLoading = true);
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      ).timeout(const Duration(seconds: 15));
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${e.message}')));
    } on TimeoutException catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay respuesta del servidor. Revisa tu conexión a internet.'))
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error inesperado: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: fondoPrincipal,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Logo directo (se verá bien cuando subas la imagen con transparencia)
              Image.asset(
                'assets/icon/app_icon.png', 
                height: 160, 
                errorBuilder: (c, e, s) => const Icon(Icons.lock_person, size: 80, color: rojoAcento)
              ),
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
                    backgroundColor: rojoAcento,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 55),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                    elevation: 5
                ),
                child: _isLoading 
                  ? const CircularProgressIndicator(color: Colors.white) 
                  : const Text('INGRESAR', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoginField(TextEditingController controller, String label, IconData icon, {bool isPassword = false, VoidCallback? onToggleVisibility, bool obscureText = false}) {
    return Container(
      decoration: BoxDecoration(
        color: fondoCampo,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.white.withAlpha(15)),
      ),
      child: TextField(
        controller: controller,
        obscureText: isPassword ? obscureText : false,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
            labelText: label,
            labelStyle: const TextStyle(color: Colors.white38, fontSize: 14),
            prefixIcon: Icon(icon, color: rojoAcento, size: 22),
            suffixIcon: isPassword
                ? IconButton(
              icon: Icon(obscureText ? Icons.visibility_off : Icons.visibility, color: Colors.white38, size: 20),
              onPressed: onToggleVisibility,
            )
                : null,
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16)
        ),
      ),
    );
  }
}
