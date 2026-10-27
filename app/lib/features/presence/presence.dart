import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/drift/database.dart' show Project;
import '../../l10n/app_localizations.dart';
import 'presence_log.dart';

/// Résultat de l'activation de la présence chantier.
enum PresenceStart { ok, denied, serviceOff, unsupported }

/// Présence chantier (plans/13-ux-moderne.md, lot 13), côté téléphone : tant que la personne l'a activée sur cet
/// appareil, la position est suivie (y compris en arrière-plan), comparée aux chantiers du workspace, et seules les
/// heures d'arrivée et de départ sont notées dans le journal de l'appareil ([PresenceLog]). La position n'est ni
/// gardée ni envoyée ; le journal s'efface à la déconnexion.
class PresenceTracker {
  PresenceTracker._();
  static final instance = PresenceTracker._();

  /// Téléphones seulement : on ne va pas sur le chantier avec le Mac ni le navigateur.
  static bool get supported =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.android);

  SharedPreferences? _prefs;
  String? _userId;
  List<Site> _sites = const [];
  StreamSubscription<Position>? _sub;
  Timer? _heartbeat;

  /// Actif pour la personne connectée, sur cet appareil.
  final enabled = ValueNotifier(false);

  /// Le journal ; une nouvelle valeur à chaque arrivée ou départ noté.
  final log = ValueNotifier(PresenceLog());

  /// Langue du profil, pour la notification d'Android (« fr », « en »).
  String locale = 'fr';

  /// Remplace le suivi de position (tests).
  @visibleForTesting
  static Stream<Position> Function()? positionsOverride;

  String get _enabledKey => 'presence_enabled:$_userId';
  String get _logKey => 'presence_log:$_userId';

  /// À la connexion (et au démarrage) : réglage et journal de cette personne ; à la déconnexion, son journal
  /// s'efface, comme les données locales.
  Future<void> bindUser(SharedPreferences prefs, String? userId) async {
    if (userId == _userId && _prefs != null) return;
    final previous = _userId;
    _prefs = prefs;
    await _stop();
    if (userId == null && previous != null) {
      await prefs.remove('presence_log:$previous');
      await prefs.remove('presence_enabled:$previous');
    }
    _userId = userId;
    enabled.value = userId != null && supported && (prefs.getBool(_enabledKey) ?? false);
    log.value = userId == null ? PresenceLog() : PresenceLog.decode(prefs.getString(_logKey));
    if (enabled.value) unawaited(_start());
  }

  /// Chantiers du workspace courant : projets actifs dont la position est réglée.
  void setSites(List<Project> projects) => _sites = [
        for (final p in projects)
          if (!p.archived && p.siteLat != null && p.siteLng != null)
            Site(projectId: p.id, lat: p.siteLat!, lng: p.siteLng!, radius: p.siteRadius ?? Site.defaultRadius),
      ];

  /// Demande l'accès à la position (« toujours » de préférence, pour l'arrière-plan), puis commence le suivi.
  Future<PresenceStart> enable() async {
    if (!supported || _userId == null) return PresenceStart.unsupported;
    if (positionsOverride == null) {
      if (!await Geolocator.isLocationServiceEnabled()) return PresenceStart.serviceOff;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) return PresenceStart.denied;
    }
    await _prefs?.setBool(_enabledKey, true);
    enabled.value = true;
    await _start();
    return PresenceStart.ok;
  }

  Future<void> disable() async {
    await _stop();
    await _prefs?.setBool(_enabledKey, false);
    enabled.value = false;
  }

  /// Efface les heures notées pour [day], ou tout le journal.
  Future<void> forget([DateTime? day]) async {
    final l = log.value..forget(day);
    log.value = PresenceLog(l.days);
    await _save();
  }

  Future<void> _start() async {
    await _stop();
    final l = lookupAppLocalizations(Locale(locale == 'en' ? 'en' : 'fr'));
    final stream = positionsOverride?.call() ??
        Geolocator.getPositionStream(
          locationSettings: defaultTargetPlatform == TargetPlatform.android
              ? AndroidSettings(
                  accuracy: LocationAccuracy.medium,
                  distanceFilter: 50,
                  intervalDuration: const Duration(minutes: 2),
                  // Service au premier plan : Android garde le suivi actif, avec une notification discrète.
                  foregroundNotificationConfig: ForegroundNotificationConfig(
                    notificationTitle: 'Clockifai',
                    notificationText: l.presenceNotification,
                    notificationChannelName: l.presenceTitle,
                  ),
                )
              : AppleSettings(
                  accuracy: LocationAccuracy.medium,
                  distanceFilter: 50,
                  activityType: ActivityType.otherNavigation,
                  // Sans pause : iOS ne relancerait pas le suivi de lui-même en arrière-plan.
                  pauseLocationUpdatesAutomatically: false,
                  allowBackgroundLocationUpdates: true,
                  // L'indicateur bleu dit que la position est suivie ; il suffit d'un accès « pendant l'utilisation ».
                  showBackgroundLocationIndicator: true,
                ),
        );
    _sub = stream.listen(onPosition, onError: (Object _) {}); // accès retiré en cours de route : plus rien n'arrive
    // Le flux ne donne une position qu'en mouvement : immobile sur le chantier, une relève toutes les 5 minutes garde
    // la dernière présence à jour, et la sortie se date à 5 minutes près.
    if (positionsOverride == null) {
      _heartbeat = Timer.periodic(const Duration(minutes: 5), (_) async {
        try {
          onPosition(await Geolocator.getCurrentPosition(
              locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 30))));
        } catch (_) {
          // pas de position cette fois-ci
        }
      });
    }
  }

  Future<void> _stop() async {
    _heartbeat?.cancel();
    _heartbeat = null;
    await _sub?.cancel();
    _sub = null;
  }

  /// Une position : les chantiers qui la contiennent, l'heure, et rien d'autre.
  @visibleForTesting
  void onPosition(Position p, {DateTime? at}) {
    final inside = {
      for (final s in _sites)
        if (s.contains(p.latitude, p.longitude, accuracy: p.accuracy)) s.projectId,
    };
    final l = log.value..record(at ?? DateTime.now(), inside);
    log.value = PresenceLog(l.days);
    unawaited(_save());
  }

  Future<void> _save() async {
    if (_userId == null) return;
    await _prefs?.setString(_logKey, log.value.encode());
  }
}
