import 'package:clockifai/data/drift/database.dart';
import 'package:clockifai/features/presence/presence.dart';
import 'package:clockifai/features/presence/presence_log.dart';
import 'package:clockifai/features/presence/presence_settings.dart';
import 'package:clockifai/features/today/day_plan.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Présence chantier (plans/13-ux-moderne.md, lot 13) : journal de l'appareil, propositions, suivi.
DateTime at(int h, [int m = 0, int day = 26]) => DateTime(2026, 10, day, h, m);

Position pos(double lat, double lng, {double accuracy = 10}) => Position(
    latitude: lat, longitude: lng, timestamp: DateTime(2026), accuracy: accuracy, altitude: 0, altitudeAccuracy: 0,
    heading: 0, headingAccuracy: 0, speed: 0, speedAccuracy: 0);

Project project(String id, {double? lat, double? lng, int? radius, bool archived = false}) => Project(
    id: id, workspaceId: 'w', name: id, color: '#000000', billableDefault: true, isPublic: true, archived: archived,
    siteLat: lat, siteLng: lng, siteRadius: radius);

TimeEntry entry(String id, DateTime start, DateTime end, {String desc = '', String? project, String? task}) => TimeEntry(
    id: id, workspaceId: 'w', userId: 'me', projectId: project, taskId: task, description: desc, startAt: start.toUtc(),
    endAt: end.toUtc(), billable: true, locked: false);

void main() {
  group('journal', () {
    test('distance : 111 km par degré de latitude, 0 sur place', () {
      expect(distanceMeters(48, 2, 49, 2), closeTo(111195, 100));
      expect(distanceMeters(48.8566, 2.3522, 48.8566, 2.3522), 0);
      const site = Site(projectId: 'p', lat: 48.8566, lng: 2.3522);
      expect(site.contains(48.8575, 2.3522), isTrue, reason: '100 m');
      expect(site.contains(48.8588, 2.3522), isFalse, reason: '245 m');
      expect(site.contains(48.8588, 2.3522, accuracy: 150), isTrue, reason: 'position imprécise : marge de 100 m');
    });

    test('arrivée, présence, sortie, retour après la pause, départ', () {
      final log = PresenceLog()
        ..record(at(7, 52), {'dupuis'})
        ..record(at(10), {'dupuis'})
        ..record(at(12, 5), {}); // part déjeuner, vu dehors 2 h après la dernière position sur place
      var v = log.visitsOn(at(0)).single;
      expect((v.arrived, v.left), (at(7, 52), at(10)), reason: 'sortie datée de la dernière position vue sur place');
      log
        ..record(at(13, 20), {'dupuis'})
        ..record(at(16, 25), {'dupuis'})
        ..record(at(16, 31), {});
      v = log.visitsOn(at(0)).single;
      expect((v.arrived, v.lastSeen, v.left), (at(7, 52), at(16, 25), at(16, 31)), reason: 'même passage, sortie à l’instant');
    });

    test('deux chantiers le même jour ; encodé, relu ; quatorze jours gardés', () {
      final log = PresenceLog()
        ..record(at(8, 0, 1), {'vieux'})
        ..record(at(8), {'a'})
        ..record(at(10, 40), {'a'})
        ..record(at(10, 45), {'b'});
      final back = PresenceLog.decode(log.encode());
      expect([for (final v in back.visitsOn(at(0))) (v.projectId, v.arrived, v.left)], [('a', at(8), at(10, 45)), ('b', at(10, 45), null)]);
      expect(back.days.keys, ['2026-10-26'], reason: 'le 1er octobre a plus de quatorze jours');
      expect(PresenceLog.decode('pas du json').days, isEmpty);
    });
  });

  group('propositions', () {
    final typical = TypicalDay(start: 480, lunch: const Span(720, 780), end: 990, target: 450, fromHistory: false);
    final history = [entry('h', at(9, 0, 23), at(12, 0, 23), desc: 'Pose placo', project: 'dupuis', task: 'placo')];
    SiteVisit visit(DateTime a, DateTime? left, {DateTime? seen}) =>
        SiteVisit(projectId: 'dupuis', arrived: a, lastSeen: seen ?? left ?? a, left: left);

    test('heures détectées : à 5 minutes près, coupées par la pause, description et tâche de la dernière entrée', () {
      final plan = planDay(day: at(0), now: at(18), mine: const [], history: history, typical: typical,
          presence: [visit(at(7, 52), at(16, 31))]);
      final drafts = plan.drafts.where((d) => d.source == DraftSource.presence).toList();
      expect([for (final d in drafts) d.span], [const Span(470, 720), const Span(780, 990)]);
      expect((drafts.first.description, drafts.first.projectId, drafts.first.taskId), ('Pose placo', 'dupuis', 'placo'));
      expect(drafts.first.reasons.single.kind, ReasonKind.presence);
      expect((drafts.first.reasons.single.a, drafts.first.reasons.single.b), (472, 991));
    });

    test('règle « planning » : calé sur la journée type à moins de 30 minutes ; temps déjà saisi respecté', () {
      final plan = planDay(day: at(0), now: at(18), mine: [entry('m', at(14), at(15), project: 'interne')], history: history,
          typical: typical, presence: [visit(at(7, 52), at(17, 10))], presenceRounding: 'planning');
      final drafts = plan.drafts.where((d) => d.source == DraftSource.presence).toList();
      expect([for (final d in drafts) d.span], [const Span(480, 720), const Span(780, 840), const Span(900, 1030)],
          reason: '7:52 → 8:00 ; 17:10 est à 40 min de 16:30 : gardé');
      expect(drafts.first.reasons.map((r) => r.kind), [ReasonKind.presence, ReasonKind.presenceRounded]);
    });

    test('encore sur place : jusqu’à maintenant ; un autre jour ou une proposition ignorée : rien', () {
      var plan = planDay(day: at(0), now: at(10, 2), mine: const [], history: history, typical: typical, presence: [visit(at(7, 55), null)]);
      expect(plan.drafts.where((d) => d.source == DraftSource.presence).single.span, const Span(475, 600));
      expect(plan.drafts.first.reasons.single.b, -1);
      plan = planDay(day: at(0, 0, 27), now: at(10, 0, 27), mine: const [], history: history, typical: typical, presence: [visit(at(7, 55), at(9))]);
      expect(plan.drafts.where((d) => d.source == DraftSource.presence), isEmpty);
      plan = planDay(day: at(0), now: at(18), mine: const [], history: history, typical: typical,
          presence: [visit(at(8), at(12))], dismissed: {'site:dupuis:480'});
      expect(plan.drafts.where((d) => d.source == DraftSource.presence), isEmpty);
    });
  });

  group('position du chantier', () {
    test('collée d’une carte, avec virgule ou point-virgule ; hors limites refusée', () {
      expect(parseSite('48.8566, 2.3522'), (48.8566, 2.3522));
      expect(parseSite(' 48,8566 ; 2,3522 '), (48.8566, 2.3522));
      expect(parseSite('-33.86 151.21'), (-33.86, 151.21));
      expect(parseSite('95, 2'), isNull);
      expect(parseSite('Paris'), isNull);
      expect(formatSite(48.8566, 2.3522), '48.856600, 2.352200');
    });
  });

  group('suivi', () {
    final tracker = PresenceTracker.instance;
    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      PresenceTracker.positionsOverride = () => const Stream.empty();
    });
    tearDown(() async {
      await tracker.bindUser(await SharedPreferences.getInstance(), null);
      PresenceTracker.positionsOverride = null;
      debugDefaultTargetPlatformOverride = null;
    });

    test('positions comparées aux chantiers actifs ; journal gardé par personne, effacé à la déconnexion', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await tracker.bindUser(prefs, 'alex');
      expect(await tracker.enable(), PresenceStart.ok);
      tracker.setSites([
        project('dupuis', lat: 48.8566, lng: 2.3522),
        project('archive', lat: 48.8566, lng: 2.3522, archived: true),
        project('bureau'),
      ]);
      tracker.onPosition(pos(48.8567, 2.3523), at: at(8));
      tracker.onPosition(pos(48.90, 2.40), at: at(8, 10));
      expect([for (final v in tracker.log.value.visitsOn(at(0))) (v.projectId, v.arrived, v.left)], [('dupuis', at(8), at(8, 10))]);
      await Future<void>.delayed(Duration.zero);
      expect(prefs.getString('presence_log:alex'), contains('dupuis'));
      expect(prefs.getString('presence_log:alex'), isNot(contains('48.8')), reason: 'jamais de position dans le journal');

      await tracker.bindUser(prefs, null); // déconnexion
      expect(prefs.getString('presence_log:alex'), isNull);
      expect(prefs.getBool('presence_enabled:alex'), isNull);
      expect(tracker.enabled.value, isFalse);
    });
  });
}
