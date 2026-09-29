import 'package:flutter_test/flutter_test.dart';
import 'package:projectsais/models/app_state.dart';
import 'package:projectsais/models/models.dart';
import 'package:projectsais/services/firestore_service.dart';

/// Keeps user profiles in memory the way Firestore's users collection does,
/// so a second AppState (a reload) reads back what the first one saved.
class _ProfileStore extends FirestoreService {
  final profiles = <String, User>{};

  @override
  Future<void> setUserProfile(User user) async => profiles[user.id] = user;

  @override
  Future<User?> getUserProfileById(String id) async => profiles[id];

  @override
  Future<User?> getUserProfileByEmail(String email) async => profiles.values
      .where((u) => u.email.toLowerCase() == email.toLowerCase())
      .firstOrNull;

  @override
  Future<List<User>> getAllUserProfiles() async => profiles.values.toList();
}

/// Records the task category lists the app saves.
class _CategoryStore extends FirestoreService {
  _CategoryStore({this.fail = false});

  final bool fail;
  final saved = <List<String>>[];

  @override
  Future<void> setTaskCategories(List<String> names) async {
    if (fail) throw Exception('offline');
    saved.add(names);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppState avatar persistence', () {
    late _ProfileStore store;

    setUp(() => store = _ProfileStore());

    test('restores avatar after reloading state', () async {
      final state = AppState(firestoreService: store);
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

      final reloaded = AppState(firestoreService: store);
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

    // Found by email when the account id it signs in with has changed —
    // never by name, which two people can share.
    test(
      'restores avatar for student accounts when the login id changes',
      () async {
        final state = AppState(firestoreService: store);
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

        final reloaded = AppState(firestoreService: store);
        await reloaded.init();
        await reloaded.login(
          User(
            id: 'u_seeded_student',
            name: 'Test Student',
            email: 'Student@Example.com',
            role: 'Student',
          ),
        );

        expect(
          reloaded.currentUser?.avatar,
          'data:image/png;base64,student-avatar',
        );
      },
    );

    test('does not give an avatar to someone who only shares a name', () async {
      final state = AppState(firestoreService: store);
      await state.init();
      await state.login(
        User(
          id: 'u_first',
          name: 'Test Student',
          email: 'first@example.com',
          role: 'Student',
        ),
      );
      await state.updateProfile(avatar: 'data:image/png;base64,first');

      final other = AppState(firestoreService: store);
      await other.init();
      await other.login(
        User(
          id: 'u_second',
          name: 'Test Student',
          email: 'second@example.com',
          role: 'Student',
        ),
      );

      expect(other.currentUser?.avatar, isNull);
    });
  });

  group('task categories and checklist items', () {
    test(
      'addTaskCategory saves a new category to the available options',
      () async {
        final store = _CategoryStore();
        final state = AppState(firestoreService: store);

        expect(await state.addTaskCategory('Inventory'), isTrue);

        expect(state.taskCategories, contains('Inventory'));
        expect(store.saved.single, contains('Inventory'));
      },
    );

    test('addTaskCategory refuses a category that is already listed', () async {
      final store = _CategoryStore();
      final state = AppState(firestoreService: store);

      expect(await state.addTaskCategory('Fieldwork'), isFalse);

      expect(store.saved, isEmpty);
    });

    test(
      'addTaskCategory keeps the list unchanged when the save fails',
      () async {
        final state = AppState(firestoreService: _CategoryStore(fail: true));

        expect(await state.addTaskCategory('Inventory'), isFalse);

        expect(state.taskCategories, isNot(contains('Inventory')));
      },
    );

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
      final store = _ProfileStore();
      final state = AppState(firestoreService: store);
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
      expect(store.profiles['u-year-level']?.yearLevel, '4th Year');
      expect(User.fromJson({'yearLevel': '2nd Year'}).yearLevel, '2nd Year');
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
}
