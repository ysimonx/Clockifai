import 'dart:convert';
import 'dart:math' as math;

/// Présence chantier (plans/13-ux-moderne.md, lot 13) : le téléphone note quand il entre dans le périmètre d'un
/// chantier et quand il en sort. Calcul pur, sans plugin : le journal ne garde que des heures et des projets, jamais
/// de position, et ne quitte pas l'appareil.

/// Distance en mètres entre deux points (formule de haversine).
double distanceMeters(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371000.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(lat2 - lat1), dLng = rad(lng2 - lng1);
  final a = math.pow(math.sin(dLat / 2), 2) + math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(dLng / 2), 2);
  return 2 * r * math.asin(math.sqrt(a));
}

/// Un chantier : le périmètre d'un projet.
class Site {
  const Site({required this.projectId, required this.lat, required this.lng, this.radius = defaultRadius});
  static const defaultRadius = 150;
  final String projectId;
  final double lat;
  final double lng;
  final int radius;

  bool contains(double lat, double lng, {double accuracy = 0}) =>
      // Une position imprécise compte jusqu'à 100 m de marge : mieux vaut une arrivée de trop, à confirmer.
      distanceMeters(this.lat, this.lng, lat, lng) <= radius + math.min(accuracy, 100);
}

/// Un passage sur un chantier, un jour : première arrivée, dernière position vue sur place, départ (null : encore
/// sur place). Une sortie puis un retour le même jour (pause de midi ailleurs) prolongent le même passage.
class SiteVisit {
  SiteVisit({required this.projectId, required this.arrived, required this.lastSeen, this.left});
  final String projectId;
  final DateTime arrived;
  DateTime lastSeen;
  DateTime? left;

  Map<String, dynamic> toJson() => {
        'p': projectId,
        'a': arrived.toUtc().toIso8601String(),
        's': lastSeen.toUtc().toIso8601String(),
        if (left != null) 'l': left!.toUtc().toIso8601String(),
      };

  static SiteVisit? fromJson(Object? j) {
    if (j is! Map) return null;
    final a = DateTime.tryParse('${j['a']}'), s = DateTime.tryParse('${j['s']}');
    if (j['p'] is! String || a == null || s == null) return null;
    return SiteVisit(projectId: j['p'] as String, arrived: a.toLocal(), lastSeen: s.toLocal(), left: DateTime.tryParse('${j['l']}')?.toLocal());
  }
}

/// Le journal de l'appareil : par jour (`yyyy-MM-dd`, heure locale), un passage par chantier ; quatorze jours gardés.
class PresenceLog {
  PresenceLog([Map<String, Map<String, SiteVisit>>? days]) : days = days ?? {};
  final Map<String, Map<String, SiteVisit>> days;

  static const keepDays = 14;

  /// Sans position pendant plus longtemps, la sortie est datée de la dernière position vue sur place.
  static const gap = Duration(minutes: 15);

  static String _key(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  List<SiteVisit> visitsOn(DateTime day) => [...?days[_key(day)]?.values]..sort((a, b) => a.arrived.compareTo(b.arrived));

  /// Une position à [now] : [inside] = les chantiers dont le périmètre la contient.
  void record(DateTime now, Set<String> inside) {
    final day = days.putIfAbsent(_key(now), () => {});
    for (final id in inside) {
      final v = day[id];
      if (v == null) {
        day[id] = SiteVisit(projectId: id, arrived: now, lastSeen: now);
      } else {
        v.lastSeen = now;
        v.left = null;
      }
    }
    for (final v in day.values) {
      if (inside.contains(v.projectId) || v.left != null) continue;
      v.left = now.difference(v.lastSeen) <= gap ? now : v.lastSeen;
    }
    final oldest = _key(DateTime(now.year, now.month, now.day - keepDays));
    days.removeWhere((k, _) => k.compareTo(oldest) < 0);
  }

  /// Efface un jour (« Oublier »), ou tout.
  void forget([DateTime? day]) => day == null ? days.clear() : days.remove(_key(day));

  String encode() => jsonEncode({
        for (final e in days.entries) e.key: [for (final v in e.value.values) v.toJson()],
      });

  static PresenceLog decode(String? text) {
    final log = PresenceLog();
    if (text == null || text.isEmpty) return log;
    try {
      final j = jsonDecode(text);
      if (j is! Map) return log;
      j.forEach((k, list) {
        if (k is! String || list is! List) return;
        log.days[k] = {for (final v in list.map(SiteVisit.fromJson).nonNulls) v.projectId: v};
      });
    } on FormatException {
      // journal illisible : on repart de zéro
    }
    return log;
  }
}
