import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../data/powersync/connector.dart';
import '../../features/approvals/reminder_banner.dart';
import '../../features/assistant/assistant.dart';
import '../../features/commands/command_palette.dart';
import '../../features/commands/shortcuts_help.dart';
import '../../features/time_entries/entry_dialog.dart';
import '../../features/time_entries/quick_add_sheet.dart';
import '../../features/timer/timer_control.dart';
import '../../features/today/day_recap.dart';
import '../di.dart';
import '../guide.dart';
import '../l10n.dart';
import '../session.dart';
import '../shortcuts.dart';
import '../team_rights.dart';
import '../theme.dart';
import 'common.dart';
import 'sync_indicator.dart';

/// Une page de l'app.
class _Dest {
  const _Dest(this.path, this.icon, this.label, {this.tabLabel, this.managerOnly = false, this.visibleIf});
  final String path;
  final IconData icon;
  final String Function(AppLocalizations) label;
  /// Libellé dans les onglets de sa rubrique, s'il diffère.
  final String Function(AppLocalizations)? tabLabel;
  final bool managerOnly;
  /// Condition d'affichage liée à l'équipe (chef d'équipe, saisie pour autrui) ; prime sur [managerOnly].
  final bool Function(TeamRights)? visibleIf;

  bool visible(SessionController session, TeamRights rights) => visibleIf?.call(rights) ?? (!managerOnly || session.isManager);
}

const _today = _Dest('/today', Icons.wb_sunny_outlined, _todayLabel);
const _grid = _Dest('/timesheet', Icons.grid_on_outlined, _timesheetLabel);
const _calendar = _Dest('/calendar', Icons.calendar_month_outlined, _calendarLabel);
const _list = _Dest('/', Icons.timer_outlined, _timeTrackerLabel);
const _reports = _Dest('/reports', Icons.bar_chart_outlined, _reportsLabel);
const _invoices = _Dest('/invoices', Icons.receipt_long_outlined, _invoicesLabel, managerOnly: true);
const _people = _Dest('/team', Icons.groups_outlined, _teamLabel, tabLabel: _peopleLabel);
const _approvals = _Dest('/approvals', Icons.fact_check_outlined, _approvalsLabel, visibleIf: _seesTeam);
const _teamEntry = _Dest('/team-entry', Icons.group_add_outlined, _teamEntryLabel, visibleIf: _canEditOthers);
const _schedule = _Dest('/schedule', Icons.view_timeline_outlined, _scheduleLabel);
const _timeOff = _Dest('/time-off', Icons.beach_access_outlined, _timeOffLabel);
const _projects = _Dest('/projects', Icons.folder_outlined, _projectsLabel);
const _clients = _Dest('/clients', Icons.business_outlined, _clientsLabel);
const _tags = _Dest('/tags', Icons.sell_outlined, _tagsLabel);
const _settings = _Dest('/settings', Icons.settings_outlined, _settingsLabel);

String _todayLabel(AppLocalizations l) => l.today;
String _timesheetLabel(AppLocalizations l) => l.timesheet;
String _calendarLabel(AppLocalizations l) => l.calendar;
String _timeTrackerLabel(AppLocalizations l) => l.timeTracker;
String _reportsLabel(AppLocalizations l) => l.reports;
String _invoicesLabel(AppLocalizations l) => l.invoices;
String _teamLabel(AppLocalizations l) => l.team;
String _peopleLabel(AppLocalizations l) => l.navPeople;
String _approvalsLabel(AppLocalizations l) => l.approvals;
String _teamEntryLabel(AppLocalizations l) => l.teamEntry;
String _scheduleLabel(AppLocalizations l) => l.schedule;
String _timeOffLabel(AppLocalizations l) => l.timeOff;
String _projectsLabel(AppLocalizations l) => l.projects;
String _clientsLabel(AppLocalizations l) => l.clients;
String _tagsLabel(AppLocalizations l) => l.tags;
String _settingsLabel(AppLocalizations l) => l.settings;
String _weekLabel(AppLocalizations l) => l.navWeek;
String _projectsClientsLabel(AppLocalizations l) => l.navProjectsClients;

bool _canEditOthers(TeamRights r) => r.canEditOthers;
bool _seesTeam(TeamRights r) => r.seesTeam;

/// Une rubrique du menu (plans/14-coller-aux-maquettes.md, lot 1) : une ou plusieurs pages ; avec [tabs], elles
/// s'affichent en onglets en tête de page (la Semaine a ses propres vues).
class _Section {
  const _Section(this.icon, this.selectedIcon, this.label, this.pages, {this.tabs = false});
  final IconData icon;
  final IconData selectedIcon;
  final String Function(AppLocalizations) label;
  final List<_Dest> pages;
  final bool tabs;

  List<_Dest> visiblePages(SessionController session, TeamRights rights) => pages.where((p) => p.visible(session, rights)).toList();
  bool contains(String location) => pages.any((p) => p.path == location);
}

/// Le menu des maquettes : cinq rubriques de travail, puis la gestion.
const _mainSections = [
  _Section(Icons.wb_sunny_outlined, Icons.wb_sunny, _todayLabel, [_today]),
  _Section(Icons.calendar_view_week_outlined, Icons.calendar_view_week, _weekLabel, [_grid, _calendar, _list]),
  _Section(Icons.bar_chart_outlined, Icons.bar_chart, _reportsLabel, [_reports]),
  _Section(Icons.receipt_long_outlined, Icons.receipt_long, _invoicesLabel, [_invoices]),
  _Section(Icons.groups_outlined, Icons.groups, _teamLabel, [_people, _approvals, _teamEntry, _schedule, _timeOff], tabs: true),
];
const _manageSections = [
  _Section(Icons.folder_outlined, Icons.folder, _projectsClientsLabel, [_projects, _clients, _tags], tabs: true),
  _Section(Icons.settings_outlined, Icons.settings, _settingsLabel, [_settings]),
];

/// Pages accessibles, dans l'ordre du menu (palette ⌘K : « Aller à »).
List<({String path, IconData icon, String label})> navDestinations(BuildContext context) {
  final l = context.l10n;
  final session = context.read<SessionController>();
  final rights = TeamRights.read(context);
  return [
    for (final s in [..._mainSections, ..._manageSections])
      for (final d in s.visiblePages(session, rights)) (path: d.path, icon: d.icon, label: d.label(l)),
  ];
}

/// Coquille responsive : menu latéral sur grand écran, barre du bas avec « + » sur téléphone ; le chronomètre
/// (bouton Démarrer ou pastille) toujours visible en haut à droite.
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

  /// Raccourcis de toute l'app (plans/13-ux-moderne.md, lot 1) ; ceux des pages passent avant ([PageShortcuts]).
  bool _onKey(KeyEvent event) {
    final key = event.logicalKey;
    if (commandPressed && key == LogicalKeyboardKey.keyK) {
      showCommandPalette(context);
      return true;
    }
    if (commandPressed && key == LogicalKeyboardKey.keyZ && !isTyping()) return undoLast(context);
    if (commandPressed && key == LogicalKeyboardKey.keyJ) {
      AssistantApi.enabled().then((on) {
        if (on && mounted) showAssistant(context);
      });
      return true;
    }
    if (!plainKey(event) || event is KeyRepeatEvent) return false;
    if (key == LogicalKeyboardKey.keyN) {
      showEntryDialog(context);
      return true;
    }
    if (key == LogicalKeyboardKey.keyS) {
      toggleTimer();
      return true;
    }
    if (event.character == '?') {
      showShortcutsHelp(context);
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    if (session.waitingForFirstSync || session.workspace == null) return _build(context);
    return AppShortcuts(onKey: _onKey, child: _build(context));
  }

  Widget _build(BuildContext context) {
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

    final rights = TeamRights.of(context);
    final main = _mainSections.where((s) => s.visiblePages(session, rights).isNotEmpty).toList();
    final manage = _manageSections.where((s) => s.visiblePages(session, rights).isNotEmpty).toList();
    final current = [...main, ...manage].where((s) => s.contains(widget.location)).firstOrNull;
    final tabs = current != null && current.tabs ? current.visiblePages(session, rights) : const <_Dest>[];
    final tabStrip = tabs.length > 1 ? _SectionTabs(pages: tabs, location: widget.location) : null;
    final wide = MediaQuery.sizeOf(context).width >= 900;

    final assistant = FutureBuilder<bool>(
      // L'assistant n'apparaît que si l'installation a une clé d'API (plan 13, lot 12).
      future: AssistantApi.enabled(),
      builder: (context, snap) => snap.data == true
          ? IconButton(
              tooltip: l.assistantTooltip('${commandKeyLabel}J'),
              icon: const Icon(Icons.auto_awesome_outlined),
              onPressed: () => showAssistant(context),
            )
          : const SizedBox.shrink(),
    );

    if (wide) {
      return Scaffold(
        body: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _Sidebar(main: main, manage: manage, current: current, session: session, rights: rights),
          Expanded(
            child: Column(children: [
              SizedBox(
                height: 64,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
                  child: Row(children: [
                    if (tabStrip != null) Expanded(child: Align(alignment: Alignment.centerLeft, child: tabStrip)) else const Spacer(),
                    assistant,
                    const SizedBox(width: 8),
                    OutlinedButton.icon(onPressed: () => showEntryDialog(context), icon: const Icon(Icons.add, size: 20), label: Text(l.addTime)),
                    const SizedBox(width: 8),
                    const TimerControl(),
                  ]),
                ),
              ),
              const ReminderBanner(),
              const DayRecapBanner(),
              Expanded(child: widget.child),
            ]),
          ),
        ]),
      );
    }

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: _WorkspaceSwitcher(session: session, compact: true),
        actions: [
          IconButton(tooltip: l.commandPaletteTooltip('${commandKeyLabel}K'), icon: const Icon(Icons.search), onPressed: () => showCommandPalette(context)),
          const SyncIndicator(),
          const Padding(padding: EdgeInsets.only(right: 12, left: 4), child: TimerControl(compact: true)),
        ],
      ),
      body: Column(children: [
        if (tabStrip != null)
          SizedBox(
            height: 52,
            child: SingleChildScrollView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(16, 4, 16, 8), child: tabStrip),
          ),
        const ReminderBanner(),
        const DayRecapBanner(),
        Expanded(child: widget.child),
      ]),
      bottomNavigationBar: _PhoneBar(main: main, manage: manage, current: current, session: session, rights: rights),
    );
  }
}

/// Changer d'espace : le nom de l'espace et une flèche.
class _WorkspaceSwitcher extends StatelessWidget {
  const _WorkspaceSwitcher({required this.session, this.compact = false});
  final SessionController session;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = Text(session.workspace!.name,
        overflow: TextOverflow.ellipsis, style: compact ? theme.textTheme.titleMedium : theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500));
    return PopupMenuButton<String>(
      tooltip: context.l10n.switchWorkspace,
      onSelected: session.selectWorkspace,
      itemBuilder: (_) => [
        for (final m in session.memberships)
          CheckedPopupMenuItem(value: m.workspace.id, checked: m.workspace.id == session.workspaceId, child: Text(m.workspace.name)),
      ],
      child: compact
          ? Row(mainAxisSize: MainAxisSize.min, children: [Flexible(child: name), const Icon(Icons.expand_more, size: 20)])
          : Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                border: Border.all(color: theme.colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(Radii.control),
              ),
              child: Row(children: [Expanded(child: name), Icon(Icons.unfold_more, size: 18, color: theme.colorScheme.outline)]),
            ),
    );
  }
}

/// Menu latéral des maquettes : logo, espace, « Rechercher ou agir », rubriques, gestion, synchronisation.
class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.main, required this.manage, required this.current, required this.session, required this.rights});
  final List<_Section> main;
  final List<_Section> manage;
  final _Section? current;
  final SessionController session;
  final TeamRights rights;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    Widget item(_Section s) => _NavItem(
          icon: s == current ? s.selectedIcon : s.icon,
          label: s.label(l),
          selected: s == current,
          onTap: () => context.go(s.visiblePages(session, rights).first.path),
        );
    return Container(
      width: 248,
      decoration: BoxDecoration(color: colors.sidebar, border: Border(right: BorderSide(color: theme.colorScheme.outlineVariant))),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 20, 14, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(color: theme.colorScheme.primary, borderRadius: BorderRadius.circular(8)),
                  child: Icon(Icons.schedule, size: 17, color: theme.colorScheme.onPrimary),
                ),
                const SizedBox(width: 10),
                Text('Clockifai', style: theme.textTheme.titleMedium?.copyWith(fontSize: 17, letterSpacing: -0.2)),
              ]),
            ),
            const SizedBox(height: 18),
            _WorkspaceSwitcher(session: session),
            const SizedBox(height: 8),
            _SearchButton(onTap: () => showCommandPalette(context)),
            const SizedBox(height: 18),
            Expanded(
              child: ListView(padding: EdgeInsets.zero, children: [
                for (final s in main) item(s),
                if (manage.isNotEmpty) ...[
                  const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Divider()),
                  for (final s in manage) item(s),
                ],
              ]),
            ),
            _NavItem(icon: Icons.help_outline, label: l.userGuide, trailing: Icons.open_in_new, onTap: () => openGuide(context)),
            const SizedBox(height: 4),
            const SyncIndicator(line: true),
          ]),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.icon, required this.label, required this.onTap, this.selected = false, this.trailing});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;
  final IconData? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = selected ? theme.colorScheme.onSurface : theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected ? theme.colorScheme.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(Radii.control),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.control),
          onTap: onTap,
          child: Semantics(
            selected: selected,
            child: SizedBox(
              height: 40,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(children: [
                  Icon(icon, size: 20, color: fg),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(label,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(color: fg, fontWeight: selected ? FontWeight.w600 : FontWeight.w400)),
                  ),
                  if (trailing != null) Icon(trailing, size: 14, color: theme.colorScheme.outline),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// « Rechercher ou agir ⌘K » : ouvre la palette.
class _SearchButton extends StatelessWidget {
  const _SearchButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.control), side: BorderSide(color: theme.colorScheme.outlineVariant)),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.control),
        onTap: onTap,
        child: SizedBox(
          height: 40,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(children: [
              Icon(Icons.search, size: 18, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 10),
              Expanded(child: Text(context.l10n.searchOrAct, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant))),
              KeyCap('${commandKeyLabel}K'),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Touche de raccourci (« ⌘K »), en Geist Mono.
class KeyCap extends StatelessWidget {
  const KeyCap(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label, style: theme.textTheme.labelSmall?.copyWith(fontFamily: monoFont, color: theme.colorScheme.onSurfaceVariant)),
    );
  }
}

/// Onglets d'une rubrique (Équipe, Projets et clients).
class _SectionTabs extends StatelessWidget {
  const _SectionTabs({required this.pages, required this.location});
  final List<_Dest> pages;
  final String location;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(11)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (final p in pages)
          Padding(
            padding: const EdgeInsets.only(right: 2),
            child: Material(
              color: p.path == location ? theme.colorScheme.surface : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
              elevation: p.path == location ? 0.5 : 0,
              child: InkWell(
                borderRadius: BorderRadius.circular(9),
                onTap: () => context.go(p.path),
                child: Semantics(
                  selected: p.path == location,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    child: Text((p.tabLabel ?? p.label)(l),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: p.path == location ? FontWeight.w600 : FontWeight.w400,
                          color: p.path == location ? theme.colorScheme.onSurface : theme.colorScheme.onSurfaceVariant,
                        )),
                  ),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

/// Barre du bas des maquettes : Aujourd'hui, Semaine, « + », Équipe, Plus.
class _PhoneBar extends StatelessWidget {
  const _PhoneBar({required this.main, required this.manage, required this.current, required this.session, required this.rights});
  final List<_Section> main;
  final List<_Section> manage;
  final _Section? current;
  final SessionController session;
  final TeamRights rights;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    // Aujourd'hui, Semaine et Équipe dans la barre ; le reste dans « Plus ».
    final team = main.where((s) => s.pages.first == _people).firstOrNull;
    final bar = [main.first, if (main.length > 1) main[1], ?team];
    final rest = [...main, ...manage].where((s) => !bar.contains(s)).toList();
    final selected = current == null ? -1 : bar.indexOf(current!);
    final items = <Widget>[
      for (final s in bar.take(2)) NavigationDestination(icon: Icon(s.icon), selectedIcon: Icon(s.selectedIcon), label: s.label(l)),
      NavigationDestination(
        icon: Container(
          width: 52,
          height: 40,
          decoration: BoxDecoration(color: theme.colorScheme.primary, borderRadius: BorderRadius.circular(14)),
          child: Icon(Icons.add, color: theme.colorScheme.onPrimary, size: 26),
        ),
        label: l.add,
      ),
      for (final s in bar.skip(2)) NavigationDestination(icon: Icon(s.icon), selectedIcon: Icon(s.selectedIcon), label: s.label(l)),
      NavigationDestination(icon: const Icon(Icons.menu), label: l.more),
    ];
    final moreIndex = items.length - 1;
    return NavigationBar(
      selectedIndex: selected < 0 ? moreIndex : (selected < 2 ? selected : selected + 1),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      destinations: items,
      onDestinationSelected: (i) {
        if (i == 2) {
          showQuickAddSheet(context);
          return;
        }
        if (i == moreIndex) return _showMore(context, rest);
        context.go(bar[i < 2 ? i : i - 1].visiblePages(session, rights).first.path);
      },
    );
  }

  void _showMore(BuildContext context, List<_Section> rest) {
    final l = context.l10n;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(12, 0, 12, 12), children: [
          for (final s in rest)
            ListTile(
              leading: Icon(s.icon),
              title: Text(s.label(l)),
              selected: s == current,
              onTap: () {
                Navigator.pop(ctx);
                context.go(s.visiblePages(session, rights).first.path);
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
}
