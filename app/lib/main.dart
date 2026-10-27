import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:logging/logging.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'core/catalog.dart';
import 'core/di.dart';
import 'core/display_prefs.dart';
import 'core/l10n.dart';
import 'core/locale_controller.dart';
import 'core/session.dart';
import 'core/theme.dart';
import 'features/presence/presence.dart';
import 'features/timer/menu_bar.dart';
import 'features/today/day_recap.dart';
import 'router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();
  Logger.root.level = Level.INFO;
  Logger.root.onRecord.listen((r) => debugPrint('[${r.loggerName}] ${r.level.name}: ${r.message}'));
  // Erreurs d'affichage et erreurs asynchrones non interceptées : journalisées même en release.
  final log = Logger('clockifai');
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    log.severe('FlutterError: ${details.exceptionAsString()}\n${details.stack}');
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    log.severe('Uncaught: $error\n$stack');
    return true;
  };

  await initializeDateFormatting();
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    publishableKey: AppConfig.supabaseAnonKey.isEmpty ? 'missing-key' : AppConfig.supabaseAnonKey,
    // Flux implicite : les liens magiques et d'invitation fonctionnent même ouverts sur un autre
    // appareil que celui qui les a demandés (le PKCE l'interdit).
    authOptions: const FlutterAuthClientOptions(authFlowType: AuthFlowType.implicit),
  );
  await setupDependencies();
  final prefs = await SharedPreferences.getInstance();
  runApp(ClockifaiApp(prefs: prefs));
}

class ClockifaiApp extends StatefulWidget {
  const ClockifaiApp({super.key, required this.prefs});
  final SharedPreferences prefs;

  @override
  State<ClockifaiApp> createState() => _ClockifaiAppState();
}

class _ClockifaiAppState extends State<ClockifaiApp> {
  late final SessionController _session = SessionController(sync: syncService, workspaces: workspaceRepo, prefs: widget.prefs);
  late final CatalogController _catalog = CatalogController(catalogRepo, workspaceRepo, teamRepo);
  late final LocaleController _locale = LocaleController(widget.prefs);
  late final DisplayPrefs _display = DisplayPrefs(widget.prefs);
  late final GoRouter _router = buildRouter(_session);

  @override
  void initState() {
    super.initState();
    _session.addListener(_bindCatalog);
    _bindCatalog();
    // Fin de journée (plan 13, lot 6) : toucher la notification ouvre « Aujourd'hui » ; sur téléphone, la notification
    // est reprogrammée quand le réglage, le fuseau ou la langue du profil changent.
    RecapNotifications.instance.onOpen = () => _router.go('/today');
    _session.addListener(_scheduleRecap);
    _display.addListener(_scheduleRecap);
    // Présence chantier (plan 13, lot 13) : réglage et journal de la personne connectée, chantiers du workspace.
    _session.addListener(_bindPresence);
    _catalog.addListener(_bindSites);
    _bindPresence();
  }

  void _bindPresence() {
    PresenceTracker.instance.locale = _session.profile?.locale ?? 'fr';
    PresenceTracker.instance.bindUser(widget.prefs, _session.userId);
  }

  void _bindSites() => PresenceTracker.instance.setSites(_catalog.projects);

  void _bindCatalog() => _catalog.bind(_session.workspaceId);

  String? _recapKey;

  void _scheduleRecap() {
    final profile = _session.profile;
    if (!_session.isSignedIn || profile == null) return;
    final key = '${_display.dayRecap} ${_display.dayRecapTime} ${profile.timezone} ${profile.locale}';
    if (key == _recapKey) return;
    _recapKey = key;
    final l = lookupAppLocalizations(Locale(profile.locale == 'en' ? 'en' : 'fr'));
    RecapNotifications.instance.schedule(
      enabled: _display.dayRecap,
      time: _display.dayRecapTime,
      timezone: profile.timezone,
      title: l.recapTitle,
      body: l.recapNotificationBody,
    );
  }

  @override
  void dispose() {
    _session.removeListener(_bindCatalog);
    _session.removeListener(_scheduleRecap);
    _display.removeListener(_scheduleRecap);
    _session.removeListener(_bindPresence);
    _catalog.removeListener(_bindSites);
    _session.dispose();
    _catalog.dispose();
    _locale.dispose();
    _display.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _session),
        ChangeNotifierProvider.value(value: _catalog),
        ChangeNotifierProvider.value(value: _locale),
        ChangeNotifierProvider.value(value: _display),
      ],
      child: Consumer2<LocaleController, DisplayPrefs>(
        builder: (context, locale, display, _) => MaterialApp.router(
          title: 'Clockifai',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(Brightness.light),
          darkTheme: buildTheme(Brightness.dark),
          themeMode: display.themeMode,
          locale: locale.locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          routerConfig: _router,
          // macOS : icône du chronomètre dans la barre de menus (sans effet ailleurs).
          builder: (context, child) => MacMenuBar(onOpenToday: () => _router.go('/today'), child: child!),
        ),
      ),
    );
  }
}
