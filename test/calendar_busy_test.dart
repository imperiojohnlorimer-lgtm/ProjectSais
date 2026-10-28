import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:projectsais/models/app_state.dart';
import 'package:projectsais/models/models.dart';
import 'package:projectsais/models/schedule_event.dart';
import 'package:projectsais/screens/calendar/calendar_screen.dart';
import 'package:projectsais/services/schedule_repository.dart';
import 'package:projectsais/services/schedule_service.dart';
import 'package:projectsais/theme/app_theme.dart';

/// A calendar store whose saves wait for the test.
class _GatedRepository implements ScheduleRepository {
  late Completer<void> gate;
  final saved = <ScheduleEvent>[];

  @override
  Future<List<ScheduleEvent>> getEventsFor(String ownerId) async => saved;

  @override
  Stream<List<ScheduleEvent>> watchEventsFor(String ownerId) =>
      const Stream.empty();

  @override
  Future<ScheduleEvent> addEvent(ScheduleEvent event) async {
    await gate.future;
    saved.add(event);
    return event;
  }

  @override
  Future<void> deleteEvent(String id) async {}
}

void main() {
  testWidgets('Add Event keeps the form up, saving, until it is saved', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final onError = FlutterError.onError;
    addTearDown(() => FlutterError.onError = onError);
    FlutterError.onError = (details) =>
        details.exceptionAsString().contains('overflowed')
        ? null
        : onError?.call(details);

    final repository = _GatedRepository()..gate = Completer<void>();
    final user = User(
      id: 'sa1',
      name: 'Sara Assistant',
      email: 'sa@example.com',
      role: 'Student Assistant',
    );
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>(
            create: (_) => AppState()
              ..currentUser = user
              ..users = [user],
          ),
          ChangeNotifierProvider<ScheduleService>(
            create: (_) => ScheduleService(repository),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.theme,
          home: const Scaffold(body: CalendarScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add Event').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Orientation');
    await tester.tap(find.text('Add Event').last);
    await tester.pump();

    expect(find.text('Saving…'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Cancel'))
          .onPressed,
      isNull,
    );

    repository.gate.complete();
    await tester.pumpAndSettle();

    expect(find.text('Saving…'), findsNothing);
    expect(repository.saved.single.title, 'Orientation');
    // The form closed once the event was saved.
    expect(find.text('Cancel'), findsNothing);
  });
}
