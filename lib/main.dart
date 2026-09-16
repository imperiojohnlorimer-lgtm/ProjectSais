import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'firebase_options.dart';
import 'package:provider/provider.dart';
import 'models/app_state.dart';
import 'theme/app_theme.dart';
import 'screens/app_shell.dart';
import 'screens/student_portal/student_portal_shell.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'services/schedule_service.dart';
import 'services/firestore_schedule_repository.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await Supabase.initialize(
    url: 'https://hksswjhioztqsypbrkjy.supabase.co',
    publishableKey: 'sb_publishable_9gI1i8ibybNp5qLBJpQo1A_7FCIkycd',
    accessToken: () async =>
        fb_auth.FirebaseAuth.instance.currentUser?.getIdToken(),
  );
  runApp(const SAISApp());
}

class SAISApp extends StatelessWidget {
  const SAISApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppState()..init()),
        ChangeNotifierProvider(
          create: (_) => ScheduleService(FirestoreScheduleRepository()),
        ),
      ],
      child: MaterialApp(
        title: 'SAIS',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.theme,
        home: const _AuthGate(),
      ),
    );
  }
}

class _AuthGate extends StatefulWidget {
  const _AuthGate();
  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  bool _showRegister = false;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    if (state.isAuthenticated) {
      // Students go to the Student Portal; all other roles go to the main app
      if (state.role == 'Student') return const StudentPortalShell();
      return const AppShell();
    }

    if (_showRegister) {
      return RegisterScreen(
        onBackToLogin: () => setState(() => _showRegister = false),
      );
    }

    return LoginScreen(
      onShowRegister: () => setState(() => _showRegister = true),
    );
  }
}
