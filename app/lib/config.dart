/// Se pasan al compilar:
/// flutter run --dart-define=SUPABASE_URL=https://xxx.supabase.co --dart-define=SUPABASE_ANON_KEY=xxx
class Config {
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://TU-PROYECTO.supabase.co',
  );
  static const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'TU_ANON_KEY',
  );

  /// Debe coincidir con el deep link del AndroidManifest y con
  /// Authentication → URL Configuration → Redirect URLs en Supabase.
  static const oauthRedirect = 'io.supabase.livetv://login-callback/';
}
