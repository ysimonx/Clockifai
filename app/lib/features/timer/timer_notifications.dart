import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../data/drift/database.dart';

/// Notification persistante « chronomètre en cours » sur iOS / Android.
/// Utilise un compteur natif (chronomètre Android) : aucun réveil de l'app n'est nécessaire.
class TimerNotifications {
  TimerNotifications._();
  static final instance = TimerNotifications._();

  static const _id = 1;
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  String? _shownFor;

  bool get _supported => !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  Future<void> init() async {
    if (!_supported || _ready) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(requestAlertPermission: false, requestBadgePermission: false, requestSoundPermission: false),
      ),
    );
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true);
    _ready = true;
  }

  Future<void> show(TimeEntry? running, {String? title, String? subtitle}) async {
    if (!_supported) return;
    try {
      await init();
      if (running == null) {
        if (_shownFor != null) await _plugin.cancel(id: _id);
        _shownFor = null;
        return;
      }
      final key = '${running.id}:$title:$subtitle';
      if (key == _shownFor) return;
      _shownFor = key;
      await _plugin.show(
        id: _id,
        title: title,
        body: subtitle,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            'timer',
            'Chronomètre',
            channelDescription: 'Chronomètre en cours',
            importance: Importance.low,
            priority: Priority.low,
            ongoing: true,
            onlyAlertOnce: true,
            showWhen: true,
            usesChronometer: true,
            when: running.startAt.millisecondsSinceEpoch,
          ),
          iOS: const DarwinNotificationDetails(presentSound: false, presentBadge: false),
        ),
      );
    } catch (e) {
      debugPrint('Notification chronomètre indisponible : $e');
    }
  }
}
