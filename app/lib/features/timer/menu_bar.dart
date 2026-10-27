import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../core/catalog.dart';
import '../../core/di.dart';
import '../../core/l10n.dart';
import '../../core/session.dart';
import '../../data/drift/database.dart';
import '../../data/repositories/time_entry_repository.dart';
import '../today/day_plan.dart' show addDays;
import '../today/quick_place.dart';
import 'timer_rules.dart';

/// Icône de la barre de menus macOS (en haut à droite de l'écran), comme celle de Clockify :
/// un clic ouvre un petit panneau pour démarrer / arrêter le chronomètre, reprendre une entrée
/// récente, saisir une ligne en clair (« 1h20 réunion site », ⌥⌘T de n'importe où) ou ouvrir la fenêtre de
/// l'application.
///
/// Le panneau est natif (`macos/Runner/MenuBar*.swift`) et n'a pas accès aux données : ce widget
/// lui envoie l'état (`update`) et exécute ses commandes sur la base locale, comme la barre du
/// chronomètre. Il fonctionne fenêtre fermée : le moteur Flutter reste actif tant que l'app tourne.
class MacMenuBar extends StatefulWidget {
  const MacMenuBar({super.key, required this.child});
  final Widget child;

  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  @override
  State<MacMenuBar> createState() => _MacMenuBarState();
}

class _MacMenuBarState extends State<MacMenuBar> {
  static const _channel = MethodChannel('clockifai/menu_bar');

  late SessionController _session;
  late CatalogController _catalog;
  late AppLocalizations _l;

  StreamSubscription<TimeEntry?>? _runningSub;
  StreamSubscription<List<EntryRow>>? _recentSub;
  String? _boundKey;
  TimeEntry? _running;
  List<EntryRow> _recent = const [];
  bool _pushScheduled = false;
  String? _lastSent;

  @override
  void initState() {
    super.initState();
    if (MacMenuBar.supported) _channel.setMethodCallHandler(_onCall);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!MacMenuBar.supported) return;
    _session = context.watch<SessionController>();
    _catalog = context.watch<CatalogController>();
    _l = context.l10n;
    final ws = _session.workspaceId;
    final user = _session.userId;
    final key = '$ws:$user';
    if (key != _boundKey) {
      _boundKey = key;
      _runningSub?.cancel();
      _recentSub?.cancel();
      _running = null;
      _recent = const [];
      if (ws != null && user != null) {
        _runningSub = entriesRepo.watchRunning(ws, user).listen((e) {
          _running = e;
          _schedulePush();
        });
        _recentSub = entriesRepo.watchRecent(ws, user).listen((rows) {
          _recent = rows;
          _schedulePush();
        });
      }
    }
    _schedulePush();
  }

  @override
  void dispose() {
    if (MacMenuBar.supported) _channel.setMethodCallHandler(null);
    _runningSub?.cancel();
    _recentSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;

  // ------------------------------------------------------------------ état → panneau

  /// Regroupe les changements simultanés (session, référentiel, chronomètre) en un seul envoi.
  void _schedulePush() {
    if (_pushScheduled) return;
    _pushScheduled = true;
    scheduleMicrotask(() {
      _pushScheduled = false;
      if (mounted) _push();
    });
  }

  Map<String, Object?> _entry(TimeEntry e) {
    final project = _catalog.project(e.projectId);
    return {
      'id': e.id,
      'description': e.description,
      'projectId': e.projectId,
      'project': project?.name,
      'client': _catalog.client(project?.clientId)?.name,
      'task': _catalog.task(e.taskId)?.name,
      'color': project?.color,
    };
  }

  Future<void> _push() async {
    final l = _l;
    final running = _running;
    final state = {
      'signedIn': _session.isSignedIn,
      'firstSync': _session.waitingForFirstSync,
      'ready': _session.workspace != null,
      'running': running == null ? null : {..._entry(running), 'start': running.startAt.millisecondsSinceEpoch},
      'recent': [for (final r in _recent) _entry(r.entry)],
      'projects': [
        for (final p in _catalog.activeProjects)
          {'id': p.id, 'name': p.name, 'client': _catalog.client(p.clientId)?.name, 'color': p.color},
      ],
      'labels': {
        'whatAreYouWorkingOn': l.whatAreYouWorkingOn,
        'project': l.project,
        'noProject': l.noProject,
        'noDescription': l.noDescription,
        'start': l.start,
        'stop': l.stop,
        'continue': l.continueEntry,
        'recent': l.menuBarRecent,
        'openApp': l.menuBarOpenApp,
        'quit': l.menuBarQuit,
        'signIn': l.menuBarSignIn,
        'firstSync': l.firstSync,
        'noWorkspace': l.noWorkspace,
        'launchAtLogin': l.launchAtLogin,
        'quickEntry': l.quickEntry,
        'quickEntryHint': l.quickEntryHint,
      },
    };
    // L'état de sync et le référentiel notifient souvent sans rien changer pour le panneau.
    final encoded = jsonEncode(state);
    if (encoded == _lastSent) return;
    _lastSent = encoded;
    try {
      await _channel.invokeMethod('update', state);
    } on MissingPluginException {
      // Runner sans barre de menus (tests).
    }
  }

  // ------------------------------------------------------------------ panneau → base locale

  /// Les commandes renvoient null, ou le message à afficher dans le panneau.
  Future<Object?> _onCall(MethodCall call) async {
    final args = (call.arguments as Map?)?.cast<String, Object?>() ?? const {};
    final ws = _session.workspace;
    final userId = _session.userId;
    if (ws == null || userId == null) return null;
    switch (call.method) {
      case 'start':
        return _start(ws, userId, args['description'] as String? ?? '', args['projectId'] as String?);
      case 'stop':
        return _stop(ws, args['description'] as String?);
      case 'setDescription':
        final running = _running;
        final text = args['description'] as String? ?? '';
        if (running != null && text.trim() != running.description) {
          await entriesRepo.update(running, description: text);
        }
        return null;
      case 'setProject':
        return _setProject(userId, args['projectId'] as String?);
      case 'continue':
        return _continue(args['id'] as String?);
      case 'previewQuick':
        return _quick(ws, userId, args['text'] as String? ?? '', save: false);
      case 'quickEntry':
        return _quick(ws, userId, args['text'] as String? ?? '', save: true);
    }
    throw MissingPluginException(call.method);
  }

  Future<String?> _start(Workspace ws, String userId, String description, String? projectId) async {
    final blocked = timerRuleViolation(_l, ws, description: description, projectId: projectId) ??
        alreadyRunningViolation(_l, await entriesRepo.watchRunningAll(ws.id, userId).first,
            description: description, projectId: projectId, taskId: null);
    if (blocked != null) return blocked;
    await entriesRepo.start(
      workspaceId: ws.id,
      userId: userId,
      draft: EntryDraft(
        description: description,
        projectId: projectId,
        billable: _catalog.project(projectId)?.billableDefault ?? true,
        hourlyRateCents: _catalog.rateFor(projectId: projectId, userId: userId),
      ),
      maxRunning: _session.runningTimersLimit,
    );
    return null;
  }

  Future<String?> _stop(Workspace ws, String? description) async {
    final running = _running;
    if (running == null) return null;
    final text = description ?? running.description;
    final blocked = timerRuleViolation(_l, ws, description: text, projectId: running.projectId);
    if (blocked != null) return blocked;
    if (text.trim() != running.description) await entriesRepo.update(running, description: text);
    await entriesRepo.stop(running.id);
    return null;
  }

  /// Change le projet du chronomètre en cours (la tâche, propre à l'ancien projet, est retirée).
  Future<String?> _setProject(String userId, String? projectId) async {
    final running = _running;
    if (running == null || running.projectId == projectId) return null;
    await entriesRepo.update(
      running,
      projectId: projectId,
      clearProject: projectId == null,
      clearTask: true,
      billable: _catalog.project(projectId)?.billableDefault,
      hourlyRateCents: _catalog.rateFor(projectId: projectId, userId: userId),
    );
    return null;
  }

  /// Saisie express (plans/13-ux-moderne.md, lot 3) : l'aperçu de la ligne (`preview`, `ready`), ou son
  /// enregistrement (`ok`, `message`), rangée comme dans la page « Aujourd'hui ».
  Future<Map<String, Object?>> _quick(Workspace ws, String userId, String text, {required bool save}) async {
    final now = DateTime.now();
    final q = parseQuick(text, _catalog, now);
    if (q == null) return {'preview': null, 'ready': false, 'ok': false};
    final rows = await entriesRepo
        .watchEntries(workspaceId: ws.id, userId: userId, from: addDays(now, -35), to: addDays(now, 1), includeRunning: true)
        .first;
    final slot = placeQuick(q, now: now, entries: [for (final r in rows) r.entry]);
    if (!mounted) return const {};
    final ready = q.isComplete && slot != null;
    if (!save) return {'preview': quickSummary(context, q, slot, _catalog, userId, now).join(' · '), 'ready': ready};
    if (!ready) return {'ok': false, 'message': q.duration == null ? _l.quickDurationMissing : _l.quickProjectMissing};
    final message = quickAddedMessage(context, q, slot, _catalog, now);
    await saveQuick(q, slot, catalog: _catalog, workspaceId: ws.id, userId: userId);
    return {'ok': true, 'message': message};
  }

  /// Relance une entrée récente, comme le bouton « Continuer » de la liste des entrées.
  Future<String?> _continue(String? id) async {
    final row = _recent.where((r) => r.entry.id == id).firstOrNull;
    if (row == null) return null;
    final e = row.entry;
    final running = await entriesRepo.watchRunningAll(e.workspaceId, e.userId).first;
    final blocked = alreadyRunningViolation(_l, running, description: e.description, projectId: e.projectId, taskId: e.taskId);
    if (blocked != null) return blocked;
    await entriesRepo.start(
      workspaceId: e.workspaceId,
      userId: e.userId,
      draft: EntryDraft(
        description: e.description,
        projectId: e.projectId,
        taskId: e.taskId,
        billable: e.billable,
        hourlyRateCents: e.hourlyRateCents,
        tagIds: row.tagIds,
      ),
      maxRunning: _session.runningTimersLimit,
    );
    return null;
  }
}
