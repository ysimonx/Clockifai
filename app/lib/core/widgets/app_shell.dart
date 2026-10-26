import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../data/powersync/connector.dart';
import '../../features/timer/timer_bar.dart';
import '../di.dart';
import '../guide.dart';
import '../l10n.dart';
import '../session.dart';
import '../team_rights.dart';
import 'common.dart';
import 'sync_indicator.dart';

class _Dest {
  const _Dest(this.path, this.icon, this.selectedIcon, this.label, {this.managerOnly = false, this.visibleIf, this.section});
  final String path;
  final IconData icon;
  final IconData selectedIcon;
  final String Function(AppLocalizations) label;
  final bool managerOnly;
  /// Condition d'affichage liée à l'équipe (chef d'équipe, saisie pour autrui) ; prime sur [managerOnly].
  final bool Function(TeamRights)? visibleIf;
  /// Titre de section affiché avant cette entrée dans le menu latéral.
  final String Function(AppLocalizations)? section;
}

final _allDestinations = <_Dest>[
  // Journal automatique (plans/13-ux-moderne.md, lot 11) : la journée proposée, à valider.
  _Dest('/today', Icons.wb_sunny_outlined, Icons.wb_sunny, (l) => l.today),
  _Dest('/', Icons.timer_outlined, Icons.timer, (l) => l.timeTracker),
  _Dest('/timesheet', Icons.grid_on_outlined, Icons.grid_on, (l) => l.timesheet),
  _Dest('/calendar', Icons.calendar_month_outlined, Icons.calendar_month, (l) => l.calendar),
  _Dest('/reports', Icons.bar_chart_outlined, Icons.bar_chart, (l) => l.reports),
  _Dest('/schedule', Icons.view_timeline_outlined, Icons.view_timeline, (l) => l.schedule, section: (l) => l.sectionTeam),
  _Dest('/team-entry', Icons.group_add_outlined, Icons.group_add, (l) => l.teamEntry, visibleIf: _canEditOthers),
  _Dest('/time-off', Icons.beach_access_outlined, Icons.beach_access, (l) => l.timeOff),
  _Dest('/approvals', Icons.fact_check_outlined, Icons.fact_check, (l) => l.approvals, visibleIf: _seesTeam),
  _Dest('/invoices', Icons.receipt_long_outlined, Icons.receipt_long, (l) => l.invoices, managerOnly: true),
  _Dest('/team', Icons.groups_outlined, Icons.groups, (l) => l.team),
  _Dest('/projects', Icons.folder_outlined, Icons.folder, (l) => l.projects, section: (l) => l.sectionManage),
  _Dest('/clients', Icons.business_outlined, Icons.business, (l) => l.clients),
  _Dest('/tags', Icons.sell_outlined, Icons.sell, (l) => l.tags),
  _Dest('/settings', Icons.settings_outlined, Icons.settings, (l) => l.settings),
];

bool _canEditOthers(TeamRights r) => r.canEditOthers;
bool _seesTeam(TeamRights r) => r.seesTeam;

/// Nombre de destinations affichées dans la barre du bas sur mobile (le reste dans « Plus »).
const _mobileMain = 4;

/// Coquille responsive : rail latéral sur grand écran, barre du bas sur mobile,
/// barre de chronomètre toujours visible, indicateur de synchronisation.
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.location, required this.child});
  final String location;
  final Widget child;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  StreamSubscription<UploadRejection>? _rejections;

  @override
  void initState() {
    super.initState();
    _rejections = syncService.rejections.listen((r) {
      if (!mounted) return;
      final l = context.l10n;
      final msg = r.code == '42501' ? l.changeRejectedPermission : l.changeRejected(r.message);
      showSnack(context, msg);
    });
  }

  @override
  void dispose() {
    _rejections?.cancel();
    super.dispose();
  }

  int _indexIn(List<_Dest> dests) {
    final i = dests.indexWhere((d) => d.path != '/' && widget.location.startsWith(d.path));
    if (i >= 0) return i;
    final root = dests.indexWhere((d) => d.path == '/');
    return root < 0 ? 0 : root;
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final session = context.watch<SessionController>();
    if (session.waitingForFirstSync) {
      return Scaffold(
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(l.firstSync),
            const SizedBox(height: 8),
            TextButton(onPressed: session.signOut, child: Text(l.signOut)),
          ]),
        ),
      );
    }
    if (session.workspace == null) {
      return Scaffold(body: EmptyState(icon: Icons.workspaces_outline, title: l.noWorkspace, message: l.noWorkspaceMessage));
    }

    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 900;
    final content = Column(children: [
      const TimerBar(),
      const Divider(height: 1),
      Expanded(child: widget.child),
    ]);

    final workspaceSwitcher = PopupMenuButton<String>(
      tooltip: l.switchWorkspace,
      onSelected: session.selectWorkspace,
      itemBuilder: (_) => [
        for (final m in session.memberships)
          CheckedPopupMenuItem(value: m.workspace.id, checked: m.workspace.id == session.workspaceId, child: Text(m.workspace.name)),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Flexible(child: Text(session.workspace!.name, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium)),
          const Icon(Icons.arrow_drop_down),
        ]),
      ),
    );

    final rights = TeamRights.of(context);
    final destinations = _allDestinations
        .where((d) => d.visibleIf?.call(rights) ?? (!d.managerOnly || session.isManager))
        .toList();
    if (wide) {
      final index = _indexIn(destinations);
      return Scaffold(
        body: Row(children: [
          SizedBox(
            width: 232,
            child: NavigationDrawer(
              // Recréé à chaque changement de page : la sélection ne dépend pas de son animation, restée figée
              // sur l'ancienne entrée après une navigation lancée depuis le contenu (lien vers la fiche d'un agent).
              key: ValueKey(index),
              selectedIndex: index,
              onDestinationSelected: (i) => context.go(destinations[i].path),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 16, 12),
                  child: Row(children: [
                    Icon(Icons.timer, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 8),
                    Text('Clockifai', style: Theme.of(context).textTheme.titleLarge),
                  ]),
                ),
                for (final d in destinations) ...[
                  if (d.section != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(28, 16, 16, 6),
                      child: Text(d.section!(l).toUpperCase(), style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.outline)),
                    ),
                  NavigationDrawerDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selectedIcon), label: Text(d.label(l))),
                ],
                // Hors destinations (n'entre pas dans selectedIndex) : ouvre le guide dans le navigateur.
                const Padding(padding: EdgeInsets.fromLTRB(28, 8, 28, 8), child: Divider(height: 1)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: ListTile(
                    shape: const StadiumBorder(),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    leading: const Icon(Icons.help_outline),
                    title: Text(l.userGuide),
                    trailing: const Icon(Icons.open_in_new, size: 16),
                    onTap: () => openGuide(context),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Column(children: [
              Material(
                child: SizedBox(
                  height: 52,
                  child: Row(children: [
                    const SizedBox(width: 8),
                    Flexible(child: workspaceSwitcher),
                    const Spacer(),
                    const SyncIndicator(),
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Tooltip(
                        message: session.displayName,
                        child: CircleAvatar(radius: 16, child: Text(session.displayName.isEmpty ? '?' : session.displayName[0].toUpperCase())),
                      ),
                    ),
                  ]),
                ),
              ),
              const Divider(height: 1),
              Expanded(child: content),
            ]),
          ),
        ]),
      );
    }

    final idx = _indexIn(destinations);
    return Scaffold(
      appBar: AppBar(title: workspaceSwitcher, titleSpacing: 8, actions: const [SyncIndicator()]),
      body: content,
      bottomNavigationBar: NavigationBar(
        selectedIndex: idx < _mobileMain ? idx : _mobileMain,
        destinations: [
          for (final d in destinations.take(_mobileMain))
            NavigationDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selectedIcon), label: d.label(l)),
          NavigationDestination(icon: const Icon(Icons.menu), label: l.more),
        ],
        onDestinationSelected: (i) {
          if (i < _mobileMain) {
            context.go(destinations[i].path);
          } else {
            showModalBottomSheet<void>(
              context: context,
              showDragHandle: true,
              isScrollControlled: true,
              builder: (ctx) => SafeArea(
                child: ListView(shrinkWrap: true, children: [
                  for (final d in destinations.skip(_mobileMain))
                    ListTile(
                      leading: Icon(d.icon),
                      title: Text(d.label(l)),
                      selected: widget.location.startsWith(d.path),
                      onTap: () {
                        Navigator.pop(ctx);
                        context.go(d.path);
                      },
                    ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.help_outline),
                    title: Text(l.userGuide),
                    trailing: const Icon(Icons.open_in_new, size: 18),
                    onTap: () {
                      Navigator.pop(ctx);
                      openGuide(context);
                    },
                  ),
                ]),
              ),
            );
          }
        },
      ),
    );
  }
}
