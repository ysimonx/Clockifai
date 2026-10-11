/// Configuration injectée à la compilation :
///   fvm flutter run --dart-define-from-file=config/local.json
/// (fichier généré par `make app-config` à partir de deploy/.env).
class AppConfig {
  /// URL publique de la passerelle Supabase (Kong).
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL', defaultValue: 'http://localhost:8000');

  /// Clé publique « anon » de Supabase (sans danger côté client : la RLS protège les données).
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// URL publique du service PowerSync.
  static const powersyncUrl = String.fromEnvironment('POWERSYNC_URL', defaultValue: 'http://localhost:8080');

  /// URL du service Flask (exports, invitations…). Vide = même origine que l'app web (`/api`).
  static const servicesUrl = String.fromEnvironment('SERVICES_URL', defaultValue: 'http://localhost:5050');

  /// Schéma de deep link utilisé pour les retours d'authentification sur mobile.
  static const authRedirectMobile = 'clockifai://login-callback';

  static bool get isConfigured => supabaseAnonKey.isNotEmpty;
}
