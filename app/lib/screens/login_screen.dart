import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../services/api.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _google() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await sb.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: Config.oauthRedirect,
      );
    } catch (e) {
      if (mounted) setState(() => _error = 'No se pudo iniciar sesión. Inténtalo de nuevo.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.live_tv_rounded, size: 84, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(height: 12),
                  const Text('LiveTV', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 32),
                  FilledButton.icon(
                    onPressed: _busy ? null : _google,
                    icon: const Icon(Icons.login),
                    label: const Text('Continuar con Google'),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
}
