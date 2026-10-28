import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../../theme/app_theme.dart';
import '../../widgets/shared_widgets.dart';
import 'landing_widgets.dart';

/// Public page shown before anyone signs in. Its job is to get students to
/// apply as Student Assistants: every "Apply" button opens registration
/// ([onGetStarted]); signing in ([onSignIn]) is the quieter second action.
///
/// It is a fixed advertisement: it can't know whether a hiring call is open, so
/// it never says so. It explains the way in (create an account, verify the
/// email, sign in, apply while a call is open) and leaves anything the program
/// decides (who may apply, pay, hours, deadlines) to the hiring call itself.
///
/// Sections: hero, quick facts, why join, how to apply, what to prepare, FAQ,
/// closing call to action, a short note for offices, footer. The layout
/// collapses from a multi-column desktop grid to a single column on phones;
/// the nav links turn into an end drawer below [_drawerBreakpoint].
class LandingScreen extends StatefulWidget {
  final VoidCallback onSignIn;
  final VoidCallback onGetStarted;

  /// Opens the Privacy Notice. The link is left out when this is null.
  final VoidCallback? onShowPrivacy;

  const LandingScreen({
    super.key,
    required this.onSignIn,
    required this.onGetStarted,
    this.onShowPrivacy,
  });

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen> {
  static const double _mobileBreakpoint = 900;
  static const double _drawerBreakpoint = 1100;
  static const double _wideBreakpoint = 1180;
  static const double _headerHeight = 76;
  static const double _maxContentWidth = 1140;

  /// The warm white the hero sits on.
  static const Color _warm = Color(0xFFFFFAF5);

  final _scroll = ScrollController();
  final _whyKey = GlobalKey();
  final _howKey = GlobalKey();
  final _faqKey = GlobalKey();
  final _staffKey = GlobalKey();

  /// Drives the header's change from see-through over the hero to a white bar.
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

  /// Scrolls so the section starts just under the header, not behind it.
  void _scrollTo(GlobalKey key) {
    final box = key.currentContext?.findRenderObject();
    if (box is! RenderBox || !_scroll.hasClients) return;
    final viewport = RenderAbstractViewport.of(box);
    final target =
        (viewport.getOffsetToReveal(box, 0).offset - _headerHeight + 8).clamp(
          0.0,
          _scroll.position.maxScrollExtent,
        );
    final reduced = MediaQuery.disableAnimationsOf(context);
    if (reduced) {
      _scroll.jumpTo(target);
    } else {
      _scroll.animateTo(
        target,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isMobile = width < _mobileBreakpoint;
    final isWide = width >= _wideBreakpoint;
    // The inline nav needs more room than the hero layout does, so it folds
    // into the drawer earlier than the page switches to its mobile layout.
    // Larger system text needs the room too, so it folds the nav as well.
    final largeText = MediaQuery.textScalerOf(context).scale(14) > 14 * 1.15;
    final useDrawerNav = width < _drawerBreakpoint || largeText;

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
                  _buildQuickFacts(isMobile),
                  _buildWhyJoin(isMobile, isWide),
                  _buildHowToApply(isMobile),
                  _buildPrepare(isMobile),
                  _buildFaq(isMobile),
                  _buildClosingCta(isMobile),
                  _buildForOffices(isMobile),
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

  // ─── Layout helpers ───────────────────────────────────────────────────
  Widget _band({
    Key? key,
    required Color color,
    required bool isMobile,
    required Widget child,
    double? verticalMobile,
    double? verticalDesktop,
  }) {
    return Container(
      key: key,
      width: double.infinity,
      color: color,
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 20 : 32,
        vertical: isMobile ? (verticalMobile ?? 56) : (verticalDesktop ?? 88),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxContentWidth),
          // Full width, so a short block sits at the left edge like the rest
          // instead of being centred.
          child: SizedBox(width: double.infinity, child: child),
        ),
      ),
    );
  }

  /// [children] in a grid of up to [maxColumns] equal columns.
  Widget _grid(
    List<Widget> children, {
    required int maxColumns,
    double minCard = 300,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 20.0;
        var columns = maxColumns;
        while (columns > 1 &&
            (constraints.maxWidth - gap * (columns - 1)) / columns < minCard) {
          columns--;
        }
        final cardWidth =
            (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final c in children) SizedBox(width: cardWidth, child: c),
          ],
        );
      },
    );
  }

  // ─── Header ───────────────────────────────────────────────────────────
  Widget _buildHeader(bool isMobile, bool useDrawerNav) {
    // The hero is light, so the header's text is dark from the start; only the
    // bar behind it changes once the page scrolls.
    const foreground = AppTheme.slate700;
    final width = MediaQuery.sizeOf(context).width;
    final showBrandSubtitle = width >= _wideBreakpoint;
    // On the narrowest phones the drawer carries Apply and Sign in; keeping the
    // buttons here would squeeze the wordmark down to a few pixels.
    final showInlineApply = width >= 400;
    // The sections keep their side padding outside the 1140 px column, so on
    // a wide window the header's content starts at the column's own edge.
    final edge = width >= _maxContentWidth + 64
        ? 0.0
        : (isMobile ? 20.0 : 32.0);

    return AnimatedContainer(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 220),
      height: _headerHeight,
      decoration: BoxDecoration(
        color: _scrolled ? Colors.white : Colors.transparent,
        border: Border(
          bottom: BorderSide(
            color: _scrolled ? AppTheme.slate200 : Colors.transparent,
          ),
        ),
        boxShadow: _scrolled
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _maxContentWidth),
            child: Padding(
              // The menu button's 24px icon sits centred in a 48px tap target,
              // so trimming 12px on that side lines the icon up with the page
              // edge the logo and hero copy use.
              padding: EdgeInsets.only(
                left: edge,
                right: (edge - (useDrawerNav ? 12 : 0)).clamp(0.0, edge),
              ),
              child: Row(
                children: [
                  const AppLogo(size: 40, shadow: []),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'SAIS',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                            color: AppTheme.slate900,
                          ),
                        ),
                        if (showBrandSubtitle)
                          const Text(
                            'Student Assistant Program · MarSU',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.3,
                              color: AppTheme.slate600,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (!useDrawerNav) ...[
                    _navLink('Why join', foreground, () => _scrollTo(_whyKey)),
                    _navLink(
                      'How to apply',
                      foreground,
                      () => _scrollTo(_howKey),
                    ),
                    _navLink('FAQ', foreground, () => _scrollTo(_faqKey)),
                    _navLink(
                      'For offices',
                      foreground,
                      () => _scrollTo(_staffKey),
                    ),
                    const SizedBox(width: 12),
                    TextButton(
                      onPressed: widget.onSignIn,
                      style: TextButton.styleFrom(foregroundColor: foreground),
                      child: const Text('Sign in'),
                    ),
                    const SizedBox(width: 8),
                    _applyButton('Apply now', compact: true),
                  ] else ...[
                    if (showInlineApply)
                      _applyButton('Apply now', compact: true),
                    Builder(
                      builder: (ctx) => IconButton(
                        onPressed: () => Scaffold.of(ctx).openEndDrawer(),
                        icon: const Icon(Icons.menu_rounded, color: foreground),
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
      Future.delayed(const Duration(milliseconds: 220), () {
        if (mounted) _scrollTo(key);
      });
    }

    Widget item(IconData icon, String label, GlobalKey key) => ListTile(
      leading: Icon(icon, color: AppTheme.slate600),
      title: Text(label),
      onTap: () => go(key),
    );

    return Drawer(
      backgroundColor: Colors.white,
      child: SafeArea(
        child: ListView(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: AppTheme.maroon50,
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
                        color: AppTheme.slate900,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            item(Icons.star_outline_rounded, 'Why join', _whyKey),
            item(Icons.route_outlined, 'How to apply', _howKey),
            item(Icons.help_outline_rounded, 'FAQ', _faqKey),
            item(Icons.business_outlined, 'For offices', _staffKey),
            const SizedBox(height: 16),
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
                      child: const Text('Apply now'),
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
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_warm, Colors.white],
        ),
      ),
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          Positioned(
            top: -120,
            right: -90,
            child: _blob(380, AppTheme.maroon.withValues(alpha: 0.06)),
          ),
          Positioned(
            top: 220,
            left: -110,
            child: _blob(260, AppTheme.gold300.withValues(alpha: 0.30)),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              isMobile ? 20 : 32,
              _headerHeight + (isMobile ? 28 : 56),
              isMobile ? 20 : 32,
              isMobile ? 40 : 56,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _maxContentWidth),
                child: isMobile
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _heroCopy(isMobile),
                          const SizedBox(height: 36),
                          const SampleApplicationCard(),
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(flex: 6, child: _heroCopy(isMobile)),
                          SizedBox(width: isWide ? 64 : 40),
                          const Expanded(
                            flex: 5,
                            child: SampleApplicationCard(),
                          ),
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
            color: Colors.white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppTheme.gold400.withValues(alpha: 0.7)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.school_outlined, size: 15, color: AppTheme.maroon),
              SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Marinduque State University · Student Assistant Program',
                  style: TextStyle(
                    color: AppTheme.maroonDark,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        Semantics(
          header: true,
          child: Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: 'Work on campus.\n'),
                TextSpan(
                  text: 'Earn while you learn.',
                  style: TextStyle(color: AppTheme.maroon),
                ),
              ],
            ),
            style: TextStyle(
              fontSize: isMobile ? 38 : 56,
              height: 1.08,
              fontWeight: FontWeight.w800,
              color: AppTheme.slate900,
              letterSpacing: isMobile ? -1.0 : -1.8,
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'Apply online to become a Student Assistant. Tell us your skills, '
          'upload your documents, and follow your application from one '
          'account, then get matched to a campus office that fits you.',
          style: TextStyle(
            fontSize: isMobile ? 15.5 : 17,
            height: 1.6,
            color: AppTheme.slate600,
          ),
        ),
        const SizedBox(height: 28),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _applyButton(
              'Apply now',
              large: true,
              icon: Icons.arrow_forward_rounded,
            ),
            OutlinedButton(
              onPressed: widget.onSignIn,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.slate800,
                side: const BorderSide(color: AppTheme.slate300, width: 1.5),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 17,
                ),
              ),
              child: const Text('I already have an account'),
            ),
          ],
        ),
        const SizedBox(height: 14),
        const Text(
          'Apply now opens registration: create your account, verify your '
          'email, then apply when a hiring call is open.',
          style: TextStyle(fontSize: 13, height: 1.5, color: AppTheme.slate600),
        ),
        const SizedBox(height: 24),
        const Wrap(
          spacing: 22,
          runSpacing: 10,
          children: [
            HeroNote(
              icon: Icons.smartphone_outlined,
              label: 'Works on your phone',
            ),
            HeroNote(
              icon: Icons.upload_file_outlined,
              label: 'Upload documents online',
            ),
            HeroNote(icon: Icons.timeline_outlined, label: 'Track your status'),
          ],
        ),
      ],
    );
  }

  // ─── Quick facts ──────────────────────────────────────────────────────
  Widget _buildQuickFacts(bool isMobile) {
    const items = [
      (Icons.devices_outlined, 'Apply online', 'From your phone or computer.'),
      (
        Icons.extension_outlined,
        'Matched by skills',
        'Placed in an office that fits you.',
      ),
      (
        Icons.payments_outlined,
        'Paid from verified hours',
        'Hourly wage payroll.',
      ),
    ];
    return _band(
      color: Colors.white,
      isMobile: isMobile,
      verticalMobile: 28,
      verticalDesktop: 36,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 20 : 32,
          vertical: isMobile ? 22 : 26,
        ),
        decoration: BoxDecoration(
          color: AppTheme.maroon50,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Wrap(
          spacing: 32,
          runSpacing: 20,
          alignment: WrapAlignment.spaceBetween,
          children: [
            for (final item in items)
              SizedBox(
                width: isMobile ? double.infinity : 320,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    ExcludeSemantics(
                      child: Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(item.$1, color: AppTheme.maroon, size: 24),
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
                              fontSize: 15.5,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.slate900,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            item.$3,
                            style: const TextStyle(
                              fontSize: 13.5,
                              height: 1.4,
                              color: AppTheme.slate600,
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
    );
  }

  // ─── Why join ─────────────────────────────────────────────────────────
  Widget _buildWhyJoin(bool isMobile, bool isWide) {
    const benefits = [
      (
        Icons.payments_outlined,
        'Earn while you study',
        'Student Assistants are paid through the Hourly Wage Payroll, worked '
            'out from the hours you actually work.',
      ),
      (
        Icons.business_center_outlined,
        'Real office experience',
        'Work in a campus office, learn on the job, and build experience you '
            'can put on your resume.',
      ),
      (
        Icons.extension_outlined,
        'Matched to your skills',
        'List your skills when you apply. The Head takes them into account '
            'when placing you in an office.',
      ),
      (
        Icons.qr_code_scanner_rounded,
        'Simple, honest attendance',
        'Clock in and out by scanning a QR code. Your verified hours are the '
            'ones that count.',
      ),
      (
        Icons.description_outlined,
        'Paperwork done for you',
        'Your contract of appointment, endorsement letter and monthly DTR are '
            'filled into the university\'s own templates.',
      ),
      (
        Icons.autorenew_rounded,
        'A way to stay on',
        'Your supervisor evaluates you each term, and good performance counts '
            'when the Head decides on rehiring.',
      ),
    ];

    return _band(
      key: _whyKey,
      color: AppTheme.slate50,
      isMobile: isMobile,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const LandingSectionHeading(
            eyebrow: 'Why join',
            title: 'Why be a Student Assistant?',
            subtitle:
                'Get paid, gain experience in a real office, and let the '
                'system handle the paperwork.',
          ),
          const SizedBox(height: 40),
          _grid([
            for (final b in benefits)
              BenefitCard(icon: b.$1, title: b.$2, body: b.$3),
          ], maxColumns: 3),
        ],
      ),
    );
  }

  // ─── How to apply ─────────────────────────────────────────────────────
  Widget _buildHowToApply(bool isMobile) {
    const steps = [
      (
        '01',
        'Create your account',
        'Register with your Gmail or MarSU email, then open the verification '
            'link we send you.',
      ),
      (
        '02',
        'Apply when hiring is open',
        'Sign in and open the Apply page. When the Head opens a hiring call, '
            'add your skills and upload the documents it asks for.',
      ),
      (
        '03',
        'Get screened',
        'The Head reviews applications and picks who to interview. Your Apply '
            'page shows where yours stands.',
      ),
      (
        '04',
        'Start working',
        'If you are approved you get a Student Assistant ID and an office '
            'placement, then your contract.',
      ),
    ];

    return _band(
      key: _howKey,
      color: Colors.white,
      isMobile: isMobile,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const LandingSectionHeading(
            eyebrow: 'How to apply',
            title: 'Four steps from sign-up to your first shift',
            subtitle:
                'You apply once, through the hiring call, and you submit '
                'everything online.',
          ),
          const SizedBox(height: 40),
          _grid(
            [
              for (final s in steps)
                StepCard(number: s.$1, title: s.$2, body: s.$3),
            ],
            maxColumns: 4,
            minCard: 240,
          ),
          const SizedBox(height: 32),
          Wrap(
            spacing: 16,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _applyButton(
                'Apply now',
                large: true,
                icon: Icons.arrow_forward_rounded,
              ),
              const Text(
                'Opens registration.',
                style: TextStyle(fontSize: 13.5, color: AppTheme.slate600),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── What to prepare ──────────────────────────────────────────────────
  Widget _buildPrepare(bool isMobile) {
    const items = [
      (
        Icons.mark_email_read_outlined,
        'An email you can open',
        'A Gmail or @marsu.edu.ph address. You must open the verification link '
            'before you can sign in.',
      ),
      (
        Icons.folder_open_outlined,
        'Your documents',
        'The hiring call lists what to upload, one file for each requirement. '
            'PDF, Word, JPG or PNG, up to 10 MB each (a call can limit the '
            'types for a requirement).',
      ),
      (
        Icons.extension_outlined,
        'Your skills',
        'Choose the skills you have. The Head matches them to what offices '
            'need.',
      ),
      (
        Icons.badge_outlined,
        'Your details',
        'Your name, program and year level, and your Student ID if you have it '
            'at hand.',
      ),
    ];

    return _band(
      color: AppTheme.maroon50,
      isMobile: isMobile,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final heading = const LandingSectionHeading(
            eyebrow: 'Before you start',
            title: 'What to have ready',
            subtitle:
                'A few things make applying quick. The hiring call tells you '
                'exactly what it needs.',
          );
          final list = Column(
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0) const SizedBox(height: 20),
                PrepareItem(
                  icon: items[i].$1,
                  title: items[i].$2,
                  body: items[i].$3,
                ),
              ],
            ],
          );
          if (constraints.maxWidth < 800) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [heading, const SizedBox(height: 32), list],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 4, child: heading),
              const SizedBox(width: 56),
              Expanded(flex: 5, child: list),
            ],
          );
        },
      ),
    );
  }

  // ─── FAQ ──────────────────────────────────────────────────────────────
  Widget _buildFaq(bool isMobile) {
    final items = <Widget>[
      const FaqItem(
        question: 'When does hiring open?',
        answer:
            'The Head of Student Assistantship opens a hiring call when the '
            'program needs new Student Assistants. Create your account now so '
            'you are ready: the Apply page shows the call, its deadline and '
            'what to upload as soon as it is open.',
      ),
      const FaqItem(
        question: 'Who can apply?',
        answer:
            'You can create an account with a Gmail or a MarSU email, and each '
            'hiring call says who it is for. Read the call on the Apply page; '
            'the Head screens every application.',
      ),
      const FaqItem(
        question: 'Can I choose the office I work in?',
        answer:
            'You apply to become a Student Assistant, not to one office. If '
            'you are approved, the Head places you in an office, taking your '
            'skills into account.',
      ),
      const FaqItem(
        question: 'What if I uploaded the wrong file?',
        answer:
            'The Head can send your application back with the reason. Your '
            'answers and files are kept, so you replace what needs fixing and '
            'apply again while the call is still open.',
      ),
      const FaqItem(
        question: 'How will I know where my application stands?',
        answer:
            'Your Apply page shows where it stands, and you get a notification '
            'when you are picked for screening and when a decision is made.',
      ),
      FaqItem(
        question: 'Is my information private?',
        answer:
            'Your documents are kept in private storage, not on a public page. '
            'The Privacy Notice explains what we collect, why, and who can '
            'see it.',
        linkLabel: widget.onShowPrivacy == null
            ? null
            : 'Read the Privacy Notice',
        onLink: widget.onShowPrivacy,
      ),
    ];

    return _band(
      key: _faqKey,
      color: Colors.white,
      isMobile: isMobile,
      child: Column(
        children: [
          const LandingSectionHeading(
            eyebrow: 'FAQ',
            title: 'Questions students ask',
            centered: true,
          ),
          const SizedBox(height: 36),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) const SizedBox(height: 12),
                  items[i],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Closing call to action ───────────────────────────────────────────
  Widget _buildClosingCta(bool isMobile) {
    return _band(
      color: Colors.white,
      isMobile: isMobile,
      verticalMobile: 8,
      verticalDesktop: 16,
      child: Container(
        padding: EdgeInsets.all(isMobile ? 28 : 52),
        decoration: BoxDecoration(
          color: AppTheme.maroon50,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: AppTheme.maroon100),
        ),
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
                  Container(
                    width: 34,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppTheme.gold400,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Semantics(
                    header: true,
                    child: Text(
                      'Ready to apply?',
                      style: TextStyle(
                        fontSize: isMobile ? 28 : 36,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.slate900,
                        height: 1.15,
                        letterSpacing: -0.9,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Create your account today, so you are ready the moment a '
                    'hiring call opens.',
                    style: TextStyle(
                      fontSize: 15.5,
                      height: 1.6,
                      color: AppTheme.slate600,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: isMobile ? 0 : 40, height: isMobile ? 24 : 0),
            Flexible(
              flex: isMobile ? 0 : 2,
              fit: FlexFit.loose,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _applyButton(
                    'Create my account',
                    large: true,
                    stretch: true,
                    icon: Icons.arrow_forward_rounded,
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: widget.onSignIn,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.slate800,
                      side: const BorderSide(
                        color: AppTheme.slate300,
                        width: 1.5,
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 17),
                    ),
                    child: const Text('Sign in'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── For offices ──────────────────────────────────────────────────────
  Widget _buildForOffices(bool isMobile) {
    const chips = [
      (Icons.how_to_reg_outlined, 'Applications & screening'),
      (Icons.account_balance_outlined, 'Office placement'),
      (Icons.qr_code_scanner_rounded, 'QR attendance'),
      (Icons.event_note_outlined, 'DTR & reports'),
      (Icons.fact_check_outlined, 'Evaluation'),
      (Icons.autorenew_rounded, 'Rehiring'),
      (Icons.payments_outlined, 'Payroll'),
    ];
    return _band(
      key: _staffKey,
      color: AppTheme.slate50,
      isMobile: isMobile,
      verticalMobile: 44,
      verticalDesktop: 64,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const LandingSectionHeading(
            eyebrow: 'For offices & staff',
            title: 'Running the program? SAIS handles the rest.',
            subtitle:
                'Administrators, the Head and supervisors work from one record, '
                'from the first application to the last payroll.',
          ),
          const SizedBox(height: 28),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final c in chips) StaffChip(icon: c.$1, label: c.$2),
            ],
          ),
          const SizedBox(height: 28),
          OutlinedButton.icon(
            onPressed: widget.onSignIn,
            icon: const Icon(Icons.login_rounded, size: 18),
            label: const Text('Staff sign in'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.maroon,
              side: const BorderSide(color: AppTheme.maroon200, width: 1.5),
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
            ),
          ),
        ],
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
                          'Student Assistant Information System · '
                          'Marinduque State University',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
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
                      color: Colors.white.withValues(alpha: 0.65),
                      fontSize: 12,
                    ),
                  ),
                  Wrap(
                    children: [
                      TextButton(
                        onPressed: widget.onGetStarted,
                        style: TextButton.styleFrom(
                          foregroundColor: AppTheme.goldLight,
                        ),
                        child: const Text('Apply now'),
                      ),
                      TextButton(
                        onPressed: widget.onSignIn,
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white.withValues(alpha: 0.8),
                        ),
                        child: const Text('Sign in'),
                      ),
                      if (widget.onShowPrivacy != null)
                        TextButton(
                          onPressed: widget.onShowPrivacy,
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white.withValues(
                              alpha: 0.8,
                            ),
                          ),
                          child: const Text('Privacy Notice'),
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

  /// Every "Apply" on the page goes to registration.
  Widget _applyButton(
    String label, {
    bool compact = false,
    bool large = false,
    bool stretch = false,
    IconData? icon,
  }) {
    final style = ElevatedButton.styleFrom(
      backgroundColor: AppTheme.maroon,
      foregroundColor: Colors.white,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 18 : (large ? 28 : 24),
        vertical: compact ? 12 : (large ? 17 : 15),
      ),
      textStyle: TextStyle(
        fontFamily: 'Inter',
        fontWeight: FontWeight.w700,
        fontSize: compact ? 13.5 : 15,
        letterSpacing: 0.2,
      ),
      elevation: 2,
      shadowColor: AppTheme.maroon.withValues(alpha: 0.35),
    );
    final child = icon == null
        ? Text(label)
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: Text(label, textAlign: TextAlign.center)),
              const SizedBox(width: 8),
              Icon(icon, size: 18),
            ],
          );
    final button = ElevatedButton(
      onPressed: widget.onGetStarted,
      style: style,
      child: child,
    );
    return stretch ? SizedBox(width: double.infinity, child: button) : button;
  }

  Widget _blob(double size, Color color) => ExcludeSemantics(
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    ),
  );
}
