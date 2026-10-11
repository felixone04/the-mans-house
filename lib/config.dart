/// Configurazione passata in fase di build:
///   flutter run --dart-define-from-file=config.json
/// Se le chiavi Supabase mancano l'app parte in modalita' DEMO (dati locali).
class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Deep link usato da Google / Apple per tornare nell'app dopo il login.
  static const authRedirect = 'themanshouse://login-callback';

  static bool get hasSupabase =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
