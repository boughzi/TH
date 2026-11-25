import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'screens/activation_screen.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/api.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await Supabase.initialize(url: Config.supabaseUrl, anonKey: Config.supabaseAnonKey);
  runApp(const LiveTvApp());
}

class LiveTvApp extends StatelessWidget {
  const LiveTvApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'LiveTV',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF4F8CFF),
            brightness: Brightness.dark,
          ),
          scaffoldBackgroundColor: const Color(0xFF0E1014),
        ),
        home: const AuthGate(),
      );
}

/// Sesión → estado de activación → Home.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> with WidgetsBindingObserver {
  late final StreamSubscription<AuthState> _sub;
  Session? _session = sb.auth.currentSession;
  String? _uid = sb.auth.currentSession?.user.id;
  String? _status;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sub = sb.auth.onAuthStateChange.listen((data) {
      final uid = data.session?.user.id;
      if (uid != _uid) {
        // Cambió el usuario (login/logout): se vuelve a comprobar el acceso.
        setState(() {
          _uid = uid;
          _session = data.session;
          _status = null;
        });
        _refresh();
      } else {
        setState(() => _session = data.session); // refresco de token: no se toca nada
      }
    });
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh(); // detecta caducidad/desactivación
  }

  Future<void> _refresh() async {
    if (sb.auth.currentSession == null) return;
    try {
      final s = await Api.accessStatus();
      if (mounted) setState(() => _status = s);
    } catch (_) {
      if (mounted && _status == null) setState(() => _status = 'error');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_session == null) return const LoginScreen();
    if (_status == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_status == 'ok') return const HomeScreen();
    return ActivationScreen(status: _status!, onRefresh: _refresh);
  }
}
