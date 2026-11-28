import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:projectsais/models/app_state.dart';
import 'package:projectsais/models/models.dart';
import 'package:projectsais/screens/accounts/accounts_screen.dart';
import 'package:projectsais/screens/accounts/admin_announcements_screen.dart';
import 'package:projectsais/screens/accounts/admin_notifications_screen.dart';
import 'package:projectsais/screens/accounts/create_department_screen.dart';
import 'package:projectsais/screens/accounts/payroll_screen.dart';
import 'package:projectsais/screens/accounts/programs_screen.dart';
import 'package:projectsais/screens/accounts/rehiring_screen.dart';
import 'package:projectsais/screens/accounts/student_documents_screen.dart';
import 'package:projectsais/screens/backups/backups_screen.dart';
import 'package:projectsais/screens/reports/reports_screen.dart';
import 'package:projectsais/screens/student_portal/sp_notifications_screen.dart';
import 'package:projectsais/screens/supervisor/dtr_accomplishment_report_screen.dart';
import 'package:projectsais/screens/supervisor/performance_evaluation_screen.dart';
import 'package:projectsais/screens/supervisor/sv_announcements_screen.dart';
import 'package:projectsais/services/in_memory_schedule_repository.dart';
import 'package:projectsais/services/schedule_service.dart';
import 'package:projectsais/theme/app_theme.dart';

/// On a phone the whole page scrolls, title and filters included: these
/// pages used to pin their header and filters and scroll only the list
/// under them, which left the list a strip at the bottom of the screen.
/// So the page's own scroller must start at the top of the page.
User _user(String role) =>
    User(id: 'u1', name: 'Test $role', email: 'u1@example.com', role: role);

void main() {
  final pages = <String, ({String role, Widget page})>{
    'Head Announcements': (
      role: 'Head',
      page: const AdminAnnouncementsScreen(),
    ),
    'Student Documents': (role: 'Head', page: const StudentDocumentsScreen()),
    'Rehiring': (role: 'Head', page: const RehiringScreen()),
    'Reports': (role: 'Supervisor', page: const ReportsScreen()),
    'Performance Evaluation': (
      role: 'Supervisor',
      page: const PerformanceEvaluationScreen(),
    ),
    'DTR/Accomplishment Report': (
      role: 'Supervisor',
      page: const DtrAccomplishmentReportScreen(),
    ),
    'Request Student Assistant': (
      role: 'Supervisor',
      page: const SvAnnouncementsScreen(),
    ),
    'Head Notifications': (
      role: 'Head',
      page: const AdminNotificationsScreen(),
    ),
    'Notifications': (
      role: 'Student Assistant',
      page: const SpNotificationsScreen(),
    ),
    'Departments': (role: 'Admin', page: const CreateDepartmentScreen()),
    'Programs': (role: 'Admin', page: const ProgramsScreen()),
    'Payroll': (role: 'Admin', page: const PayrollScreen()),
    'Backups': (role: 'Admin', page: const BackupsScreen()),
    'Accounts': (role: 'Admin', page: const AccountsScreen()),
  };

  for (final entry in pages.entries) {
    testWidgets('${entry.key}: the whole page scrolls on a phone', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final onError = FlutterError.onError;
      final errors = <String>[];
      FlutterError.onError = (details) {
        final message = details.exceptionAsString();
        // The test font is wider than the real one; overflows aren't
        // what this test is about.
        if (!message.contains('overflowed')) {
          errors.add(message.split('\n').first);
        }
      };
      final state = AppState()..currentUser = _user(entry.value.role);
      try {
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<AppState>.value(value: state),
              ChangeNotifierProvider(
                create: (_) => ScheduleService(InMemoryScheduleRepository()),
              ),
            ],
            child: MaterialApp(
              theme: AppTheme.theme,
              home: Scaffold(body: entry.value.page),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));
      } finally {
        FlutterError.onError = onError;
      }
      tester.takeException();
      expect(errors, isEmpty);

      // The first vertical scroller in the tree is the page's own, and it
      // starts at the top of the page: nothing is pinned above it.
      final scroller = find
          .byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          )
          .first;
      final box = tester.renderObject<RenderBox>(scroller);
      expect(box.localToGlobal(Offset.zero).dy, 0);
    });
  }
}
