import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'firebase_options.dart';
import 'package:provider/provider.dart';
import 'models/app_state.dart';
import 'navigation/app_router.dart';
import 'theme/app_theme.dart';
import 'screens/app_shell.dart';
import 'screens/student_portal/student_portal_shell.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/landing/landing_screen.dart';
import 'services/schedule_service.dart';
import 'services/firestore_schedule_repository.dart';

void main() async {
  // Addresses like /tasks rather than /#/tasks. Firebase Hosting serves the
  // app for every path (firebase.json's rewrite), so they all load it.
  usePathUrlStrategy();
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

class SAISApp extends StatefulWidget {
  const SAISApp({super.key});

  @override
  State<SAISApp> createState() => _SAISAppState();
}

class _SAISAppState extends State<SAISApp> {
  final _state = AppState()..init();
  late final _router = AppRouterDelegate(
    _state,
    home: (waitingForSession) =>
        _AuthGate(waitingForSession: waitingForSession),
  );

  @override
  void dispose() {
    _router.dispose();
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _state),
        ChangeNotifierProvider(
          create: (_) => ScheduleService(FirestoreScheduleRepository()),
        ),
      ],
      child: MaterialApp.router(
        title: 'SAIS',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.theme,
        routerDelegate: _router,
        routeInformationParser: const AppRouteParser(),
      ),
    );
  }
}

class _AuthGate extends StatelessWidget {
  /// Set while a link to a signed-in page waits for startup to restore the
  /// session, so Login doesn't flash up first.
  final bool waitingForSession;

  const _AuthGate({required this.waitingForSession});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    if (state.isAuthenticated) {
      // Students go to the Student Portal; all other roles go to the main app
      if (state.role == 'Student') return const StudentPortalShell();
      return const AppShell();
    }

    if (waitingForSession) {
      return const Scaffold(
        backgroundColor: AppTheme.slate50,
        body: Center(child: CircularProgressIndicator(color: AppTheme.maroon)),
      );
    }

    void go(PublicPage page) => state.showPublicPage(page);
    switch (state.publicPage) {
      case PublicPage.register:
        return RegisterScreen(
          onBackToLogin: () => go(PublicPage.login),
          onBack: () => go(PublicPage.landing),
        );
      case PublicPage.login:
        return LoginScreen(
          onShowRegister: () => go(PublicPage.register),
          onBack: () => go(PublicPage.landing),
        );
      case PublicPage.landing:
        return LandingScreen(
          onSignIn: () => go(PublicPage.login),
          onGetStarted: () => go(PublicPage.register),
        );
    }
  }
}
