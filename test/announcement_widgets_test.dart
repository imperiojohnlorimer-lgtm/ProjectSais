import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:projectsais/models/models.dart';
import 'package:projectsais/widgets/announcement_widgets.dart';

void main() {
  testWidgets('renders announcement title, status, and requirements', (tester) async {
    final announcement = Announcement(
      id: 'ann_1',
      title: 'UI Developer',
      body: 'Need a developer for the next sprint.',
      postedBy: 'Admin',
      postedAt: 'Today',
      requirements: ['Flutter', 'Dart'],
      approvalStatus: 'Pending',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnnouncementCard(announcement: announcement),
        ),
      ),
    );

    expect(find.text('UI Developer'), findsOneWidget);
    expect(find.text('Pending Approval'), findsOneWidget);
    expect(find.text('Flutter'), findsOneWidget);
    expect(find.text('Dart'), findsOneWidget);
  });
}
