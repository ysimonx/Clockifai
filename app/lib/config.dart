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

  /// Guide d'utilisation (docs/guide). Vide = `/guide/` de [servicesUrl] (ou de l'origine de l'app web), servi par
  /// le Caddy de prod ; en local, `make docs-serve` (http://localhost:3200/guide/, écrit par `make app-config`).
  static const guideUrl = String.fromEnvironment('GUIDE_URL');

  /// Schéma de deep link utilisé pour les retours d'authentification sur mobile.
  static const authRedirectMobile = 'clockifai://login-callback';

  static bool get isConfigured => supabaseAnonKey.isNotEmpty;

  /// Backend de développement (pile Docker locale) plutôt que la production.
  static bool get isLocal => isLocalServer(supabaseUrl);

  /// Serveur affiché sur l'écran de connexion : « localhost:8000 », « supabase.clockifai.kysoe.com ».
  static String get serverLabel {
    final uri = Uri.tryParse(supabaseUrl);
    if (uri == null || uri.host.isEmpty) return supabaseUrl;
    return uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
  }
}

/// Vrai pour un serveur de développement : localhost, `.local`, émulateur Android (10.0.2.2), adresses privées.
bool isLocalServer(String url) {
  final host = Uri.tryParse(url)?.host ?? '';
  if (host == 'localhost' || host == '::1' || host.endsWith('.local')) return true;
  final ip = host.split('.').map(int.tryParse).toList();
  if (ip.length != 4 || ip.contains(null)) return false;
  final a = ip[0]!, b = ip[1]!;
  return a == 127 || a == 10 || (a == 192 && b == 168) || (a == 172 && b >= 16 && b <= 31);
}
