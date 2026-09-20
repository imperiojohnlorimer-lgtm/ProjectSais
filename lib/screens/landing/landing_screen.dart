import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../widgets/shared_widgets.dart';

/// Public marketing / entry page shown before a user signs in.
///
/// Sections: hero, capability strip, features, roles, how-it-works, CTA, footer.
/// The layout collapses from a multi-column desktop grid to a single column on
/// phones; the nav links turn into an end drawer below [_mobileBreakpoint].
class LandingScreen extends StatefulWidget {
  final VoidCallback onSignIn;
  final VoidCallback onGetStarted;

  const LandingScreen({
    super.key,
    required this.onSignIn,
    required this.onGetStarted,
  });

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen> {
  static const double _mobileBreakpoint = 900;
  static const double _wideBreakpoint = 1180;
  static const double _headerHeight = 76;
  static const double _maxContentWidth = 1140;

  final _scroll = ScrollController();
  final _featuresKey = GlobalKey();
  final _rolesKey = GlobalKey();
  final _howKey = GlobalKey();

  /// Drives the header's transition from transparent-over-hero to solid white.
  bool _scrolled = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      final scrolled = _scroll.offset > 24;
      if (scrolled != _scrolled) setState(() => _scrolled = scrolled);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _scrollTo(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isMobile = width < _mobileBreakpoint;
    final isWide = width >= _wideBreakpoint;

    // The inline nav needs more room than the hero layout does, so it folds
    // into the drawer earlier than the page switches to its mobile layout.
    final useDrawerNav = width < 1024;

    return Scaffold(
      backgroundColor: Colors.white,
      endDrawer: useDrawerNav ? _buildDrawer() : null,
      body: Stack(
        children: [
          Positioned.fill(
            child: SingleChildScrollView(
              controller: _scroll,
              physics: const BouncingScrollPhysics(),
              child: Column(
                children: [
                  _buildHero(isMobile, isWide),
                  _buildCapabilityStrip(isMobile),
                  _buildFeatures(
                    key: _featuresKey,
                    isMobile: isMobile,
                    isWide: isWide,
                  ),
                  _buildRoles(key: _rolesKey, isMobile: isMobile),
                  _buildHowItWorks(key: _howKey, isMobile: isMobile),
                  _buildCallToAction(isMobile),
                  _buildFooter(isMobile),
                ],
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _buildHeader(isMobile, useDrawerNav),
          ),
        ],
      ),
    );
  }

  // ─── Header ───────────────────────────────────────────────────────────
  Widget _buildHeader(bool isMobile, bool useDrawerNav) {
    // Over the maroon hero the header is transparent with light text; once the
    // user scrolls past it, it becomes an opaque white bar with dark text.
    final onDark = !_scrolled;
    final foreground = onDark ? Colors.white : AppTheme.slate700;
    final width = MediaQuery.sizeOf(context).width;
    final showBrandSubtitle = width >= _wideBreakpoint;
    // On the narrowest phones the drawer carries sign-in; keeping the button
    // here would squeeze the wordmark down to a few pixels.
    final showInlineSignIn = width >= 400;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      height: _headerHeight,
      decoration: BoxDecoration(
        color: onDark ? Colors.transparent : Colors.white,
        border: Border(
          bottom: BorderSide(
            color: onDark ? Colors.transparent : AppTheme.slate200,
          ),
        ),
        boxShadow: onDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _maxContentWidth),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: isMobile ? 20 : 32),
              child: Row(
                children: [
                  const AppLogo(size: 40, shadow: []),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SAIS',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                            color: onDark ? Colors.white : AppTheme.slate900,
                          ),
                        ),
                        // The full name only fits beside the nav links once
                        // there is room for both; below that the mark alone
                        // carries the brand.
                        if (showBrandSubtitle)
                          Text(
                            'Student Assistant Information System',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.3,
                              color: onDark
                                  ? Colors.white.withValues(alpha: 0.75)
                                  : AppTheme.slate500,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  if (!useDrawerNav) ...[
                    _navLink(
                      'Features',
                      foreground,
                      () => _scrollTo(_featuresKey),
                    ),
                    _navLink('Roles', foreground, () => _scrollTo(_rolesKey)),
                    _navLink(
                      'How it works',
                      foreground,
                      () => _scrollTo(_howKey),
                    ),
                    const SizedBox(width: 12),
                    TextButton(
                      onPressed: widget.onSignIn,
                      style: TextButton.styleFrom(foregroundColor: foreground),
                      child: const Text('Sign in'),
                    ),
                    const SizedBox(width: 8),
                    _primaryButton(
                      label: 'Get started',
                      onPressed: widget.onGetStarted,
                      onDark: onDark,
                      compact: true,
                    ),
                  ] else ...[
                    if (showInlineSignIn)
                      TextButton(
                        onPressed: widget.onSignIn,
                        style: TextButton.styleFrom(
                          foregroundColor: foreground,
                        ),
                        child: const Text('Sign in'),
                      ),
                    Builder(
                      builder: (ctx) => IconButton(
                        onPressed: () => Scaffold.of(ctx).openEndDrawer(),
                        icon: Icon(Icons.menu_rounded, color: foreground),
                        tooltip: 'Menu',
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _navLink(String label, Color color, VoidCallback onTap) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      ),
      child: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
    );
  }

  Widget _buildDrawer() {
    void go(GlobalKey key) {
      Navigator.of(context).pop();
      Future.delayed(const Duration(milliseconds: 220), () => _scrollTo(key));
    }

    return Drawer(
      backgroundColor: Colors.white,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppTheme.maroon, AppTheme.maroonDark],
                ),
                border: Border(
                  bottom: BorderSide(color: AppTheme.gold400, width: 2),
                ),
              ),
              child: const Row(
                children: [
                  AppLogo(size: 44),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'SAIS',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(
                Icons.widgets_outlined,
                color: AppTheme.slate600,
              ),
              title: const Text('Features'),
              onTap: () => go(_featuresKey),
            ),
            ListTile(
              leading: const Icon(
                Icons.groups_outlined,
                color: AppTheme.slate600,
              ),
              title: const Text('Roles'),
              onTap: () => go(_rolesKey),
            ),
            ListTile(
              leading: const Icon(
                Icons.route_outlined,
                color: AppTheme.slate600,
              ),
              title: const Text('How it works'),
              onTap: () => go(_howKey),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        widget.onGetStarted();
                      },
                      child: const Text('Create an account'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        widget.onSignIn();
                      },
                      child: const Text('Sign in'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Hero ─────────────────────────────────────────────────────────────
  Widget _buildHero(bool isMobile, bool isWide) {
    return Container(
      width: double.infinity,
      clipBehavior: Clip.hardEdge,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.maroon, AppTheme.maroonDark],
        ),
        border: Border(bottom: BorderSide(color: AppTheme.gold400, width: 3)),
      ),
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          Positioned(
            top: -70,
            right: -60,
            child: _circle(240, AppTheme.gold300.withValues(alpha: 0.12)),
          ),
          Positioned(
            bottom: -90,
            left: -70,
            child: _circle(220, Colors.white.withValues(alpha: 0.05)),
          ),
          Positioned(
            bottom: 60,
            right: 120,
            child: _circle(90, AppTheme.gold300.withValues(alpha: 0.07)),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              isMobile ? 20 : 32,
              _headerHeight + (isMobile ? 36 : 64),
              isMobile ? 20 : 32,
              isMobile ? 56 : 88,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _maxContentWidth),
                child: isMobile
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _heroCopy(isMobile),
                          const SizedBox(height: 40),
                          _heroPreviewCard(),
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(flex: 6, child: _heroCopy(isMobile)),
                          SizedBox(width: isWide ? 56 : 36),
                          Expanded(flex: 5, child: _heroPreviewCard()),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroCopy(bool isMobile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppTheme.gold400.withValues(alpha: 0.45)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.auto_awesome, size: 14, color: AppTheme.goldLight),
              SizedBox(width: 8),
              Flexible(
                child: Text(
                  'One system, from application to payroll',
                  style: TextStyle(
                    color: AppTheme.goldLight,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        Text(
          'Run your Student\nAssistant program\nwithout the paperwork.',
          style: TextStyle(
            fontSize: isMobile ? 34 : 50,
            height: 1.1,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            letterSpacing: isMobile ? -0.8 : -1.4,
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'SAIS brings applications, screening, duty schedules, attendance, '
          'tasks, evaluations, and payroll into a single record — so offices, '
          'supervisors, and student assistants all work from the same source '
          'of truth.',
          style: TextStyle(
            fontSize: isMobile ? 15 : 16.5,
            height: 1.6,
            color: Colors.white.withValues(alpha: 0.82),
            fontWeight: FontWeight.w400,
          ),
        ),
        const SizedBox(height: 30),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _primaryButton(
              label: 'Get started',
              onPressed: widget.onGetStarted,
              onDark: true,
              icon: Icons.arrow_forward_rounded,
            ),
            OutlinedButton(
              onPressed: widget.onSignIn,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(
                  color: Colors.white.withValues(alpha: 0.55),
                  width: 1.5,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 26,
                  vertical: 16,
                ),
              ),
              child: const Text('Sign in to your account'),
            ),
          ],
        ),
        const SizedBox(height: 26),
        const Wrap(
          spacing: 20,
          runSpacing: 10,
          children: [
            _HeroNote(icon: Icons.lock_outline, label: 'Role-based access'),
            _HeroNote(icon: Icons.sync_outlined, label: 'Real-time records'),
            _HeroNote(
              icon: Icons.description_outlined,
              label: 'Official forms generated',
            ),
          ],
        ),
      ],
    );
  }

  /// Stylised in-app preview: a miniature of the dashboard users land on.
  Widget _heroPreviewCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 40,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Window chrome with the gold underline that echoes the app's AppBar.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(
                bottom: BorderSide(color: AppTheme.gold400, width: 2.5),
              ),
            ),
            child: Row(
              children: [
                _dot(AppTheme.red500),
                const SizedBox(width: 6),
                _dot(AppTheme.amber500),
                const SizedBox(width: 6),
                _dot(AppTheme.emerald500),
                const SizedBox(width: 14),
                const Text(
                  'Dashboard',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.slate700,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
          ),
          Container(
            color: AppTheme.slate50,
            padding: const EdgeInsets.all(16),
            child: const Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _MiniStat(
                        label: 'On duty now',
                        value: '24',
                        icon: Icons.access_time_filled,
                        tint: AppTheme.emerald500,
                      ),
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: _MiniStat(
                        label: 'Pending',
                        value: '7',
                        icon: Icons.assignment_outlined,
                        tint: AppTheme.amber500,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 10),
                _MiniRow(
                  icon: Icons.how_to_reg_outlined,
                  title: 'Applicant endorsed',
                  subtitle: 'Registrar’s Office · 2 min ago',
                  tint: AppTheme.maroon,
                ),
                SizedBox(height: 8),
                _MiniRow(
                  icon: Icons.task_alt,
                  title: 'Task completed',
                  subtitle: 'Library · Shelving · today',
                  tint: AppTheme.blue500,
                ),
                SizedBox(height: 8),
                _MiniRow(
                  icon: Icons.description_outlined,
                  title: 'DTR submitted for review',
                  subtitle: 'September · awaiting supervisor',
                  tint: AppTheme.violet500,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Capability strip ─────────────────────────────────────────────────
  Widget _buildCapabilityStrip(bool isMobile) {
    const items = [
      ('4', 'user roles', 'Admin, Head, Supervisor, Student'),
      ('6', 'official documents', 'Generated from approved templates'),
      ('1', 'student record', 'From application through payroll'),
    ];

    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 20 : 32,
        vertical: isMobile ? 32 : 44,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxContentWidth),
          child: Wrap(
            spacing: 24,
            runSpacing: 24,
            alignment: WrapAlignment.spaceBetween,
            children: [
              for (final item in items)
                SizedBox(
                  width: isMobile ? double.infinity : 320,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.$1,
                        style: const TextStyle(
                          fontSize: 40,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.maroon,
                          height: 1,
                          letterSpacing: -1.5,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.$2,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.slate800,
                                letterSpacing: 0.2,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              item.$3,
                              style: const TextStyle(
                                fontSize: 12.5,
                                height: 1.4,
                                color: AppTheme.slate500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Features ─────────────────────────────────────────────────────────
  Widget _buildFeatures({
    required Key key,
    required bool isMobile,
    required bool isWide,
  }) {
    const features = [
      (
        Icons.how_to_reg_outlined,
        'Applications & screening',
        'Publish openings, collect student applications, record interview '
            'assessments, and endorse applicants to the right office.',
      ),
      (
        Icons.access_time_filled,
        'Attendance & DTR',
        'Time-in and time-out logging that rolls straight into the monthly DTR '
            'and accomplishment report, ready for signature.',
      ),
      (
        Icons.calendar_today_outlined,
        'Duty scheduling',
        'Build recurring duty schedules per office and academic year, and catch '
            'conflicts before they reach the student.',
      ),
      (
        Icons.task_alt,
        'Tasks & evaluation',
        'Assign work, track completion, and let supervisors run structured '
            'performance evaluations each term.',
      ),
      (
        Icons.payments_outlined,
        'Payroll summaries',
        'Turn verified duty hours into payroll summaries by department, office, '
            'and academic year.',
      ),
      (
        Icons.folder_copy_outlined,
        'Document generation',
        'Contracts of appointment, endorsement letters, and evaluation forms '
            'produced from your official templates.',
      ),
    ];

    final columns = isMobile ? 1 : (isWide ? 3 : 2);

    return Container(
      key: key,
      width: double.infinity,
      color: AppTheme.slate50,
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 20 : 32,
        vertical: isMobile ? 56 : 88,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxContentWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionHeading(
                eyebrow: 'What it does',
                title: 'Every stage of the program, in one place',
                subtitle:
                    'No more scattered spreadsheets, printed logsheets, and '
                    'chat threads. Each step feeds the next.',
              ),
              const SizedBox(height: 40),
              LayoutBuilder(
                builder: (context, constraints) {
                  const gap = 20.0;
                  final cardWidth =
                      (constraints.maxWidth - gap * (columns - 1)) / columns;
                  return Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      for (final f in features)
                        SizedBox(
                          width: cardWidth,
                          child: _FeatureCard(
                            icon: f.$1,
                            title: f.$2,
                            body: f.$3,
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Roles ────────────────────────────────────────────────────────────
  Widget _buildRoles({required Key key, required bool isMobile}) {
    const roles = [
      (
        Icons.admin_panel_settings_outlined,
        'Administrator',
        'Owns the system',
        [
          'Manage accounts and departments',
          'Set the academic year and offices',
          'Oversee payroll and reports',
        ],
      ),
      (
        Icons.business_outlined,
        'Office Head',
        'Requests and endorses',
        [
          'Request student assistants',
          'Screen and endorse applicants',
          'Monitor the office’s roster',
        ],
      ),
      (
        Icons.supervisor_account_outlined,
        'Supervisor',
        'Runs day-to-day duty',
        [
          'Approve attendance and DTRs',
          'Assign and review tasks',
          'Complete performance evaluations',
        ],
      ),
      (
        Icons.school_outlined,
        'Student Assistant',
        'Works and reports',
        [
          'Apply and upload requirements',
          'View schedule and log duty hours',
          'Submit accomplishment reports',
        ],
      ),
    ];

    return Container(
      key: key,
      width: double.infinity,
      color: Colors.white,
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 20 : 32,
        vertical: isMobile ? 56 : 88,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxContentWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionHeading(
                eyebrow: 'Who it is for',
                title: 'One system, four points of view',
                subtitle:
                    'Everyone signs in to the same record and sees only what '
                    'their role needs.',
              ),
              const SizedBox(height: 40),
              LayoutBuilder(
                builder: (context, constraints) {
                  const gap = 20.0;
                  final columns = constraints.maxWidth >= 1000
                      ? 4
                      : (constraints.maxWidth >= 640 ? 2 : 1);
                  final cardWidth =
                      (constraints.maxWidth - gap * (columns - 1)) / columns;
                  return Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      for (final r in roles)
                        SizedBox(
                          width: cardWidth,
                          child: _RoleCard(
                            icon: r.$1,
                            title: r.$2,
                            tagline: r.$3,
                            points: r.$4,
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── How it works ─────────────────────────────────────────────────────
  Widget _buildHowItWorks({required Key key, required bool isMobile}) {
    const steps = [
      (
        '01',
        'Apply',
        'Students register, complete their profile, and submit requirements '
            'online.',
      ),
      (
        '02',
        'Screen & endorse',
        'Offices interview applicants, record the assessment, and endorse the '
            'qualified ones.',
      ),
      (
        '03',
        'Deploy',
        'Appoint the student to an office with a duty schedule and a '
            'supervisor.',
      ),
      (
        '04',
        'Track & report',
        'Log hours, complete tasks, then generate DTRs, evaluations, and '
            'payroll.',
      ),
    ];

    return Container(
      key: key,
      width: double.infinity,
      color: AppTheme.maroon50,
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 20 : 32,
        vertical: isMobile ? 56 : 88,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxContentWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionHeading(
                eyebrow: 'How it works',
                title: 'From application to payroll in four steps',
                subtitle:
                    'The record a student starts on day one is the same record '
                    'that produces their contract, DTR, and pay summary.',
              ),
              const SizedBox(height: 40),
              LayoutBuilder(
                builder: (context, constraints) {
                  const gap = 20.0;
                  final columns = constraints.maxWidth >= 1000
                      ? 4
                      : (constraints.maxWidth >= 640 ? 2 : 1);
                  final cardWidth =
                      (constraints.maxWidth - gap * (columns - 1)) / columns;
                  return Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      for (final s in steps)
                        SizedBox(
                          width: cardWidth,
                          child: _StepCard(
                            number: s.$1,
                            title: s.$2,
                            body: s.$3,
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Call to action ───────────────────────────────────────────────────
  Widget _buildCallToAction(bool isMobile) {
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 20 : 32,
        vertical: isMobile ? 48 : 72,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxContentWidth),
          child: Container(
            clipBehavior: Clip.hardEdge,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppTheme.maroon, AppTheme.maroonDark],
              ),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.maroon.withValues(alpha: 0.28),
                  blurRadius: 30,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: Stack(
              children: [
                Positioned(
                  top: -50,
                  right: -30,
                  child: _circle(160, AppTheme.gold300.withValues(alpha: 0.12)),
                ),
                Padding(
                  padding: EdgeInsets.all(isMobile ? 28 : 48),
                  child: Flex(
                    direction: isMobile ? Axis.vertical : Axis.horizontal,
                    crossAxisAlignment: isMobile
                        ? CrossAxisAlignment.start
                        : CrossAxisAlignment.center,
                    children: [
                      Flexible(
                        flex: isMobile ? 0 : 3,
                        fit: isMobile ? FlexFit.loose : FlexFit.tight,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Ready to get your office on SAIS?',
                              style: TextStyle(
                                fontSize: isMobile ? 24 : 30,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                height: 1.2,
                                letterSpacing: -0.6,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Create an account to apply as a student '
                              'assistant, or sign in if your office already '
                              'has access.',
                              style: TextStyle(
                                fontSize: 14.5,
                                height: 1.6,
                                color: Colors.white.withValues(alpha: 0.8),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: isMobile ? 0 : 32,
                        height: isMobile ? 26 : 0,
                      ),
                      Flexible(
                        flex: isMobile ? 0 : 2,
                        fit: FlexFit.loose,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _primaryButton(
                              label: 'Create an account',
                              onPressed: widget.onGetStarted,
                              onDark: true,
                              stretch: true,
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton(
                              onPressed: widget.onSignIn,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: BorderSide(
                                  color: Colors.white.withValues(alpha: 0.5),
                                  width: 1.5,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                              ),
                              child: const Text('Sign in'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Footer ───────────────────────────────────────────────────────────
  Widget _buildFooter(bool isMobile) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: AppTheme.slate900,
        border: Border(top: BorderSide(color: AppTheme.gold400, width: 3)),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 20 : 32,
        vertical: 36,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxContentWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const AppLogo(size: 40, shadow: []),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'SAIS',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                          ),
                        ),
                        Text(
                          'Student Assistant Information System',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              Divider(color: Colors.white.withValues(alpha: 0.12), height: 1),
              const SizedBox(height: 12),
              Wrap(
                spacing: 16,
                runSpacing: 8,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    '© ${DateTime.now().year} SAIS. All rights reserved.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 12,
                    ),
                  ),
                  Wrap(
                    children: [
                      TextButton(
                        onPressed: widget.onSignIn,
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white.withValues(alpha: 0.75),
                        ),
                        child: const Text('Sign in'),
                      ),
                      TextButton(
                        onPressed: widget.onGetStarted,
                        style: TextButton.styleFrom(
                          foregroundColor: AppTheme.goldLight,
                        ),
                        child: const Text('Create an account'),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Small shared bits ────────────────────────────────────────────────

  /// On the maroon surfaces the primary action inverts to maroon-on-gold so it
  /// still reads as the strongest element on the page.
  Widget _primaryButton({
    required String label,
    required VoidCallback onPressed,
    required bool onDark,
    IconData? icon,
    bool compact = false,
    bool stretch = false,
  }) {
    final style = ElevatedButton.styleFrom(
      backgroundColor: onDark ? AppTheme.gold : AppTheme.maroon,
      foregroundColor: onDark ? AppTheme.maroonDark : Colors.white,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 18 : 26,
        vertical: compact ? 12 : 16,
      ),
      textStyle: TextStyle(
        fontFamily: 'Inter',
        fontWeight: FontWeight.w700,
        fontSize: compact ? 13 : 14.5,
        letterSpacing: 0.3,
      ),
      elevation: onDark ? 0 : 2,
    );

    final child = icon == null
        ? Text(label)
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label),
              const SizedBox(width: 8),
              Icon(icon, size: 18),
            ],
          );

    final button = ElevatedButton(
      onPressed: onPressed,
      style: style,
      child: child,
    );
    return stretch ? SizedBox(width: double.infinity, child: button) : button;
  }

  Widget _circle(double size, Color color) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(shape: BoxShape.circle, color: color),
  );

  Widget _dot(Color color) => Container(
    width: 9,
    height: 9,
    decoration: BoxDecoration(shape: BoxShape.circle, color: color),
  );
}

// ─── Section heading ────────────────────────────────────────────────────
class _SectionHeading extends StatelessWidget {
  final String eyebrow;
  final String title;
  final String subtitle;

  const _SectionHeading({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 640),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 22,
                height: 3,
                decoration: BoxDecoration(
                  color: AppTheme.gold400,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                eyebrow.toUpperCase(),
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.maroon,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w800,
              color: AppTheme.slate900,
              height: 1.2,
              letterSpacing: -0.8,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 15,
              height: 1.6,
              color: AppTheme.slate500,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Feature card ───────────────────────────────────────────────────────
class _FeatureCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final String body;

  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  State<_FeatureCard> createState() => _FeatureCardState();
}

class _FeatureCardState extends State<_FeatureCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        transform: Matrix4.translationValues(0, _hover ? -4 : 0, 0),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _hover ? AppTheme.maroon200 : AppTheme.slate200,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: _hover ? 0.08 : 0.03),
              blurRadius: _hover ? 22 : 10,
              offset: Offset(0, _hover ? 10 : 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(13),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppTheme.maroon, AppTheme.maroonDark],
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.maroon.withValues(alpha: 0.25),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(widget.icon, color: Colors.white, size: 22),
            ),
            const SizedBox(height: 18),
            Text(
              widget.title,
              style: const TextStyle(
                fontSize: 16.5,
                fontWeight: FontWeight.w700,
                color: AppTheme.slate900,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.body,
              style: const TextStyle(
                fontSize: 13.5,
                height: 1.6,
                color: AppTheme.slate500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Role card ──────────────────────────────────────────────────────────
class _RoleCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String tagline;
  final List<String> points;

  const _RoleCard({
    required this.icon,
    required this.title,
    required this.tagline,
    required this.points,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppTheme.slate50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.slate200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppTheme.maroon, size: 28),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppTheme.slate900,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            tagline,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.maroon,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 16),
          for (final point in points)
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 6),
                    width: 5,
                    height: 5,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppTheme.gold400,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      point,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.45,
                        color: AppTheme.slate600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Step card ──────────────────────────────────────────────────────────
class _StepCard extends StatelessWidget {
  final String number;
  final String title;
  final String body;

  const _StepCard({
    required this.number,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.maroon100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            number,
            style: TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w800,
              height: 1,
              letterSpacing: -1.5,
              color: AppTheme.maroon.withValues(alpha: 0.18),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppTheme.slate900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: const TextStyle(
              fontSize: 13.5,
              height: 1.6,
              color: AppTheme.slate500,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Hero note chip ─────────────────────────────────────────────────────
class _HeroNote extends StatelessWidget {
  final IconData icon;
  final String label;

  const _HeroNote({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: AppTheme.goldLight),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Colors.white.withValues(alpha: 0.8),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Hero preview bits ──────────────────────────────────────────────────
class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color tint;

  const _MiniStat({
    required this.label,
    required this.value,
    required this.icon,
    required this.tint,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.slate200),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 16, color: tint),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.slate900,
                    height: 1.1,
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: AppTheme.slate500,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color tint;

  const _MiniRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.tint,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.slate200),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 15, color: tint),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.slate800,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: AppTheme.slate400,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
