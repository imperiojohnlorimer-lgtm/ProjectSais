import 'package:flutter_test/flutter_test.dart';
import 'package:projectsais/models/app_state.dart';
import 'package:projectsais/models/models.dart';

void main() {
  // The Admin's "Open Applications" setting. With it off the app refuses
  // before touching Firestore (whose rules refuse it too).
  test('no application goes through while applications are closed', () async {
    final state = AppState()
      ..currentUser = User(
        id: 'u_student',
        name: 'Sam Student',
        email: 'sam@example.com',
        role: 'Student',
      )
      ..allowAcademicApplications = false;

    final submitted = await state.submitApplication(
      Application(
        id: 'app_1',
        announcementId: 'ann_1',
        announcementTitle: 'Library Assistant',
        applicantId: 'u_student',
        applicantName: 'Sam Student',
        appliedAt: 'Sep 25, 2026',
      ),
    );

    expect(submitted, isFalse);
    expect(state.applications, isEmpty);
  });
}
