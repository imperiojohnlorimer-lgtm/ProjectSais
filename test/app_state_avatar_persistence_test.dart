import 'package:flutter_test/flutter_test.dart';
import 'package:projectsais/models/app_state.dart';
import 'package:projectsais/models/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppState avatar persistence', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
    });

    test('restores avatar after reloading state', () async {
      final state = AppState();
      await state.init();

      await state.login(
        User(
          id: 'u1',
          name: 'Test User',
          email: 'test@example.com',
          role: 'Student Assistant',
        ),
      );

      await state.updateProfile(avatar: 'data:image/png;base64,abc123');

      final reloaded = AppState();
      await reloaded.init();
      await reloaded.login(
        User(
          id: 'u1',
          name: 'Test User',
          email: 'test@example.com',
          role: 'Student Assistant',
        ),
      );

      expect(reloaded.currentUser?.avatar, 'data:image/png;base64,abc123');
    });

    test(
      'restores avatar for student accounts when the login id changes',
      () async {
        final state = AppState();
        await state.init();

        await state.login(
          User(
            id: 'u_student_123',
            name: 'Test Student',
            email: 'student@example.com',
            role: 'Student',
          ),
        );

        await state.updateProfile(
          avatar: 'data:image/png;base64,student-avatar',
        );

        final reloaded = AppState();
        await reloaded.init();
        await reloaded.login(
          User(
            id: 'u_seeded_student',
            name: 'Test Student',
            email: 'test@example.com',
            role: 'Student',
          ),
        );

        expect(
          reloaded.currentUser?.avatar,
          'data:image/png;base64,student-avatar',
        );
      },
    );
  });

  group('task categories and checklist items', () {
    test('addTaskCategory adds a new category to the available options', () {
      final state = AppState();

      state.addTaskCategory('Fieldwork');

      expect(state.taskCategories, contains('Fieldwork'));
    });

    test('tasks store category and checklist items', () {
      final task = Task(
        id: 't1',
        title: 'Inventory Review',
        description: 'Check equipment stock',
        status: 'Not Started',
        priority: 'Medium',
        dueDate: 'May 25, 2026',
        category: 'Administration',
        checklistItems: const ['Count items', 'Submit report'],
      );

      expect(task.category, 'Administration');
      expect(task.checklistItems, ['Count items', 'Submit report']);
    });
  });

  group('user profile data', () {
    test('stores and restores year level in the profile model', () async {
      final state = AppState();
      await state.init();

      state.currentUser = User(
        id: 'u-year-level',
        name: 'Yearly Student',
        email: 'yearly@example.com',
        role: 'Student',
        yearLevel: '3rd Year',
      );

      await state.updateProfile(yearLevel: '4th Year');

      expect(state.currentUser?.yearLevel, '4th Year');
      expect(
        User.fromJson({'yearLevel': '2nd Year'}).yearLevel,
        '2nd Year',
      );
    });
  });

  group('application skills', () {
    test('shows skills from approved applications only', () {
      final state = AppState();
      final user = User(
        id: 'u1',
        name: 'Test User',
        email: 'test@example.com',
        role: 'Student',
        skills: const ['Existing skill'],
      );
      state.users = [user];
      state.applications = [
        Application(
          id: 'a-pending',
          announcementId: 'ann-1',
          announcementTitle: 'Pending role',
          applicantId: 'u1',
          applicantName: 'Test User',
          appliedAt: '2026-08-23',
          skills: const ['Pending skill'],
        ),
        Application(
          id: 'a-approved',
          announcementId: 'ann-2',
          announcementTitle: 'Approved role',
          applicantId: 'u1',
          applicantName: 'Test User',
          appliedAt: '2026-08-23',
          status: 'Approved',
          skills: const ['Approved skill'],
        ),
      ];

      expect(state.skillsForUser(user), ['Approved skill', 'Existing skill']);
    });
  });

  group('announcement notifications', () {
    test(
      'submitAnnouncementForApproval notifies the currently logged-in admin as a fallback',
      () {
        final state = AppState();
        state.currentUser = User(
          id: 'admin-current',
          name: 'Admin User',
          email: 'admin@example.com',
          role: 'Admin',
        );
        state.users = [
          User(
            id: 'u-supervisor',
            name: 'Supervisor User',
            email: 'supervisor@example.com',
            role: 'Supervisor',
          ),
        ];

        state.submitAnnouncementForApproval(
          Announcement(
            id: 'a-approval',
            title: 'Pending Internship',
            body: 'Body',
            postedBy: 'Supervisor User',
            postedByRole: 'Supervisor',
            postedAt: '2026-07-30',
            postedById: 'u-supervisor',
            approvalStatus: 'Pending',
            isOpen: false,
          ),
        );

        expect(
          state.notifications.any(
            (n) =>
                n.userId == 'admin-current' &&
                n.title == 'Announcement Awaiting Approval',
          ),
          isTrue,
        );
      },
    );

    test(
      'admin users can see notifications targeted to other admin accounts',
      () {
        final state = AppState();
        state.currentUser = User(
          id: 'u-admin-2',
          name: 'Admin Two',
          email: 'admin2@example.com',
          role: 'Admin',
        );
        state.users = [
          User(
            id: 'u-admin-1',
            name: 'Admin One',
            email: 'admin1@example.com',
            role: 'Admin',
          ),
          User(
            id: 'u-admin-2',
            name: 'Admin Two',
            email: 'admin2@example.com',
            role: 'Admin',
          ),
        ];
        state.notifications = [
          AppNotification(
            id: 'n-admin-1',
            userId: 'u-admin-1',
            title: 'Announcement Awaiting Approval',
            message: 'A supervisor submitted a new announcement.',
            type: 'announcement',
            createdAt: 'Today',
          ),
        ];

        expect(state.myNotifications, hasLength(1));
      },
    );

    test(
      'approveAnnouncement notifies the submitter by postedById even without a matching user record',
      () async {
        final state = AppState();
        state.users = [
          User(
            id: 'u-student',
            name: 'Student User',
            email: 'student@example.com',
            role: 'Student',
          ),
        ];
        state.announcements = [
          Announcement(
            id: 'a1',
            title: 'Summer Internship',
            body: 'Body',
            postedBy: 'Supervisor Name',
            postedByRole: 'Supervisor',
            postedAt: '2026-07-30',
            postedById: 'u-supervisor',
            approvalStatus: 'Pending',
            isOpen: false,
          ),
        ];

        await state.approveAnnouncement('a1');

        expect(
          state.notifications.any(
            (n) =>
                n.userId == 'u-supervisor' &&
                n.title == 'Announcement Approved',
          ),
          isTrue,
        );
      },
    );

    test(
      'rejectAnnouncement notifies the submitter by postedById even without a matching user record',
      () {
        final state = AppState();
        state.announcements = [
          Announcement(
            id: 'a2',
            title: 'Winter Internship',
            body: 'Body',
            postedBy: 'Supervisor Name',
            postedByRole: 'Supervisor',
            postedAt: '2026-07-30',
            postedById: 'u-supervisor-2',
            approvalStatus: 'Pending',
            isOpen: false,
          ),
        ];

        state.rejectAnnouncement('a2', reason: 'Needs more detail');

        expect(
          state.notifications.any(
            (n) =>
                n.userId == 'u-supervisor-2' &&
                n.title == 'Announcement Rejected',
          ),
          isTrue,
        );
      },
    );
  });
}
