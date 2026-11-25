import 'dart:convert';
import 'package:cryptography/cryptography.dart';

/// Descifra URLs AES-256-GCM. Formato: base64(nonce[12] || ciphertext || tag[16]).
/// La clave (64 hex) solo vive en memoria; nunca se guarda en disco.
class CryptoService {
  CryptoService(this._key);

  factory CryptoService.fromHex(String hex) {
    final h = hex.trim();
    if (h.length != 64) {
      throw const FormatException('La clave AES debe tener 64 caracteres hex (256 bits)');
    }
    return CryptoService([
      for (var i = 0; i < h.length; i += 2) int.parse(h.substring(i, i + 2), radix: 16),
    ]);
  }

  final List<int> _key;
  static final _algo = AesGcm.with256bits();

  Future<String> decrypt(String b64) async {
    final box = SecretBox.fromConcatenation(
      base64.decode(b64),
      nonceLength: 12,
      macLength: 16,
    );
    final clear = await _algo.decrypt(box, secretKey: SecretKey(_key));
    return utf8.decode(clear);
  }
}
