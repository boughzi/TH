import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api.dart';

/// Pantalla de bloqueo: pide el código manual que genera el administrador.
class ActivationScreen extends StatefulWidget {
  const ActivationScreen({super.key, required this.status, required this.onRefresh});

  final String status; // locked | disabled | expired | error
  final Future<void> Function() onRefresh;

  @override
  State<ActivationScreen> createState() => _ActivationScreenState();
}

class _ActivationScreenState extends State<ActivationScreen> {
  final _ctrl = TextEditingController();
  late final Future<String> _contact = Api.contactText().catchError((_) => '');
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _ctrl.text.trim();
    if (code.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ok = await Api.redeem(code);
      if (ok) {
        await widget.onRefresh();
      } else if (mounted) {
        setState(() => _error = 'Código incorrecto o bloqueado. Contacta con el administrador.');
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Error de conexión. Inténtalo de nuevo.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String get _title {
    switch (widget.status) {
      case 'disabled':
        return 'Cuenta desactivada';
      case 'expired':
        return 'Acceso caducado';
      case 'error':
        return 'No se pudo comprobar tu acceso';
      default:
        return 'Activa tu cuenta';
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = sb.auth.currentUser?.email ?? '';
    final canEnter = widget.status == 'locked';
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.lock_outline, size: 64),
                  const SizedBox(height: 12),
                  Text(_title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Text(email, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54)),
                  const SizedBox(height: 16),
                  FutureBuilder<String>(
                    future: _contact,
                    builder: (_, s) => Text(
                      s.data ?? '',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (canEnter) ...[
                    TextField(
                      controller: _ctrl,
                      enabled: !_busy,
                      textAlign: TextAlign.center,
                      textCapitalization: TextCapitalization.characters,
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]'))],
                      maxLength: 16,
                      style: const TextStyle(fontSize: 22, letterSpacing: 4),
                      decoration: const InputDecoration(
                        hintText: 'CÓDIGO',
                        counterText: '',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _submit(),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Activar'),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.redAccent)),
                  ],
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _busy ? null : widget.onRefresh,
                    child: const Text('Actualizar estado'),
                  ),
                  TextButton(
                    onPressed: () => sb.auth.signOut(),
                    child: const Text('Cerrar sesión'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
