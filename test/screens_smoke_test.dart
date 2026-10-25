import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:projectsais/models/app_state.dart';
import 'package:projectsais/models/models.dart';
import 'package:projectsais/screens/accounts/document_folders_screen.dart';
import 'package:projectsais/screens/accounts/offices_screen.dart';
import 'package:projectsais/screens/accounts/rehiring_screen.dart';
import 'package:projectsais/screens/accounts/student_documents_screen.dart';
import 'package:projectsais/screens/settings/academic_year_settings_screen.dart';
import 'package:projectsais/screens/students/students_screen.dart';
import 'package:projectsais/theme/app_theme.dart';

/// Screens with no widget test of their own, pumped at a phone, a tablet and
/// a desktop width with some data in them. Each must lay out and build
/// without throwing.
///
/// The test font draws every glyph as a full square, so rows overflow here
/// though they fit in the app: overflows are counted and printed, not
/// failures, and can't prove a layout fix (give a fix its own targeted test).
/// Any other exception fails the test.
final _admin = User(
  id: 'admin1',
  name: 'Ana Admin',
  email: 'admin@example.com',
  role: 'Admin',
);
final _head = User(
  id: 'head1',
  name: 'Hana Head',
  email: 'head@example.com',
  role: 'Head',
);
final _supervisor = User(
  id: 'sup1',
  name: 'Sid Supervisor',
  email: 'sup@example.com',
  role: 'Supervisor',
);
final _assistant = User(
  id: 'sa1',
  name: 'Sara Assistant',
  email: 'sa@example.com',
  role: 'Student Assistant',
  department: 'College of Information and Computing Sciences',
);

AppState _seeded(User user) {
  final state = AppState()
    ..currentUser = user
    ..users = [_admin, _head, _supervisor, _assistant]
    ..students = [
      Student(
        id: 'sa1',
        userId: 'sa1',
        name: 'Sara Assistant',
        email: 'sa@example.com',
        department: 'College of Information and Computing Sciences',
      ),
    ]
    ..offices = [
      Office(
        id: 'o1',
        name: 'CICS Office',
        code: 'CICS',
        headIds: const ['sup1'],
        headNames: const ['Sid Supervisor'],
        assistantIds: const ['sa1'],
        assistantNames: const ['Sara Assistant'],
      ),
    ];
  return state;
}

void main() {
  final screens = <String, ({User user, Widget screen})>{
    'Students': (user: _head, screen: const StudentsScreen()),
    'Offices': (user: _head, screen: const OfficesScreen()),
    'Document Folders': (user: _head, screen: const DocumentFoldersScreen()),
    'Student Documents': (user: _head, screen: const StudentDocumentsScreen()),
    'Rehiring': (user: _head, screen: const RehiringScreen()),
    'Academic Year Settings': (
      user: _admin,
      screen: const AcademicYearSettingsScreen(),
    ),
  };

  for (final entry in screens.entries) {
    for (final width in const [360.0, 800.0, 1400.0]) {
      testWidgets('${entry.key} builds at ${width.toInt()} px wide', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        var overflows = 0;
        final others = <String>[];
        final onError = FlutterError.onError;
        FlutterError.onError = (details) {
          final message = details.exceptionAsString();
          if (message.contains('overflowed')) {
            overflows++;
          } else {
            others.add(message.split('\n').first);
          }
        };
        final state = _seeded(entry.value.user);
        try {
          await tester.pumpWidget(
            ChangeNotifierProvider<AppState>.value(
              value: state,
              child: MaterialApp(
                theme: AppTheme.theme,
                home: Scaffold(body: entry.value.screen),
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 300));
        } finally {
          FlutterError.onError = onError;
        }
        final thrown = tester.takeException();
        if (thrown != null && !thrown.toString().contains('overflowed')) {
          others.add(thrown.toString().split('\n').first);
        }

        if (overflows > 0) {
          debugPrint(
            '${entry.key} at ${width.toInt()} px: $overflows overflow(s) '
            'under the test font',
          );
        }
        expect(others, isEmpty, reason: '${entry.key} threw while building');
      });
    }
  }
}
