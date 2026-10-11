import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'core/session.dart';
import 'core/widgets/app_shell.dart';
import 'features/approvals/approvals_page.dart';
import 'features/auth/login_page.dart';
import 'features/calendar/calendar_page.dart';
import 'features/clients/clients_page.dart';
import 'features/invoices/invoices_page.dart';
import 'features/kiosk/kiosk_page.dart';
import 'features/projects/projects_page.dart';
import 'features/reports/reports_page.dart';
import 'features/schedule/schedule_page.dart';
import 'features/settings/settings_page.dart';
import 'features/tags/tags_page.dart';
import 'features/team/team_page.dart';
import 'features/time_off/time_off_page.dart';
import 'features/time_entries/time_entries_page.dart';
import 'features/timesheet/timesheet_page.dart';

GoRouter buildRouter(SessionController session) {
  Page<void> page(Widget child) => NoTransitionPage(child: child);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: session,
    redirect: (context, state) {
      final atLogin = state.matchedLocation == '/login';
      // Le mode kiosque fonctionne sans compte utilisateur (jeton d'appareil).
      if (state.matchedLocation == '/kiosk') return null;
      if (!session.isSignedIn) return atLogin ? null : '/login';
      if (atLogin || state.matchedLocation == '/auth/callback') return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginPage()),
      GoRoute(path: '/kiosk', builder: (_, _) => const KioskPage()),
      // Retour des liens magiques / confirmations (web) : supabase_flutter lit le code dans l'URL.
      GoRoute(path: '/auth/callback', builder: (_, _) => const Scaffold(body: Center(child: CircularProgressIndicator()))),
      ShellRoute(
        builder: (context, state, child) => AppShell(location: state.uri.path, child: child),
        routes: [
          GoRoute(path: '/', pageBuilder: (_, _) => page(const TimeEntriesPage())),
          GoRoute(path: '/timesheet', pageBuilder: (_, _) => page(const TimesheetPage())),
          GoRoute(path: '/calendar', pageBuilder: (_, _) => page(const CalendarPage())),
          GoRoute(path: '/reports', pageBuilder: (_, _) => page(const ReportsPage())),
          GoRoute(path: '/schedule', pageBuilder: (_, _) => page(const SchedulePage())),
          GoRoute(path: '/time-off', pageBuilder: (_, _) => page(const TimeOffPage())),
          GoRoute(path: '/approvals', pageBuilder: (_, _) => page(const ApprovalsPage())),
          GoRoute(path: '/invoices', pageBuilder: (_, _) => page(const InvoicesPage())),
          GoRoute(path: '/projects', pageBuilder: (_, _) => page(const ProjectsPage())),
          GoRoute(path: '/clients', pageBuilder: (_, _) => page(const ClientsPage())),
          GoRoute(path: '/tags', pageBuilder: (_, _) => page(const TagsPage())),
          GoRoute(path: '/team', pageBuilder: (_, _) => page(const TeamPage())),
          GoRoute(path: '/settings', pageBuilder: (_, _) => page(const SettingsPage())),
        ],
      ),
    ],
  );
}
