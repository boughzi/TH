import 'package:supabase_flutter/supabase_flutter.dart';
import '../models.dart';
import 'crypto_service.dart';

SupabaseClient get sb => Supabase.instance.client;

class Api {
  /// locked | disabled | expired | ok
  static Future<String> accessStatus() async =>
      (await sb.rpc('access_status')) as String;

  static Future<bool> redeem(String code) async =>
      (await sb.rpc('redeem_code', params: {'p_code': code})) == true;

  static Future<String> contactText() async {
    final r = await sb.from('app_config').select('value').eq('key', 'contact_text').maybeSingle();
    return (r?['value'] as String?) ??
        'Contacta con el administrador para obtener tu código de activación.';
  }

  static Future<CryptoService> loadCrypto() async {
    final r = await sb.from('app_config').select('value').eq('key', 'aes_key').single();
    return CryptoService.fromHex(r['value'] as String);
  }

  static Future<List<Category>> categories() async {
    final r = await sb.from('categories').select('id,name').order('sort_order').order('name');
    return (r as List).map((e) => Category.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<List<Channel>> channels() async {
    final out = <Channel>[];
    var from = 0;
    while (true) {
      final r = await sb
          .from('channels')
          .select('id,name,country_code,country_name,category_id,logo_url,stream_url_enc')
          .order('sort_order')
          .order('name')
          .order('id')
          .range(from, from + 999);
      final list = r as List;
      out.addAll(list.map((e) => Channel.fromJson(e as Map<String, dynamic>)));
      if (list.length < 1000) break;
      from += 1000;
    }
    return out;
  }
}
