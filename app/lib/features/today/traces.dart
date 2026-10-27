import '../../core/services_api.dart';
import 'day_plan.dart';

/// Traces d'une journée (plans/13-ux-moderne.md, lots 4 et 11) : événements de son agenda et ses commits, lus par
/// le serveur (`GET /api/traces`). En ligne seulement : hors ligne, la journée se propose sans elles.
class DayTraces {
  const DayTraces({this.events = const [], this.commits = const [], this.calendar = 'none'});
  final List<CalendarEvent> events;
  final List<CommitTrace> commits;

  /// `ok`, `none` (pas d'agenda), ou la raison d'un échec de lecture.
  final String calendar;

  bool get isEmpty => events.isEmpty && commits.isEmpty;
  static const empty = DayTraces();
}

/// Lecture des traces, gardées cinq minutes par jour (la page se reconstruit souvent).
class TracesApi {
  static final _cache = <String, (DateTime, DayTraces)>{};

  /// Remplace la lecture (tests, sans serveur).
  static Future<DayTraces> Function(String workspaceId, DateTime day)? override;

  static Future<DayTraces> day(String workspaceId, DateTime day) async {
    if (override case final load?) return load(workspaceId, day);
    final key = '$workspaceId ${dayKey(day)}';
    final hit = _cache[key];
    if (hit != null && DateTime.now().difference(hit.$1).inMinutes < 5) return hit.$2;
    final from = DateTime(day.year, day.month, day.day);
    final json = await ServicesApi.get('/api/traces', {
      'workspace_id': workspaceId,
      'from': from.toUtc().toIso8601String(),
      'to': addDays(from, 1).toUtc().toIso8601String(),
    });
    final traces = DayTraces(
      calendar: json['calendar'] as String? ?? 'none',
      events: [
        for (final e in (json['events'] as List? ?? const []).cast<Map<String, dynamic>>())
          CalendarEvent(
            id: e['id'] as String,
            start: DateTime.parse(e['start'] as String),
            end: DateTime.parse(e['end'] as String),
            title: e['title'] as String? ?? '',
          ),
      ],
      commits: [
        for (final c in (json['commits'] as List? ?? const []).cast<Map<String, dynamic>>())
          CommitTrace(
            sha: c['sha'] as String,
            subject: c['subject'] as String? ?? '',
            at: DateTime.parse(c['at'] as String),
            repository: c['repository'] as String? ?? '',
            projectId: c['project_id'] as String?,
          ),
      ],
    );
    _cache[key] = (DateTime.now(), traces);
    return traces;
  }

  /// Après un changement d'agenda : tout est relu.
  static void forget() => _cache.clear();

  /// `{configured, host}` : l'adresse elle-même n'est jamais renvoyée.
  static Future<Map<String, dynamic>> calendarSource() => ServicesApi.get('/api/traces/calendar', const {});

  static Future<Map<String, dynamic>> setCalendar(String url) async {
    final res = await ServicesApi.put('/api/traces/calendar', {'url': url});
    forget();
    return res;
  }

  static Future<void> removeCalendar() async {
    await ServicesApi.delete('/api/traces/calendar', const {});
    forget();
  }
}
