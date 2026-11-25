import 'package:flutter/material.dart';

import '../models.dart';
import '../services/api.dart';
import '../services/crypto_service.dart';
import 'player_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Channel> _all = [];
  List<Category> _cats = [];
  CryptoService? _crypto;
  String? _country;
  String? _cat;
  String _q = '';
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final crypto = await Api.loadCrypto();
      final cats = await Api.categories();
      final chans = await Api.channels();
      if (!mounted) return;
      setState(() {
        _crypto = crypto;
        _cats = cats;
        _all = chans;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudieron cargar los canales';
        _loading = false;
      });
    }
  }

  List<Channel> get _filtered {
    final q = _q.toLowerCase();
    return _all
        .where((c) =>
            (_country == null || c.countryCode == _country) &&
            (_cat == null || c.categoryId == _cat) &&
            (q.isEmpty || c.name.toLowerCase().contains(q)))
        .toList();
  }

  List<MapEntry<String, String>> get _countries {
    final m = <String, String>{};
    for (final c in _all) {
      m.putIfAbsent(c.countryCode, () => c.countryName);
    }
    return m.entries.toList()..sort((a, b) => a.value.compareTo(b.value));
  }

  List<Category> get _availableCats {
    final ids = _all
        .where((c) => _country == null || c.countryCode == _country)
        .map((c) => c.categoryId)
        .toSet();
    return _cats.where((c) => ids.contains(c.id)).toList();
  }

  void _open(List<Channel> list, int i) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PlayerScreen(channels: list, index: i, crypto: _crypto!),
    ));
  }

  Widget _flagItem(String? url, String label, bool selected, VoidCallback onTap) {
    final primary = Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(40),
      child: SizedBox(
        width: 72,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: selected ? primary : Colors.transparent, width: 2),
              ),
              child: CircleAvatar(
                radius: 24,
                backgroundColor: Colors.white12,
                backgroundImage: url != null ? NetworkImage(url) : null,
                child: url == null ? const Icon(Icons.public) : null,
              ),
            ),
            const SizedBox(height: 4),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(label: Text(label), selected: selected, onSelected: (_) => onTap()),
      );

  @override
  Widget build(BuildContext context) {
    final list = _filtered;
    return Scaffold(
      appBar: AppBar(
        title: const Text('LiveTV'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
          IconButton(onPressed: () => sb.auth.signOut(), icon: const Icon(Icons.logout)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!),
                      const SizedBox(height: 12),
                      FilledButton(onPressed: _load, child: const Text('Reintentar')),
                    ],
                  ),
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                      child: TextField(
                        onChanged: (v) => setState(() => _q = v),
                        decoration: InputDecoration(
                          hintText: 'Buscar canal',
                          prefixIcon: const Icon(Icons.search),
                          isDense: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(28)),
                        ),
                      ),
                    ),
                    SizedBox(
                      height: 86,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        children: [
                          _flagItem(null, 'Todos', _country == null, () => setState(() {
                                _country = null;
                                _cat = null;
                              })),
                          for (final c in _countries)
                            _flagItem(flagUrl(c.key), c.value, _country == c.key, () => setState(() {
                                  _country = c.key;
                                  _cat = null;
                                })),
                        ],
                      ),
                    ),
                    SizedBox(
                      height: 44,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        children: [
                          _chip('Todas', _cat == null, () => setState(() => _cat = null)),
                          for (final c in _availableCats)
                            _chip(c.name, _cat == c.id, () => setState(() => _cat = c.id)),
                        ],
                      ),
                    ),
                    Expanded(
                      child: list.isEmpty
                          ? const Center(child: Text('Sin canales'))
                          : GridView.builder(
                              padding: const EdgeInsets.all(12),
                              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 150,
                                mainAxisSpacing: 10,
                                crossAxisSpacing: 10,
                                childAspectRatio: 0.95,
                              ),
                              itemCount: list.length,
                              itemBuilder: (_, i) => _ChannelTile(channel: list[i], onTap: () => _open(list, i)),
                            ),
                    ),
                  ],
                ),
    );
  }
}

class _ChannelTile extends StatelessWidget {
  const _ChannelTile({required this.channel, required this.onTap});

  final Channel channel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                Expanded(
                  child: channel.logoUrl == null
                      ? const Icon(Icons.tv, size: 40)
                      : Image.network(
                          channel.logoUrl!,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const Icon(Icons.tv, size: 40),
                        ),
                ),
                const SizedBox(height: 6),
                Text(
                  channel.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      );
}
