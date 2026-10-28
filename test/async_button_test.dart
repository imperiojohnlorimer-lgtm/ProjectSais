import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:projectsais/widgets/shared_widgets.dart';

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

void main() {
  runWithBusyTests();
  testWidgets('shows a spinner and the busy label while waiting', (
    tester,
  ) async {
    final done = Completer<void>();
    await tester.pumpWidget(
      _host(
        AsyncButton(
          label: 'Save',
          busyLabel: 'Saving…',
          icon: Icons.save,
          onPressed: () => done.future,
        ),
      ),
    );
    expect(find.text('Save'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.tap(find.text('Save'));
    await tester.pump();

    expect(find.text('Saving…'), findsOneWidget);
    expect(find.text('Save'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNull,
    );

    done.complete();
    await tester.pump();

    expect(find.text('Save'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('a second tap while waiting does not run the action again', (
    tester,
  ) async {
    var runs = 0;
    final done = Completer<void>();
    await tester.pumpWidget(
      _host(
        AsyncButton(
          label: 'Go',
          kind: AsyncButtonKind.outlined,
          onPressed: () {
            runs++;
            return done.future;
          },
        ),
      ),
    );
    await tester.tap(find.text('Go'));
    await tester.pump();
    // No icon was given: the spinner still shows.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.byType(OutlinedButton), warnIfMissed: false);
    await tester.pump();
    expect(runs, 1);
    done.complete();
    await tester.pump();
  });

  testWidgets('comes back after the action throws', (tester) async {
    final errors = <Object>[];
    await runZonedGuarded(() async {
      await tester.pumpWidget(
        _host(
          AsyncButton(
            label: 'Try',
            kind: AsyncButtonKind.text,
            onPressed: () async => throw StateError('nope'),
          ),
        ),
      );
      await tester.tap(find.text('Try'));
      await tester.pump();
      await tester.pump();
    }, (error, _) => errors.add(error));

    expect(errors, hasLength(1));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(
      tester.widget<TextButton>(find.byType(TextButton)).onPressed,
      isNotNull,
    );
  });

  testWidgets('is safe when removed while waiting', (tester) async {
    final done = Completer<void>();
    await tester.pumpWidget(
      _host(AsyncButton(label: 'Save', onPressed: () => done.future)),
    );
    await tester.tap(find.text('Save'));
    await tester.pump();

    await tester.pumpWidget(_host(const SizedBox()));
    done.complete();
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('waits for the answer to "are you sure?" before it spins', (
    tester,
  ) async {
    final answer = Completer<bool>();
    var runs = 0;
    await tester.pumpWidget(
      _host(
        AsyncButton(
          label: 'Delete',
          busyLabel: 'Deleting…',
          confirm: () => answer.future,
          onPressed: () async => runs++,
        ),
      ),
    );
    await tester.tap(find.text('Delete'));
    await tester.pump();
    // Still asking: no spinner yet.
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Delete'), findsOneWidget);

    answer.complete(false);
    await tester.pump();
    expect(runs, 0);
    expect(find.text('Delete'), findsOneWidget);
  });

  testWidgets('a yes to the question runs the action with a spinner', (
    tester,
  ) async {
    final done = Completer<void>();
    await tester.pumpWidget(
      _host(
        AsyncButton(
          label: 'Delete',
          busyLabel: 'Deleting…',
          confirm: () async => true,
          onPressed: () => done.future,
        ),
      ),
    );
    await tester.tap(find.text('Delete'));
    await tester.pump();
    expect(find.text('Deleting…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    done.complete();
    await tester.pump();
    expect(find.text('Delete'), findsOneWidget);
  });

  testWidgets('a second tap while it is still asking starts nothing', (
    tester,
  ) async {
    final answer = Completer<bool>();
    var asked = 0;
    var runs = 0;
    await tester.pumpWidget(
      _host(
        AsyncButton(
          label: 'Delete',
          confirm: () {
            asked++;
            return answer.future;
          },
          onPressed: () async => runs++,
        ),
      ),
    );
    await tester.tap(find.text('Delete'));
    await tester.tap(find.text('Delete'));
    await tester.pump();
    answer.complete(true);
    await tester.pump();
    await tester.pump();

    expect(asked, 1);
    expect(runs, 1);
  });

  testWidgets('with no action it is disabled', (tester) async {
    await tester.pumpWidget(
      _host(const AsyncButton(label: 'Save', onPressed: null)),
    );
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNull,
    );
  });
}

void runWithBusyTests() {
  testWidgets('runWithBusy shows a working card until the work is done', (
    tester,
  ) async {
    final done = Completer<int>();
    int? result;
    await tester.pumpWidget(
      _host(
        Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async => result = await runWithBusy(
              context,
              () => done.future,
              message: 'Deleting…',
            ),
            child: const Text('Go'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Deleting…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    done.complete(7);
    await tester.pumpAndSettle();
    expect(find.text('Deleting…'), findsNothing);
    expect(result, 7);
  });

  testWidgets('runWithBusy takes the card away when the work throws', (
    tester,
  ) async {
    final errors = <Object>[];
    await runZonedGuarded(() async {
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => runWithBusy<void>(
                context,
                () async => throw StateError('nope'),
              ),
              child: const Text('Go'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Go'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
    }, (error, _) => errors.add(error));
    expect(errors, hasLength(1));
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
