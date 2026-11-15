// Finds text that is cut off on phones.
//
//   flutter test tool/mobile_audit/mobile_audit_test.dart --update-goldens
//
// Every page of every role (and the public pages) is drawn at phone widths,
// at the normal and a larger phone font size, with Roboto: SAIS asks for
// 'Inter', which it doesn't bundle, so phones and browsers fall back to
// Roboto. For each page it notes text that was ellipsized or cut at its
// line limit, single-line text wider than its box, and every overflow, and
// saves a picture of the screen. The findings go to out/report.md and the
// pictures to out/ (git-ignored). Not part of CI: `tool/` isn't tested.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:projectsais/models/app_state.dart';
import 'package:projectsais/models/models.dart';
import 'package:projectsais/screens/app_shell.dart';
import 'package:projectsais/screens/auth/login_screen.dart';
import 'package:projectsais/screens/auth/register_screen.dart';
import 'package:projectsais/screens/landing/landing_screen.dart';
import 'package:projectsais/screens/student_portal/student_portal_shell.dart';
import 'package:projectsais/services/in_memory_schedule_repository.dart';
import 'package:projectsais/services/schedule_service.dart';
import 'package:projectsais/theme/app_theme.dart';

import 'seed.dart';

/// Phone sizes (logical px) and the font sizes to try.
const _sizes = [Size(360, 780), Size(390, 844), Size(390, 2200)];
const _scales = [1.0, 1.3];

final _findings = <String, List<String>>{};
final _counts = <String, int>{};

Future<void> _loadFonts() async {
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? r'C:\src\flutter';
  final fonts = '$flutterRoot/bin/cache/artifacts/material_fonts';
  Future<ByteData> read(String path) async =>
      ByteData.view(Uint8List.fromList(File(path).readAsBytesSync()).buffer);
  const roboto = [
    'roboto-regular.ttf',
    'roboto-italic.ttf',
    'roboto-medium.ttf',
    'roboto-mediumitalic.ttf',
    'roboto-bold.ttf',
    'roboto-bolditalic.ttf',
    'roboto-black.ttf',
    'roboto-light.ttf',
  ];
  // Text with no family (some button and dropdown styles) gets the
  // platform default, Roboto, on a phone; in a test it gets 'FlutterTest'.
  for (final family in ['Inter', 'Roboto', 'FlutterTest']) {
    final loader = FontLoader(family);
    for (final f in roboto) {
      loader.addFont(read('$fonts/$f'));
    }
    await loader.load();
  }
  await (FontLoader('MaterialIcons')
        ..addFont(read('$fonts/materialicons-regular.otf')))
      .load();
  await (FontLoader('SourceSerifDisplay')
        ..addFont(read('assets/fonts/SourceSerif4Display-Semibold.ttf')))
      .load();
}

/// What is cut off in the current frame.
List<String> _cutText(WidgetTester tester) {
  final found = <String>{};
  void visit(RenderObject o) {
    // Text with no font family (some dropdowns and buttons) is drawn with
    // the test font here, which is far wider than Roboto: it can't be
    // judged, so it's left to the pictures.
    if (o is RenderParagraph &&
        o.hasSize &&
        o.text.style?.fontFamily != null) {
      final text = o.text.toPlainText().replaceAll('\n', ' ').trim();
      if (text.isNotEmpty) {
        if (o.didExceedMaxLines) {
          found.add('CUT  "$text"');
        } else if (!o.softWrap || o.maxLines == 1) {
          final wants = o.getMaxIntrinsicWidth(double.infinity);
          if (wants > o.size.width + 1) found.add('WIDE "$text"');
        }
      }
    }
    // Hidden children aren't on screen: a dropdown keeps every item in an
    // IndexedStack to size itself, and an Offstage keeps its child laid out.
    if (o is RenderOffstage && o.offstage) return;
    if (o is RenderIndexedStack) {
      var i = 0;
      o.visitChildren((child) {
        if (i++ == o.index) visit(child);
      });
      return;
    }
    o.visitChildren(visit);
  }

  for (final view in tester.binding.renderViews) {
    visit(view);
  }
  return found.toList();
}

Widget _host(AppState state, Widget home) => MultiProvider(
  providers: [
    ChangeNotifierProvider<AppState>.value(value: state),
    ChangeNotifierProvider(
      create: (_) => ScheduleService(InMemoryScheduleRepository()),
    ),
  ],
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.theme,
    home: home,
  ),
);

String _slug(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(
      RegExp(r'^-|-$'),
      '',
    );

Future<void> _audit(
  WidgetTester tester, {
  required String name,
  required AppState Function() state,
  required Widget home,
  Future<void> Function(WidgetTester tester)? then,
}) async {
  for (final size in _sizes) {
    for (final scale in _scales) {
      final key = '$name @${size.width.toInt()} x$scale';
      final problems = <String>[];
      final errors = <String>[];
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      final onError = FlutterError.onError;
      FlutterError.onError = (details) {
        final message = details.exceptionAsString().split('\n').first;
        // Where in SAIS's code the widget that overflowed was made.
        final where =
            RegExp(r'lib/[\w/]+\.dart:\d+')
                .firstMatch(details.toString(minLevel: DiagnosticLevel.debug))
                ?.group(0) ??
            '';
        errors.add('$message $where'.trim());
      };
      final s = state();
      try {
        await tester.pumpWidget(_host(s, home));
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump(const Duration(milliseconds: 400));
        if (then != null) await then(tester);
        problems.addAll(_cutText(tester));
        // Pictures at 390 px: the phone screen (n, l = larger font) and a
        // tall one (t, tl) that shows more of the page.
        if (size.width == 390) {
          final tall = size.height > 1000;
          final tag = '${tall ? 't' : ''}${scale == 1 ? (tall ? '' : 'n') : 'l'}';
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile('out/${_slug(name)}_$tag.png'),
          );
        }
      } catch (e) {
        errors.add('THREW ${e.toString().split('\n').first}');
      } finally {
        FlutterError.onError = onError;
        tester.takeException();
      }
      final all = [
        ...problems,
        for (final e in errors.toSet())
          if (e.contains('overflowed')) 'OVERFLOW $e' else 'ERROR $e',
      ];
      _counts[key] = all.length;
      if (all.isNotEmpty) _findings[key] = all;
      await tester.pumpWidget(const SizedBox());
      s.dispose();
    }
  }
  tester.view.reset();
  tester.platformDispatcher.clearTextScaleFactorTestValue();
}

void main() {
  setUpAll(_loadFonts);

  tearDownAll(() {
    final out = StringBuffer('# Mobile text audit\n\n');
    out.writeln(
      'CUT = ellipsized or cut at its line limit; WIDE = one-line text wider '
      'than its box; OVERFLOW = a row/column too big for its space.\n',
    );
    final pages = _counts.keys.toList()..sort();
    out.writeln('${_findings.length} of ${pages.length} page renders have findings.\n');
    for (final page in pages) {
      final list = _findings[page];
      if (list == null) continue;
      out.writeln('## $page (${list.length})');
      for (final line in list) {
        out.writeln('- $line');
      }
      out.writeln();
    }
    final file = File('tool/mobile_audit/out/report.md')
      ..createSync(recursive: true);
    file.writeAsStringSync(out.toString());
    // ignore: avoid_print
    print('Report: ${file.absolute.path}');
  });

  for (final role in ['Admin', 'Head', 'Supervisor', 'Student Assistant']) {
    for (final page in AppShell.pagesFor(role)) {
      testWidgets('$role: ${page.label}', (tester) async {
        await _audit(
          tester,
          name: '$role ${page.label}',
          state: () => seededState(role)..activeTab = page.id,
          home: const AppShell(),
        );
      });
    }
    testWidgets('$role: menu', (tester) async {
      await _audit(
        tester,
        name: '$role menu',
        state: () => seededState(role),
        home: const AppShell(),
        then: (tester) async {
          await tester.tap(find.byIcon(Icons.menu_rounded).first);
          await tester.pump(const Duration(milliseconds: 400));
          await tester.pump(const Duration(milliseconds: 400));
        },
      );
    });
  }

  // The main forms and dialogs, opened from their page.
  final dialogs = <(String role, String tab, String button)>[
    ('Supervisor', 'tasks', 'Assign Task'),
    ('Head', 'tasks', 'Categories'),
    ('Supervisor', 'sv_announcements', 'New Request'),
    ('Head', 'announcements', 'Post Announcement'),
    ('Head', 'offices', 'Add Office'),
    ('Admin', 'accounts', 'Add Account'),
  ];
  for (final (role, tab, button) in dialogs) {
    testWidgets('$role dialog: $button', (tester) async {
      await _audit(
        tester,
        name: '$role dialog $button',
        state: () => seededState(role)..activeTab = tab,
        home: const AppShell(),
        then: (tester) async {
          final target = find.text(button);
          if (target.evaluate().isEmpty) return;
          await tester.ensureVisible(target.first);
          await tester.tap(target.first, warnIfMissed: false);
          await tester.pump(const Duration(milliseconds: 400));
          await tester.pump(const Duration(milliseconds: 400));
        },
      );
    });
  }

  for (final page in StudentPortalShell.pages) {
    testWidgets('Student: ${page.label}', (tester) async {
      await _audit(
        tester,
        name: 'Student ${page.label}',
        state: () => seededState('Student')..activeTab = page.id,
        home: const StudentPortalShell(),
      );
    });
  }

  final public = <String, Widget>{
    'Landing': LandingScreen(onSignIn: () {}, onGetStarted: () {}),
    'Login': LoginScreen(onShowRegister: () {}),
    'Register': RegisterScreen(onBackToLogin: () {}),
  };
  for (final entry in public.entries) {
    testWidgets('Public: ${entry.key}', (tester) async {
      await _audit(
        tester,
        name: 'Public ${entry.key}',
        state: () => AppState(),
        home: Scaffold(body: entry.value),
      );
    });
  }
}
