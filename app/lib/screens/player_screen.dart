import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models.dart';
import '../services/crypto_service.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.channels,
    required this.index,
    required this.crypto,
  });

  final List<Channel> channels;
  final int index;
  final CryptoService crypto;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _Quality {
  const _Quality(this.bandwidth, this.label);
  final int bandwidth;
  final String label;
}

class _PlayerScreenState extends State<PlayerScreen> {
  static const _headers = {
    'User-Agent': 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Chrome/120 Mobile Safari/537.36',
  };

  final Player _player = Player();
  late final VideoController _video = VideoController(_player);
  final List<StreamSubscription<dynamic>> _subs = [];
  final ScrollController _listCtrl = ScrollController();

  late int _i;
  int _gen = 0; // invalida cargas de canales anteriores (cambio rápido)
  int _retry = 0;
  bool _tuned = false;
  bool _ui = true;
  bool _list = false;
  String? _url; // URL descifrada: solo en memoria
  String? _status;
  _Quality? _quality; // null = máxima
  List<_Quality> _qualities = const [];
  Timer? _retryTimer;
  Timer? _stall;
  Timer? _uiTimer;

  @override
  void initState() {
    super.initState();
    _i = widget.index;
    SystemChrome.setPreferredOrientations(
        [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WakelockPlus.enable();

    _subs.add(_player.stream.error.listen((_) => _scheduleRetry()));
    _subs.add(_player.stream.completed.listen((done) {
      if (done) _scheduleRetry(); // un directo no debería terminar
    }));
    _subs.add(_player.stream.buffering.listen(_onBuffering));
    _subs.add(_player.stream.position.listen((p) {
      if (_retry != 0 && p > const Duration(seconds: 2)) {
        _retry = 0;
        if (_status != null && mounted) setState(() => _status = null);
      }
    }));

    _play();
    _bumpUi();
  }

  @override
  void dispose() {
    _gen++;
    _url = null;
    for (final s in _subs) {
      s.cancel();
    }
    _retryTimer?.cancel();
    _stall?.cancel();
    _uiTimer?.cancel();
    _listCtrl.dispose();
    _player.dispose();
    WakelockPlus.disable();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  // ---------------- reproducción ----------------
  Future<void> _tune() async {
    try {
      final p = _player.platform as dynamic;
      await p.setProperty('network-timeout', '10');
      await p.setProperty('stream-lavf-o', 'reconnect=1,reconnect_streamed=1,reconnect_delay_max=4');
    } catch (_) {}
  }

  Future<void> _applyQuality() async {
    try {
      await (_player.platform as dynamic)
          .setProperty('hls-bitrate', _quality?.bandwidth.toString() ?? 'max');
    } catch (_) {}
  }

  Future<void> _play() async {
    _retryTimer?.cancel();
    final gen = ++_gen;
    final ch = widget.channels[_i];
    if (_qualities.isNotEmpty) setState(() => _qualities = const []);
    try {
      if (!_tuned) {
        _tuned = true;
        await _tune();
      }
      final url = await widget.crypto.decrypt(ch.streamEnc); // se descifra en memoria
      if (gen != _gen) return;
      _url = url;
      await _applyQuality();
      await _player.open(Media(url, httpHeaders: _headers));
      if (gen != _gen) return;
      _loadQualities(url, gen);
    } catch (_) {
      if (gen == _gen) _scheduleRetry();
    }
  }

  void _scheduleRetry() {
    if (!mounted || (_retryTimer?.isActive ?? false)) return;
    _retry++;
    const waits = [1, 2, 4, 8, 15];
    final idx = _retry - 1 > 4 ? 4 : _retry - 1;
    setState(() => _status = 'Reconectando… (intento $_retry)');
    _retryTimer = Timer(Duration(seconds: waits[idx]), _play);
  }

  void _onBuffering(bool buffering) {
    _stall?.cancel();
    if (buffering) {
      _stall = Timer(const Duration(seconds: 20), _scheduleRetry); // atasco prolongado
    }
  }

  void _switch(int delta) {
    final n = widget.channels.length;
    setState(() {
      _i = (_i + delta + n) % n;
      _status = null;
    });
    _retry = 0;
    _play();
    _bumpUi();
  }

  // ---------------- calidad (HLS) ----------------
  Future<void> _loadQualities(String url, int gen) async {
    if (RegExp(r'\.(ts|mp4|mkv|flv|avi)(\?|$)', caseSensitive: false).hasMatch(url)) return;
    try {
      final r = await http
          .get(Uri.parse(url), headers: _headers)
          .timeout(const Duration(seconds: 8));
      if (gen != _gen || r.statusCode != 200) return;
      final q = _parseMaster(r.body);
      if (mounted && gen == _gen) setState(() => _qualities = q);
    } catch (_) {}
  }

  List<_Quality> _parseMaster(String body) {
    final byLabel = <String, _Quality>{};
    for (final line in const LineSplitter().convert(body)) {
      if (!line.startsWith('#EXT-X-STREAM-INF:')) continue;
      final bw = RegExp(r'(?:^|[:,])BANDWIDTH=(\d+)').firstMatch(line);
      if (bw == null) continue;
      final b = int.parse(bw.group(1)!);
      final res = RegExp(r'RESOLUTION=\d+x(\d+)').firstMatch(line);
      final label = res != null
          ? '${res.group(1)}p'
          : '${(b / 1000000).toStringAsFixed(1)} Mbps';
      final prev = byLabel[label];
      if (prev == null || b > prev.bandwidth) byLabel[label] = _Quality(b, label);
    }
    return byLabel.values.toList()..sort((a, b) => b.bandwidth.compareTo(a.bandwidth));
  }

  Future<void> _setQuality(_Quality? q) async {
    setState(() => _quality = q);
    await _applyQuality();
    final url = _url;
    if (url != null) await _player.open(Media(url, httpHeaders: _headers));
  }

  void _openQuality() {
    _bumpUi();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1B1F27),
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Calidad', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            ListTile(
              title: const Text('Máxima'),
              trailing: _quality == null ? const Icon(Icons.check) : null,
              onTap: () {
                Navigator.pop(ctx);
                _setQuality(null);
              },
            ),
            for (final q in _qualities)
              ListTile(
                title: Text(q.label),
                trailing: _quality?.bandwidth == q.bandwidth ? const Icon(Icons.check) : null,
                onTap: () {
                  Navigator.pop(ctx);
                  _setQuality(q);
                },
              ),
            if (_qualities.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Este canal no ofrece varias calidades.',
                    style: TextStyle(color: Colors.white54)),
              ),
          ],
        ),
      ),
    );
  }

  // ---------------- interfaz ----------------
  void _bumpUi() {
    _uiTimer?.cancel();
    if (!_ui && mounted) setState(() => _ui = true);
    _uiTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && !_list) setState(() => _ui = false);
    });
  }

  void _toggleList() {
    setState(() => _list = !_list);
    if (_list) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_listCtrl.hasClients) {
          final max = _listCtrl.position.maxScrollExtent;
          final off = _i * 56.0 - 120;
          _listCtrl.jumpTo(off < 0 ? 0 : (off > max ? max : off));
        }
      });
    } else {
      _bumpUi();
    }
  }

  Widget _channelPanel() => Positioned(
        top: 0,
        bottom: 0,
        right: 0,
        width: 300,
        child: Material(
          color: Colors.black87,
          child: SafeArea(
            child: ListView.builder(
              controller: _listCtrl,
              itemExtent: 56,
              itemCount: widget.channels.length,
              itemBuilder: (_, i) {
                final c = widget.channels[i];
                return ListTile(
                  dense: true,
                  selected: i == _i,
                  leading: SizedBox(
                    width: 36,
                    child: c.logoUrl == null
                        ? const Icon(Icons.tv)
                        : Image.network(c.logoUrl!,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => const Icon(Icons.tv)),
                  ),
                  title: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: () {
                    setState(() {
                      _i = i;
                      _list = false;
                      _status = null;
                    });
                    _retry = 0;
                    _play();
                    _bumpUi();
                  },
                );
              },
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final ch = widget.channels[_i];
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _ui ? setState(() => _ui = false) : _bumpUi(),
        onVerticalDragEnd: (d) {
          final v = d.primaryVelocity ?? 0;
          if (v < -200) {
            _switch(1);
          } else if (v > 200) {
            _switch(-1);
          }
        },
        child: Stack(
          children: [
            Positioned.fill(
              child: Video(controller: _video, controls: NoVideoControls, fit: BoxFit.contain),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: StreamBuilder<bool>(
                  stream: _player.stream.buffering,
                  initialData: true,
                  builder: (_, s) => (s.data ?? false)
                      ? const Center(child: CircularProgressIndicator())
                      : const SizedBox.shrink(),
                ),
              ),
            ),
            if (_status != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 24,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(_status!),
                  ),
                ),
              ),
            if (_ui) ...[
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(8, 12, 8, 24),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.black87, Colors.transparent],
                    ),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      if (ch.logoUrl != null)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Image.network(
                            ch.logoUrl!,
                            width: 32,
                            height: 32,
                            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                          ),
                        ),
                      Expanded(
                        child: Text(
                          ch.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Calidad',
                        icon: const Icon(Icons.high_quality, color: Colors.white),
                        onPressed: _openQuality,
                      ),
                      IconButton(
                        tooltip: 'Canales',
                        icon: const Icon(Icons.list, color: Colors.white),
                        onPressed: _toggleList,
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 8,
                top: 0,
                bottom: 0,
                child: Center(
                  child: IconButton(
                    iconSize: 40,
                    icon: const Icon(Icons.skip_previous, color: Colors.white),
                    onPressed: () => _switch(-1),
                  ),
                ),
              ),
              Positioned(
                right: 8,
                top: 0,
                bottom: 0,
                child: Center(
                  child: IconButton(
                    iconSize: 40,
                    icon: const Icon(Icons.skip_next, color: Colors.white),
                    onPressed: () => _switch(1),
                  ),
                ),
              ),
            ],
            if (_list) _channelPanel(),
          ],
        ),
      ),
    );
  }
}
