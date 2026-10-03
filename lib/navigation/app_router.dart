import 'package:flutter/material.dart';
import '../models/app_state.dart';
import '../screens/app_shell.dart';
import '../screens/student_portal/student_portal_shell.dart';

/// The web address of every page. A signed-in page's address comes from
/// its sidebar label, so it reads like what was clicked: "Sent to Head" is
/// /sent-to-head, and each role's Notifications page is /notifications.
/// The Academic Year page adds the year it shows: /academic-year/2026-2027.
/// The signed-out pages are /, /login and /register.
abstract final class AppRoutes {
  static const landing = '/';
  static const login = '/login';
  static const register = '/register';

  static const _academicYear = '/academic-year';
  static final _academicYearPath = RegExp(r'^/academic-year/(\d{4}-\d{4})$');

  /// The address of the Academic Year page showing [year].
  static String academicYearPath(String year) => '$_academicYear/$year';

  /// The year an Academic Year page's address names, or null.
  static String? academicYearAt(String path) =>
      _academicYearPath.firstMatch(normalize(path))?.group(1);

  static final _pagesByRole = <String, List<({String id, String label})>>{};

  /// The pages [role] can open: tab id and sidebar label.
  static List<({String id, String label})> pagesFor(String role) =>
      _pagesByRole.putIfAbsent(
        role,
        () => role == 'Student'
            ? StudentPortalShell.pages
            : AppShell.pagesFor(role),
      );

  /// The page [role] opens on after signing in.
  static String homeTab(String role) =>
      role == 'Student' ? 'announcements' : 'dashboard';

  /// The address of [role]'s page [tab].
  static String pathFor(String role, String tab) {
    for (final page in pagesFor(role)) {
      if (page.id == tab) return '/${_slug(page.label)}';
    }
    return '/${_slug(tab)}';
  }

  /// [role]'s page at [path], or null when [role] has none there.
  static String? tabAt(String role, String path) {
    final wanted = academicYearAt(path) == null
        ? normalize(path)
        : _academicYear;
    for (final page in pagesFor(role)) {
      if ('/${_slug(page.label)}' == wanted) return page.id;
    }
    return null;
  }

  /// [path] without a trailing slash, in lower case: /Tasks/ is /tasks.
  static String normalize(String path) {
    var p = path.trim().toLowerCase();
    while (p.length > 1 && p.endsWith('/')) {
      p = p.substring(0, p.length - 1);
    }
    return p.startsWith('/') ? p : '/$p';
  }

  static String _slug(String label) => label
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
}

/// Reads the path out of the browser's address, and back.
class AppRouteParser extends RouteInformationParser<String> {
  const AppRouteParser();

  @override
  Future<String> parseRouteInformation(RouteInformation routeInformation) =>
      Future.value(AppRoutes.normalize(routeInformation.uri.path));

  @override
  RouteInformation restoreRouteInformation(String configuration) =>
      RouteInformation(uri: Uri.parse(configuration));
}

/// Keeps the address bar and the page shown in step. The page is
/// [AppState.activeTab] (or [AppState.publicPage] when signed out), which
/// every button that changes page already sets; this writes it into the
/// address bar, and opens the page an address names when the browser hands
/// one over: a link, a typed address, Back or Forward, a refresh.
///
/// A signed-in page asked for while signed out waits for sign-in with its
/// address kept, then opens. One a role doesn't have opens that role's
/// first page instead.
class AppRouterDelegate extends RouterDelegate<String>
    with ChangeNotifier, PopNavigatorRouterDelegateMixin<String> {
  AppRouterDelegate(this.state, {required this.home}) {
    state.addListener(_onStateChanged);
    _shown = currentConfiguration;
  }

  final AppState state;

  /// The app itself; [waitingForSession] while a link to a signed-in page
  /// waits for startup to restore the session.
  final Widget Function(bool waitingForSession) home;

  @override
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  /// A signed-in page asked for while signed out.
  String? _wanted;

  /// What the address bar shows, and whether the app waited, as of the last
  /// report: AppState changes all the time, mostly not the page.
  String? _shown;
  bool _waited = false;

  bool get _waitingForSession =>
      _wanted != null && !state.isAuthenticated && !state.sessionChecked;

  String get _currentTab {
    final role = state.role;
    final open = AppRoutes.pagesFor(role).any((p) => p.id == state.activeTab);
    return open ? state.activeTab : AppRoutes.homeTab(role);
  }

  @override
  String get currentConfiguration {
    if (!state.isAuthenticated) {
      return _wanted ??
          switch (state.publicPage) {
            PublicPage.landing => AppRoutes.landing,
            PublicPage.login => AppRoutes.login,
            PublicPage.register => AppRoutes.register,
          };
    }
    final tab = _currentTab;
    return tab == AppState.academicYearTab
        ? AppRoutes.academicYearPath(state.academicYearShown)
        : AppRoutes.pathFor(state.role, tab);
  }

  /// Opens [state.role]'s page at [path], or its first page when it has
  /// none there.
  void _open(String path) {
    final tab = AppRoutes.tabAt(state.role, path);
    if (tab == AppState.academicYearTab) {
      state.openAcademicYear(AppRoutes.academicYearAt(path));
    } else {
      state.setTab(tab ?? AppRoutes.homeTab(state.role));
    }
  }

  void _onStateChanged() {
    if (state.isAuthenticated) {
      final wanted = _wanted;
      _wanted = null;
      if (wanted != null && AppRoutes.tabAt(state.role, wanted) != null) {
        _open(wanted); // notifies again
        return;
      }
      if (_currentTab != state.activeTab) {
        state.setTab(_currentTab); // a page this role doesn't have
        return;
      }
    } else if (_wanted != null && state.publicPage != PublicPage.login) {
      _wanted = null; // left Login for another page
    }
    _report();
  }

  void _report() {
    final path = currentConfiguration;
    final waiting = _waitingForSession;
    if (path == _shown && waiting == _waited) return;
    _shown = path;
    _waited = waiting;
    notifyListeners();
  }

  @override
  Future<void> setNewRoutePath(String configuration) async {
    final path = AppRoutes.normalize(configuration);
    if (!state.isAuthenticated) {
      _wanted = null;
      switch (path) {
        case AppRoutes.landing:
          state.showPublicPage(PublicPage.landing);
        case AppRoutes.login:
          state.showPublicPage(PublicPage.login);
        case AppRoutes.register:
          state.showPublicPage(PublicPage.register);
        default:
          _wanted = path;
          state.showPublicPage(PublicPage.login);
      }
    } else {
      _open(path);
    }
    // The browser shows [path] now. Where that isn't the page opened (a
    // signed-in /login, a page this role doesn't have), _report puts the
    // right address back.
    _shown = path;
    _report();
  }

  @override
  Widget build(BuildContext context) => Navigator(
    key: navigatorKey,
    pages: [
      MaterialPage<void>(
        key: const ValueKey('sais'),
        child: home(_waitingForSession),
      ),
    ],
    onDidRemovePage: (_) {},
  );

  @override
  void dispose() {
    state.removeListener(_onStateChanged);
    super.dispose();
  }
}
