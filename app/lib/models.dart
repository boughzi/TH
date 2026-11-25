String flagUrl(String code) => 'https://flagcdn.com/w80/$code.png';

class Category {
  Category({required this.id, required this.name});
  final String id;
  final String name;

  factory Category.fromJson(Map<String, dynamic> j) =>
      Category(id: j['id'] as String, name: j['name'] as String);
}

class Channel {
  Channel({
    required this.id,
    required this.name,
    required this.countryCode,
    required this.countryName,
    required this.streamEnc,
    this.categoryId,
    this.logoUrl,
  });

  final String id;
  final String name;
  final String countryCode;
  final String countryName;
  final String streamEnc; // URL cifrada (AES-256-GCM, base64)
  final String? categoryId;
  final String? logoUrl;

  factory Channel.fromJson(Map<String, dynamic> j) => Channel(
        id: j['id'] as String,
        name: j['name'] as String,
        countryCode: (j['country_code'] as String).toLowerCase(),
        countryName: j['country_name'] as String,
        streamEnc: j['stream_url_enc'] as String,
        categoryId: j['category_id'] as String?,
        logoUrl: j['logo_url'] as String?,
      );
}
