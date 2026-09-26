import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:projectsais/models/app_state.dart';
import 'package:projectsais/models/models.dart';
import 'package:projectsais/screens/dashboard/dashboard_screen.dart';
import 'package:projectsais/theme/app_theme.dart';
import 'package:projectsais/widgets/dashboard_widgets.dart';

User _user(String role) => User(
  id: 'u_1',
  name: 'Juan dela Cruz',
  email: 'juan@marsu.edu.ph',
  role: role,
  department: 'College of Information and Computing Sciences',
  campus: 'Boac Campus',
);

void main() {
  Future<void> pumpDashboard(
    WidgetTester tester,
    String role,
    Size size, {
    List<User>? users,
    List<AttendanceRecord>? attendance,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>(
        create: (_) {
          final state = AppState()..currentUser = _user(role);
          if (users != null) state.users = users;
          if (attendance != null) state.attendance = attendance;
          return state;
        },
        child: MaterialApp(
          theme: AppTheme.theme,
          home: const Scaffold(body: DashboardScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  // Every breakpoint the dashboards switch on, plus the extremes.
  const widths = [320.0, 379.0, 380.0, 480.0, 640.0, 767.0, 768.0, 1024.0,
      1440.0, 1920.0];

  const roles = ['Head', 'Admin', 'Supervisor', 'Student Assistant'];

  for (final role in roles) {
    group('$role dashboard', () {
      for (final width in widths) {
        testWidgets('lays out without overflow at ${width.toInt()}px', (
          tester,
        ) async {
          await pumpDashboard(tester, role, Size(width, 1800));
          expect(tester.takeException(), isNull);
          // Four headline numbers, however they are arranged. The Student
          // Assistant has three: duty status lives in the Today card.
          expect(
            find.byType(DashboardStatTile),
            findsNWidgets(role == 'Student Assistant' ? 3 : 4),
          );
        });
      }

      testWidgets('leads with a heading and a stat row', (tester) async {
        await pumpDashboard(tester, role, const Size(1440, 1800));
        expect(find.byType(DashboardHeading), findsOneWidget);
        expect(find.byType(DashboardStatRow), findsOneWidget);
      });
    });
  }

  group('stat row', () {
    testWidgets('is one column on the narrowest phones, four when wide', (
      tester,
    ) async {
      double tileWidth(WidgetTester tester) => tester
          .widgetList<SizedBox>(
            find.descendant(
              of: find.byType(DashboardStatRow),
              matching: find.byType(SizedBox),
            ),
          )
          .first
          .width!;

      await pumpDashboard(tester, 'Head', const Size(320, 1800));
      final narrow = tileWidth(tester);

      await pumpDashboard(tester, 'Head', const Size(1440, 1800));
      final wide = tileWidth(tester);

      // One column fills the row; four columns take about a quarter each.
      expect(narrow, greaterThan(250));
      expect(wide, lessThan(narrow * 1.6));
    });
  });

  group('Student Assistant Today card', () {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug',
        'Sep', 'Oct', 'Nov', 'Dec'];
    String dateOf(DateTime d) => '${months[d.month - 1]} ${d.day}, ${d.year}';
    String clockOf(DateTime d) {
      final hour = d.hour % 12 == 0 ? 12 : d.hour % 12;
      final minute = d.minute.toString().padLeft(2, '0');
      return '$hour:$minute ${d.hour < 12 ? 'AM' : 'PM'}';
    }

    AttendanceRecord record(
      String id,
      DateTime day, {
      String timeIn = '8:00 AM',
      String? timeOut = '11:00 AM',
      double? hours = 3,
      bool isInvalid = false,
    }) => AttendanceRecord(
      id: id,
      studentName: 'Juan dela Cruz',
      studentId: 'u_1',
      date: dateOf(day),
      timeIn: timeIn,
      timeOut: timeOut,
      totalHours: hours,
      isInvalid: isInvalid,
    );

    Future<void> pumpStudent(
      WidgetTester tester,
      List<AttendanceRecord> attendance,
    ) => pumpDashboard(
      tester,
      'Student Assistant',
      const Size(1440, 1800),
      attendance: attendance,
    );

    testWidgets('shows an empty week against the cap', (tester) async {
      await pumpStudent(tester, const []);
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Not on duty'), findsOneWidget);
      expect(find.text('0 of 20 hours'), findsOneWidget);
      expect(find.text('20 hours left · resets Monday'), findsOneWidget);
    });

    testWidgets('counts this week only, and leaves out voided sessions', (
      tester,
    ) async {
      final today = DateTime.now();
      await pumpStudent(tester, [
        record('a', today, hours: 6.5),
        record('b', today.subtract(const Duration(days: 8)), hours: 4),
        record('c', today, hours: 2, isInvalid: true),
      ]);
      expect(find.text('6.5 of 20 hours'), findsOneWidget);
      expect(find.text('13.5 hours left · resets Monday'), findsOneWidget);
      expect(find.text('6.5 hours credited today'), findsOneWidget);
      expect(
        find.text('You missed a time-out today, so that session didn\'t count.'),
        findsOneWidget,
      );
    });

    testWidgets('shows who is on duty and since when', (tester) async {
      final now = DateTime.now();
      final timeIn = clockOf(now);
      await pumpStudent(tester, [
        record('open', now, timeIn: timeIn, timeOut: null, hours: null),
      ]);
      expect(find.textContaining('On duty'), findsOneWidget);
      expect(find.text('Timed in at $timeIn'), findsOneWidget);
      expect(
        find.text('Your current session is added when you time out.'),
        findsOneWidget,
      );
    });

    testWidgets('says when the weekly limit is reached', (tester) async {
      await pumpStudent(tester, [record('a', DateTime.now(), hours: 20)]);
      expect(find.text('Limit reached · resets Monday'), findsOneWidget);
      expect(
        find.text('You\'ve reached this week\'s 20-hour limit.'),
        findsOneWidget,
      );
    });

    testWidgets('lets three stat tiles share the row', (tester) async {
      double tileWidth() => tester
          .widgetList<SizedBox>(
            find.descendant(
              of: find.byType(DashboardStatRow),
              matching: find.byType(SizedBox),
            ),
          )
          .first
          .width!;

      await pumpDashboard(tester, 'Head', const Size(1440, 1800));
      final four = tileWidth();
      // Unmount first, or the provider keeps the Head's state.
      await tester.pumpWidget(const SizedBox());
      await pumpStudent(tester, const []);
      final three = tileWidth();
      expect(three, greaterThan(four * 1.25));
    });

    testWidgets('lets a lone last tile span the row on phones', (tester) async {
      await pumpDashboard(tester, 'Student Assistant', const Size(390, 1800));
      final row = tester.widget<Wrap>(
        find.descendant(
          of: find.byType(DashboardStatRow),
          matching: find.byType(Wrap),
        ),
      );
      final widths = [
        for (final tile in row.children) (tile as SizedBox).width,
      ];
      // Two columns: two half-width tiles, then one across the whole row.
      expect(widths[2], greaterThan(widths[0]! * 1.9));
    });
  });

  group('Supervisor dashboard', () {
    testWidgets('keeps quick actions on phones', (tester) async {
      // They used to be dropped below 768px, leaving phone users with no way
      // to reach them from the dashboard.
      await pumpDashboard(tester, 'Supervisor', const Size(390, 1800));
      expect(find.text('Quick Actions'), findsOneWidget);

      await pumpDashboard(tester, 'Supervisor', const Size(1440, 1800));
      expect(find.text('Quick Actions'), findsOneWidget);
    });
  });

  group('Admin role breakdown', () {
    testWidgets('shows each role with its count and share', (tester) async {
      await pumpDashboard(
        tester,
        'Admin',
        const Size(1440, 1800),
        users: [
          _user('Admin'),
          _user('Head'),
          _user('Supervisor'),
          _user('Supervisor'),
          _user('Student Assistant'),
        ],
      );

      expect(find.text('Role Breakdown'), findsOneWidget);
      // Scoped to the card: "Heads" and "Supervisors" are also stat labels.
      for (final role in ['Heads', 'Supervisors', 'Student Assistants']) {
        expect(
          find.descendant(
            of: find.byType(DashboardSectionCard),
            matching: find.text(role),
          ),
          findsOneWidget,
          reason: 'missing $role in the breakdown',
        );
      }
      // Counts are direct-labelled, so identity never rests on colour.
      // Shares are of the staffed roles (1 head + 2 supervisors + 1 SA),
      // not of the 5 accounts: the admin is not one of them.
      expect(find.text('50%'), findsOneWidget);
      expect(find.text('25%'), findsNWidgets(2));
      expect(
        find.text('4 of 5 accounts are staffed roles'),
        findsOneWidget,
      );
    });

    testWidgets('draws a stacked bar with a segment per role', (tester) async {
      // Asserting on text alone missed this twice: the bar was laid out at
      // zero size and drew nothing while every label still read correctly.
      await pumpDashboard(
        tester,
        'Admin',
        const Size(1440, 1800),
        users: [
          _user('Head'),
          _user('Supervisor'),
          _user('Supervisor'),
          _user('Student Assistant'),
        ],
      );

      final segments = find.descendant(
        of: find.byType(DashboardSectionCard),
        matching: find.byType(ColoredBox),
      );
      expect(segments, findsNWidgets(3));

      var widest = 0.0;
      for (var i = 0; i < 3; i++) {
        final size = tester.getSize(segments.at(i));
        expect(size.height, 10, reason: 'segment $i has no height');
        expect(size.width, greaterThan(0), reason: 'segment $i has no width');
        widest = size.width > widest ? size.width : widest;
      }
      // The two-supervisor slice is wider than the one-head slice.
      expect(tester.getSize(segments.at(1)).width, widest);
    });

    testWidgets('says so when there are no accounts', (tester) async {
      await pumpDashboard(
        tester,
        'Admin',
        const Size(1440, 1800),
        users: const [],
      );
      expect(find.text('No active accounts yet'), findsOneWidget);
    });
  });

  group('chart palette', () {
    test('is assigned by position and never cycled', () {
      // A fourth category must fold into "Other" rather than reuse slot 1.
      expect(ChartPalette.categorical.length, 3);
      expect(ChartPalette.categorical.toSet().length, 3);
    });
  });
}
