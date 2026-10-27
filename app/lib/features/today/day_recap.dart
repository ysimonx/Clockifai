import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../core/catalog.dart';
import '../../core/di.dart';
import '../../core/display_prefs.dart';
import '../../core/format.dart';
import '../../core/l10n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../../data/repositories/time_entry_repository.dart';
import '../presence/presence.dart' show PresenceTracker;
import 'day_plan.dart';
import 'quick_place.dart';
import 'traces.dart';

/// Fin de journée (plans/13-ux-moderne.md, lot 6) : à l'heure choisie, le temps saisi du jour et les propositions
/// à cocher, confirmées d'un geste. Dans l'app (web, Mac : bandeau, et notification sur Mac), dans la barre de
/// menus du Mac, et en notification programmée sur téléphone (l'app n'y tourne pas en arrière-plan).

/// La journée d'aujourd'hui telle que la page « Aujourd'hui » la propose (mêmes sources), lue une fois.
Future<DayPlan> loadTodayPlan(BuildContext context, DateTime now) async {
  final session = context.read<SessionController>();
  final catalog = context.read<CatalogController>();
  final prefs = context.read<DisplayPrefs>();
  final ws = session.workspaceId!, me = session.userId!;
  final day = DateTime(now.year, now.month, now.day);
  final next = addDays(day, 1);
  final rows = await entriesRepo.watchEntries(workspaceId: ws, userId: me, from: addDays(day, -35), to: next, includeRunning: true).first;
  final agentId = catalog.agentsOf(me).firstOrNull?.userId;
  final agentRows = agentId == null
      ? const <EntryRow>[]
      : await entriesRepo.watchEntries(workspaceId: ws, userId: agentId, from: day, to: next, includeRunning: true).first;
  final planning = await modulesRepo.watchAssignments(ws, userId: me, from: day, to: next).first;
  var traces = DayTraces.empty;
  try {
    traces = await TracesApi.day(ws, day);
  } catch (_) {
    // hors ligne : la journée se propose sans traces
  }
  return planDay(
    day: day,
    now: now,
    mine: [for (final r in rows) if (!r.entry.startAt.toLocal().isBefore(day)) r.entry],
    history: [for (final r in rows) if (r.entry.startAt.toLocal().isBefore(day)) r.entry],
    agentEntries: [for (final r in agentRows) r.entry],
    planning: planning,
    dismissed: prefs.dismissedSuggestions,
    typical: TypicalDay.ofProfile(session.profile),
    calendar: traces.events,
    commits: traces.commits,
    presence: [for (final v in PresenceTracker.instance.log.value.visitsOn(day)) if (catalog.project(v.projectId) != null) v],
    presenceRounding: session.workspace?.presenceRounding,
    guessProject: (text) {
      final q = parseQuick(text, catalog, now);
      return q?.projectId == null ? null : (projectId: q!.projectId, taskId: q.taskId);
    },
  );
}

/// « 6:30 saisies sur 7:30 · 2 propositions à confirmer ».
String recapLine(AppLocalizations l, DayPlan plan) {
  final logged = formatHm(plan.loggedMinutes * 60);
  final target = formatHm(plan.typical.target * 60);
  return plan.drafts.isEmpty ? l.recapLineDone(logged, target) : l.recapLine(logged, target, plan.drafts.length);
}

/// Le récapitulatif : les propositions cochées par défaut, confirmées d'un geste (Annuler les retire).
Future<void> showDayRecap(BuildContext context, {DateTime Function() clock = DateTime.now}) async {
  final now = clock();
  final plan = await loadTodayPlan(context, now);
  if (!context.mounted) return;
  await showDialog<void>(context: context, builder: (_) => _RecapDialog(plan: plan, now: now));
}

class _RecapDialog extends StatefulWidget {
  const _RecapDialog({required this.plan, required this.now});
  final DayPlan plan;
  final DateTime now;

  @override
  State<_RecapDialog> createState() => _RecapDialogState();
}

class _RecapDialogState extends State<_RecapDialog> {
  late final _checked = {for (final d in widget.plan.drafts) d.key};

  Future<void> _confirm() async {
    final l = context.l10n;
    final session = context.read<SessionController>();
    final catalog = context.read<CatalogController>();
    final ws = session.workspaceId!, me = session.userId!;
    final day = DateTime(widget.now.year, widget.now.month, widget.now.day);
    final chosen = [for (final d in widget.plan.drafts) if (_checked.contains(d.key)) d];
    final ids = <String>[];
    for (final d in chosen) {
      ids.add(await entriesRepo.createManual(
        workspaceId: ws,
        userId: me,
        start: atMinute(day, d.span.start),
        end: atMinute(day, d.span.end),
        createdBy: me,
        draft: EntryDraft(
          description: d.description,
          projectId: d.projectId,
          taskId: d.taskId,
          billable: catalog.billableFor(projectId: d.projectId, userId: me),
          hourlyRateCents: catalog.rateFor(projectId: d.projectId, userId: me),
        ),
      ));
    }
    if (!mounted) return;
    final minutes = chosen.fold(0, (a, d) => a + d.span.length);
    showUndo(context, l.journalAdded(chosen.length, formatHm(minutes * 60)), () => entriesRepo.deleteMany(ids));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final catalog = context.watch<CatalogController>();
    final plan = widget.plan;
    return AlertDialog(
      title: Text(l.recapTitle),
      content: SizedBox(
        width: 480,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(recapLine(l, plan), style: theme.textTheme.bodyMedium),
          const SizedBox(height: 8),
          if (plan.drafts.isEmpty)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.check_circle, color: AppColors.of(context).success),
              title: Text(l.recapNothing),
            )
          else
            Flexible(
              child: ListView(shrinkWrap: true, children: [
                for (final d in plan.drafts)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _checked.contains(d.key),
                    onChanged: (v) => setState(() => v == true ? _checked.add(d.key) : _checked.remove(d.key)),
                    title: Text(d.description.isEmpty ? (catalog.project(d.projectId)?.name ?? l.noDescription) : d.description),
                    subtitle: Text([
                      '${hm(d.span.start)} – ${hm(d.span.end)}',
                      ?catalog.project(d.projectId)?.name,
                    ].join(' · ')),
                  ),
              ]),
            ),
        ]),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(context);
            GoRouter.of(context).go('/today');
          },
          child: Text(l.recapOpenDay),
        ),
        if (plan.drafts.isNotEmpty)
          FilledButton(onPressed: _checked.isEmpty ? null : _confirm, child: Text(l.recapConfirm(_checked.length)))
        else
          FilledButton(onPressed: () => Navigator.pop(context), child: Text(l.close)),
      ],
    );
  }
}

/// Le récapitulatif du jour, s'il est dû : pour la barre de menus du Mac (null sinon).
final recapNotice = ValueNotifier<String?>(null);

/// Surveille l'heure du récapitulatif tant que l'app tourne (web, Mac) : bandeau au-dessus de la page, et sur Mac
/// une notification. Une fois par jour et par appareil.
class DayRecapBanner extends StatefulWidget {
  const DayRecapBanner({super.key, this.clock = DateTime.now});
  final DateTime Function() clock;

  @override
  State<DayRecapBanner> createState() => _DayRecapBannerState();
}

class _DayRecapBannerState extends State<DayRecapBanner> {
  Timer? _tick;
  String? _line;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(minutes: 1), (_) => _check());
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    if (!mounted) return;
    final prefs = context.read<DisplayPrefs>();
    final now = widget.clock();
    final today = dayKey(now);
    final at = parseHm(prefs.dayRecapTime) ?? 1050;
    if (!prefs.dayRecap || prefs.dayRecapShown == today || now.hour * 60 + now.minute < at || now.weekday > DateTime.friday) return;
    final l = context.l10n;
    await prefs.markDayRecapShown(today);
    if (!mounted) return;
    final plan = await loadTodayPlan(context, now);
    if (!mounted) return;
    final line = recapLine(l, plan);
    setState(() => _line = line);
    recapNotice.value = line;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS) await RecapNotifications.instance.showNow(l.recapTitle, line);
  }

  void _close() {
    setState(() => _line = null);
    recapNotice.value = null;
  }

  @override
  Widget build(BuildContext context) {
    final line = _line;
    if (line == null) return const SizedBox.shrink();
    final l = context.l10n;
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(children: [
          Icon(Icons.nights_stay_outlined, color: theme.colorScheme.onSecondaryContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text('${l.recapTitle} · $line', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSecondaryContainer)),
          ),
          TextButton(onPressed: _close, child: Text(l.recapLater)),
          FilledButton.tonal(
            onPressed: () async {
              _close();
              await showDayRecap(context, clock: widget.clock);
            },
            child: Text(l.recapReview),
          ),
        ]),
      ),
    );
  }
}

/// Notifications du récapitulatif : immédiate sur Mac (l'app tourne dans la barre de menus), programmée chaque jour
/// ouvré sur iPhone et Android. Toucher la notification ouvre « Aujourd'hui » ([onOpen]).
class RecapNotifications {
  RecapNotifications._();
  static final instance = RecapNotifications._();

  static const _id = 2;
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  /// Ouvre la page « Aujourd'hui » (posé par l'app, qui connaît le routeur).
  VoidCallback? onOpen;

  bool get _mobile => !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);
  bool get _mac => !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  Future<void> _init() async {
    if (_ready) return;
    const darwin = DarwinInitializationSettings(requestAlertPermission: true, requestBadgePermission: false, requestSoundPermission: false);
    await _plugin.initialize(
      settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher'), iOS: darwin, macOS: darwin),
      onDidReceiveNotificationResponse: (r) {
        if (r.payload == 'today') onOpen?.call();
      },
    );
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true && launch?.notificationResponse?.payload == 'today') onOpen?.call();
    _ready = true;
  }

  Future<void> showNow(String title, String body) async {
    if (!_mac) return;
    try {
      await _init();
      await _plugin.show(id: _id, title: title, body: body, payload: 'today', notificationDetails: const NotificationDetails(macOS: DarwinNotificationDetails()));
    } catch (e) {
      debugPrint('Notification de fin de journée indisponible : $e');
    }
  }

  /// Notification immédiate (Mac, téléphone), l'app étant ouverte : une relance reçue, par exemple.
  Future<void> alert(String title, String body) async {
    if (!_mac && !_mobile) return;
    try {
      await _init();
      await _plugin.show(
        id: 3,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails('reminders', 'Relances', channelDescription: 'Relances de feuille de temps'),
          iOS: DarwinNotificationDetails(),
          macOS: DarwinNotificationDetails(),
        ),
      );
    } catch (e) {
      debugPrint('Notification indisponible : $e');
    }
  }

  /// Téléphone : une notification chaque jour ouvré à [time] (« 17:30 »), dans le fuseau du profil ; rien si
  /// [enabled] est faux.
  Future<void> schedule({required bool enabled, required String time, required String timezone, required String title, required String body}) async {
    if (!_mobile) return;
    try {
      await _init();
      for (var weekday = DateTime.monday; weekday <= DateTime.friday; weekday++) {
        await _plugin.cancel(id: _id * 10 + weekday);
      }
      final minutes = parseHm(time);
      if (!enabled || minutes == null) return;
      tzdata.initializeTimeZones();
      final location = tz.getLocation(timezone);
      final now = tz.TZDateTime.now(location);
      for (var weekday = DateTime.monday; weekday <= DateTime.friday; weekday++) {
        var at = tz.TZDateTime(location, now.year, now.month, now.day, minutes ~/ 60, minutes % 60);
        while (at.weekday != weekday || at.isBefore(now)) {
          at = at.add(const Duration(days: 1));
        }
        await _plugin.zonedSchedule(
          id: _id * 10 + weekday,
          title: title,
          body: body,
          scheduledDate: at,
          payload: 'today',
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails('day_recap', 'Fin de journée', channelDescription: 'Récapitulatif de fin de journée'),
            iOS: DarwinNotificationDetails(),
          ),
        );
      }
    } catch (e) {
      debugPrint('Programmation du récapitulatif impossible : $e');
    }
  }
}
