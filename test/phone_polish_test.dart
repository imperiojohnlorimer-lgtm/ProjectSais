import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:projectsais/models/app_state.dart';
import 'package:projectsais/models/models.dart';
import 'package:projectsais/screens/accounts/rehiring_screen.dart';
import 'package:projectsais/screens/accounts/student_documents_screen.dart';
import 'package:projectsais/services/firestore_service.dart';
import 'package:projectsais/theme/app_theme.dart';
import 'package:projectsais/widgets/announcement_widgets.dart';
import 'package:projectsais/widgets/shared_widgets.dart';

/// Phone polish: one line of figures, filters behind a button, back to top,
/// short skill lists, and @mentions that notify.

class _Store extends FirestoreService {
  final notifications = <Map<String, dynamic>>[];

  @override
  Future<DocumentReference> addAnnouncement({
    required String title,
    required String body,
    Map<String, dynamic>? extra,
    String? id,
  }) async => _FakeDocRef(id ?? 'ann1');

  @override
  Future<void> addNotification(Map<String, dynamic> payload) async =>
      notifications.add(payload);
}

// ignore: subtype_of_sealed_class
class _FakeDocRef implements DocumentReference<Map<String, dynamic>> {
  _FakeDocRef(this.id);

  @override
  final String id;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

User _u(String id, String name, String role, {String status = 'Active'}) =>
    User(
      id: id,
      name: name,
      email: '$id@example.com',
      role: role,
      status: status,
    );

Future<void> _pump(WidgetTester tester, Widget child, {double width = 390}) {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  return tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.theme,
      home: Scaffold(body: child),
    ),
  );
}

const _stats = [
  HeroStatData(label: 'Recommended', value: '4', icon: Icons.thumb_up),
  HeroStatData(label: 'Not recommended', value: '0', icon: Icons.thumb_down),
];

/// A page whose filter lives in its state, like Rehiring's.
class _FilterPage extends StatefulWidget {
  const _FilterPage();

  @override
  State<_FilterPage> createState() => _FilterPageState();
}

class _FilterPageState extends State<_FilterPage> {
  String _show = 'All';

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: HeroBanner(
      isMobile: true,
      icon: Icons.autorenew,
      title: 'Rehiring',
      subtitle: 'Decide who continues',
      searchHint: 'Search',
      onSearch: (_) {},
      stats: _stats,
      filters: [TextButton(onPressed: () {}, child: const Text('Export'))],
      activeFilterCount: _show == 'All' ? 0 : 1,
      sheetFilters: [
        DropdownButton<String>(
          value: _show,
          items: [
            for (final v in ['All', 'Undecided'])
              DropdownMenuItem(value: v, child: Text('Show $v')),
          ],
          onChanged: (v) => setState(() => _show = v!),
        ),
      ],
    ),
  );
}

void main() {
  group('HeroBanner on a phone', () {
    testWidgets('figures are one line of text; chips on wide screens', (
      tester,
    ) async {
      final banner = HeroBanner(
        isMobile: true,
        icon: Icons.autorenew,
        title: 'Rehiring',
        subtitle: 'Decide who continues',
        stats: _stats,
      );
      await _pump(tester, banner);
      expect(find.byType(CompactFigures), findsOneWidget);
      expect(
        find.textContaining('4 Recommended', findRichText: true),
        findsOneWidget,
      );

      await _pump(tester, banner, width: 1200);
      expect(find.byType(CompactFigures), findsNothing);
      expect(find.text('Recommended'), findsOneWidget);
    });

    testWidgets('sheet filters go behind "Filters (N)" and stay live', (
      tester,
    ) async {
      await _pump(tester, const _FilterPage());
      expect(find.text('Export'), findsOneWidget);
      expect(find.text('Show All'), findsNothing);
      expect(find.text('Filters'), findsOneWidget);

      await tester.tap(find.text('Filters'));
      await tester.pumpAndSettle();
      expect(find.text('Show All'), findsOneWidget);

      // Changing the filter inside the sheet shows the new value there and
      // counts it on the button.
      await tester.tap(find.text('Show All'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show Undecided').last);
      await tester.pumpAndSettle();
      expect(find.text('Show Undecided'), findsOneWidget);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('Filters (1)'), findsOneWidget);
    });

    testWidgets('the sheet closes when the screen widens', (tester) async {
      await _pump(tester, const _FilterPage());
      await tester.tap(find.text('Filters'));
      await tester.pumpAndSettle();
      expect(find.text('Done'), findsOneWidget);
      tester.view.physicalSize = const Size(1200, 800);
      await tester.pumpAndSettle();
      expect(find.text('Done'), findsNothing);
      expect(find.text('Show All'), findsOneWidget);
    });

    testWidgets('wide screens show the sheet filters inline', (tester) async {
      await _pump(tester, const _FilterPage(), width: 1200);
      expect(find.text('Show All'), findsOneWidget);
      expect(find.byType(FilterSheetButton), findsNothing);
    });
  });

  testWidgets('Back to top shows once scrolled down and scrolls up', (
    tester,
  ) async {
    await _pump(
      tester,
      BackToTopHost(
        child: ListView(
          children: [
            for (var i = 0; i < 100; i++)
              SizedBox(height: 60, child: Text('Row $i')),
          ],
        ),
      ),
    );
    final button = find.byTooltip('Back to top');
    double opacity() => tester
        .widget<AnimatedOpacity>(
          find.ancestor(of: button, matching: find.byType(AnimatedOpacity)),
        )
        .opacity;
    expect(opacity(), 0);

    await tester.drag(find.byType(ListView), const Offset(0, -1500));
    await tester.pumpAndSettle();
    expect(opacity(), 1);

    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('Row 0'), findsOneWidget);
    expect(opacity(), 0);
  });

  group('SkillsNeeded', () {
    const skills = ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H'];

    testWidgets('a card shows 3 and "+5 more"; a tap shows all', (
      tester,
    ) async {
      await _pump(tester, const SkillsNeeded(skills));
      expect(find.text('C'), findsOneWidget);
      expect(find.text('D'), findsNothing);
      await tester.tap(find.text('+5 more'));
      await tester.pump();
      expect(find.text('H'), findsOneWidget);
      await tester.tap(find.text('Show less'));
      await tester.pump();
      expect(find.text('H'), findsNothing);
    });

    testWidgets('four skills show all four; no limit shows all', (
      tester,
    ) async {
      await _pump(tester, const SkillsNeeded(['A', 'B', 'C', 'D']));
      expect(find.text('D'), findsOneWidget);
      expect(find.textContaining('more'), findsNothing);
      await _pump(tester, const SkillsNeeded(skills, limit: null));
      expect(find.text('H'), findsOneWidget);
    });
  });

  group('@mentions', () {
    final head = _u('head', 'Helen Head', 'Head');
    final ana = _u('ana', 'Ana Cruz', 'Student');
    final anaMarie = _u('anam', 'Ana Cruz Reyes', 'Student Assistant');
    final sid = _u('sid', 'Sid Santos', 'Supervisor');
    final gone = _u('gone', 'Gina Gone', 'Student', status: 'Archived');
    final admin = _u('adm', 'Al Admin', 'Admin');
    final other = _u('oth', 'Olga Other', 'Student');

    AppState state([FirestoreService? store]) =>
        AppState(firestoreService: store)
          ..currentUser = head
          ..users = [head, ana, anaMarie, sid, gone, admin, other];

    test('finds full names, case ignored, longest first', () {
      final s = state();
      List<String> ids(String text) =>
          s.mentionedUsers(text, excludeId: 'head').map((u) => u.id).toList()
            ..sort();
      expect(ids('Hi @ana cruz, see @Sid Santos.'), ['ana', 'sid']);
      expect(ids('Thanks @Ana Cruz Reyes!'), ['anam']);
      expect(ids('@Ana Cruz Reyes and @Ana Cruz'), ['ana', 'anam']);
      expect(ids('@Ana Cruzado is not Ana'), isEmpty);
      expect(ids('@Gina Gone @Al Admin @Helen Head'), isEmpty);
      expect(ids('no mentions'), isEmpty);
      // Inside a word or an email address isn't a mention.
      expect(ids('mail x@ana cruz now'), isEmpty);
    });

    test('two people with the same name are both told', () {
      final s = state()
        ..users = [...state().users, _u('ana2', 'Ana Cruz', 'Supervisor')];
      final ids = s.mentionedUsers('@Ana Cruz').map((u) => u.id).toList()
        ..sort();
      expect(ids, ['ana', 'ana2']);
    });

    test('posting notifies those mentioned, with the text', () async {
      final store = _Store();
      final s = state(store);
      final ok = await s.postAnnouncement(
        Announcement(
          id: 'ann_1',
          title: 'Orientation',
          body: '@Ana Cruz and @Sid Santos please attend.',
          postedBy: 'Helen Head',
          postedAt: '11/28/2026',
        ),
      );
      expect(ok, isTrue);
      await Future<void>.delayed(Duration.zero);
      final byUser = {for (final n in store.notifications) '${n['userId']}': n};
      expect(byUser['ana']!['id'], 'mention_ann_1_ana');
      expect(byUser['ana']!['title'], 'You were mentioned');
      expect(
        byUser['sid']!['message'],
        'Helen Head mentioned you in "Orientation": '
        '@Ana Cruz and @Sid Santos please attend.',
      );
      // Ana, a mentioned student, doesn't also get the general alert; the
      // other student does.
      expect(
        store.notifications.where((n) => n['userId'] == 'ana'),
        hasLength(1),
      );
      expect(byUser['oth']!['title'], 'New Hiring Announcement');

      // A Supervisor's mention opens nothing (the text is in it).
      s.currentUser = sid;
      final mention = s.notifications.firstWhere(
        (n) => n.userId == 'sid' && n.id.startsWith('mention_'),
      );
      expect(s.notificationTab(mention), isNull);
    });
  });

  for (final (name, page, hidden) in [
    ('Student Documents', const StudentDocumentsScreen(), 'All Campuses'),
    ('Rehiring', const RehiringScreen(), 'All'),
  ]) {
    testWidgets('$name on a phone shows one Filters button', (tester) async {
      final onError = FlutterError.onError;
      FlutterError.onError = (d) => d.exceptionAsString().contains('overflowed')
          ? null
          : onError?.call(d);
      addTearDown(() => FlutterError.onError = onError);
      await _pump(
        tester,
        ChangeNotifierProvider<AppState>(
          create: (_) =>
              AppState()..currentUser = _u('head', 'Helen Head', 'Head'),
          child: page,
        ),
      );
      expect(find.byType(FilterSheetButton), findsOneWidget);
      expect(find.text(hidden), findsNothing);
    });
  }
}
