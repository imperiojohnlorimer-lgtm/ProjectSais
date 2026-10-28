import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
/// The look comes from the campus: photos of the main building, MarSU maroon,
/// the building's warm cream, serif headings (see [LandingColors]).
///
/// Sections: photo hero with a facts card over its edge, why join (beside a
/// campus photo), how to apply (beside a sample ID card), what to prepare, FAQ,
/// a closing call to action over a photo, a short note for offices, footer.
/// The nav links turn into an end drawer below [_drawerBreakpoint].
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

  static const _heroPhoto = 'assets/images/marsu_hero.jpg';
  static const _campusPhoto = 'assets/images/marsu_campus.jpg';

  final _scroll = ScrollController();
  final _whyKey = GlobalKey();
  final _howKey = GlobalKey();
  final _faqKey = GlobalKey();
  final _staffKey = GlobalKey();

  /// Drives the header's change from see-through over the photo to a bar.
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
    if (MediaQuery.disableAnimationsOf(context)) {
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
    // Larger system text needs room too, so it folds the nav.
    final largeText = MediaQuery.textScalerOf(context).scale(14) > 14 * 1.15;
    // The inline nav needs more room than the hero layout does, so it folds
    // into the drawer earlier than the page switches to its mobile layout.
    final useDrawerNav = width < _drawerBreakpoint || largeText;

    return Scaffold(
      backgroundColor: LandingColors.paper,
      endDrawer: useDrawerNav ? _buildDrawer() : null,
      body: Stack(
        children: [
          Positioned.fill(
            child: SingleChildScrollView(
              controller: _scroll,
              physics: const ClampingScrollPhysics(),
              child: Column(
                children: [
                  _buildHero(isMobile),
                  _buildWhyJoin(isMobile),
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
        vertical: isMobile ? (verticalMobile ?? 64) : (verticalDesktop ?? 96),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxContentWidth),
          // Full width, so a short block sits at the left edge like the rest.
          child: SizedBox(width: double.infinity, child: child),
        ),
      ),
    );
  }

  /// [children] in a grid of up to [maxColumns] equal columns.
  Widget _grid(
    List<Widget> children, {
    required int maxColumns,
    double minCard = 260,
    double gap = 24,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
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

  Widget _photo(String asset, {Alignment alignment = Alignment.center}) {
    return ExcludeSemantics(
      child: Image.asset(
        asset,
        fit: BoxFit.cover,
        alignment: alignment,
        width: double.infinity,
        height: double.infinity,
        // A soft maroon field while it decodes, never a white flash.
        frameBuilder: (context, child, frame, sync) => frame == null && !sync
            ? Container(color: LandingColors.maroonDeep)
            : child,
        errorBuilder: (_, _, _) => Container(color: LandingColors.maroonDeep),
      ),
    );
  }

  // ─── Header ───────────────────────────────────────────────────────────
  Widget _buildHeader(bool isMobile, bool useDrawerNav) {
    final width = MediaQuery.sizeOf(context).width;
    final showBrandSubtitle = width >= _wideBreakpoint;
    // On the narrowest phones the drawer carries Apply and Sign in.
    final showInlineApply = width >= 400;
    // The sections keep their side padding outside the 1140 px column, so on
    // a wide window the header's content starts at the column's own edge.
    final edge = width >= _maxContentWidth + 64
        ? 0.0
        : (isMobile ? 20.0 : 32.0);
    // Over the photo the header is see-through with white text; once the page
    // scrolls it is a white bar with ink text. Both switch in the same frame,
    // so the text never sits on a background of nearly its own colour.
    final foreground = _scrolled ? LandingColors.ink : Colors.white;

    return Container(
      height: _headerHeight,
      decoration: BoxDecoration(
        color: _scrolled ? Colors.white : null,
        // Over the photo a maroon shade keeps the white text readable even
        // where the header crosses bright sky.
        gradient: _scrolled
            ? null
            : LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  LandingColors.maroonDeep.withValues(alpha: 0.72),
                  LandingColors.maroonDeep.withValues(alpha: 0.55),
                ],
              ),
        border: Border(
          bottom: BorderSide(
            color: _scrolled ? LandingColors.rule : Colors.transparent,
          ),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _maxContentWidth),
            child: Padding(
              // The menu button's icon sits centred in a 48px tap target, so
              // trimming 12px on that side lines it up with the page edge.
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
                        Text(
                          'SAIS',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: landingSerif,
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            color: foreground,
                          ),
                        ),
                        if (showBrandSubtitle)
                          Text(
                            'Student Assistant Program · MarSU',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: foreground.withValues(alpha: 0.8),
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
                    _applyButton(
                      'Apply now',
                      compact: true,
                      onDark: !_scrolled,
                    ),
                  ] else ...[
                    if (showInlineApply)
                      _applyButton(
                        'Apply now',
                        compact: true,
                        onDark: !_scrolled,
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
      Future.delayed(const Duration(milliseconds: 220), () {
        if (mounted) _scrollTo(key);
      });
    }

    Widget item(IconData icon, String label, GlobalKey key) => ListTile(
      leading: Icon(icon, color: LandingColors.maroon),
      title: Text(
        label,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          color: LandingColors.ink,
        ),
      ),
      onTap: () => go(key),
    );

    return Drawer(
      backgroundColor: LandingColors.paper,
      child: SafeArea(
        child: ListView(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              color: LandingColors.maroonDeep,
              child: const Row(
                children: [
                  AppLogo(size: 44, shadow: []),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'SAIS',
                      style: TextStyle(
                        fontFamily: landingSerif,
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
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
                      style: _buttonStyle(onDark: false),
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
                      style: _outlineStyle(onDark: false),
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
  Widget _buildHero(bool isMobile) {
    final photo = Stack(
      children: [
        Positioned.fill(
          child: _photo(
            _heroPhoto,
            // The statue and the building's centre stay in view on phones.
            alignment: const Alignment(0.05, 0.1),
          ),
        ),
        // Maroon from the left (from the bottom on phones) so the text reads,
        // fading out to let the building show.
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: isMobile ? Alignment.bottomCenter : Alignment.centerLeft,
                end: isMobile ? Alignment.topCenter : Alignment.centerRight,
                colors: [
                  LandingColors.maroonDeep.withValues(alpha: 0.96),
                  LandingColors.maroonDeep.withValues(alpha: 0.88),
                  LandingColors.maroonDeep.withValues(alpha: 0.35),
                  LandingColors.maroonDeep.withValues(alpha: 0.05),
                ],
                stops: isMobile
                    ? const [0, 0.55, 0.85, 1]
                    : const [0, 0.38, 0.68, 1],
              ),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            isMobile ? 20 : 32,
            _headerHeight + (isMobile ? 80 : 72),
            isMobile ? 20 : 32,
            isMobile ? 48 : 132,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _maxContentWidth),
              child: Align(
                alignment: Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: _heroCopy(isMobile),
                ),
              ),
            ),
          ),
        ),
      ],
    );

    // On phones the card is three rows tall, too tall to lay over the text:
    // it simply follows the photo.
    if (isMobile) {
      return Column(
        children: [
          photo,
          Container(
            width: double.infinity,
            color: LandingColors.paper,
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
            child: _factsCard(isMobile),
          ),
        ],
      );
    }

    // On wider screens the facts card sits half over the photo's bottom edge.
    const overlap = 56.0;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Column(
          children: [
            photo,
            Container(height: overlap, color: LandingColors.paper),
          ],
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: isMobile ? 20 : 32),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _maxContentWidth),
                child: _factsCard(isMobile),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _heroCopy(bool isMobile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Container(width: 28, height: 2, color: LandingColors.brass),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                'MARINDUQUE STATE UNIVERSITY · STUDENT ASSISTANT PROGRAM',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.6,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        Semantics(
          header: true,
          child: Text(
            'Work on campus.\nEarn while you learn.',
            style: TextStyle(
              fontFamily: landingSerif,
              fontSize: isMobile ? 36 : 58,
              height: 1.06,
              fontWeight: FontWeight.w600,
              color: Colors.white,
              letterSpacing: isMobile ? -0.6 : -1.0,
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Apply online to become a Student Assistant. Tell us your skills, '
          'upload your documents, and follow your application from one '
          'account, then get matched to a campus office that fits you.',
          style: TextStyle(
            fontSize: isMobile ? 16 : 17,
            height: 1.65,
            color: Colors.white.withValues(alpha: 0.92),
          ),
        ),
        const SizedBox(height: 30),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _applyButton(
              'Apply now',
              large: true,
              icon: Icons.arrow_forward_rounded,
              onDark: true,
            ),
            OutlinedButton(
              onPressed: widget.onSignIn,
              style: _outlineStyle(onDark: true),
              child: const Text('I already have an account'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'Apply now opens registration: create your account, verify your '
          'email, then apply when a hiring call is open.',
          style: TextStyle(
            fontSize: 13.5,
            height: 1.5,
            color: Colors.white.withValues(alpha: 0.82),
          ),
        ),
        const SizedBox(height: 22),
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

  Widget _factsCard(bool isMobile) {
    const facts = [
      (Icons.devices_outlined, 'Apply online', 'From your phone or computer.'),
      (
        Icons.extension_outlined,
        'Matched by skills',
        'Placed in an office that fits you.',
      ),
      (
        Icons.payments_outlined,
        'Paid from verified hours',
        'Through the Hourly Wage Payroll.',
      ),
    ];
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 20 : 32,
        vertical: isMobile ? 20 : 26,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: LandingColors.rule),
        boxShadow: [
          BoxShadow(
            color: LandingColors.maroonDeep.withValues(alpha: 0.07),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: _grid(
        [for (final f in facts) FactItem(icon: f.$1, title: f.$2, body: f.$3)],
        maxColumns: 3,
        minCard: 230,
        gap: 28,
      ),
    );
  }

  // ─── Why join ─────────────────────────────────────────────────────────
  Widget _buildWhyJoin(bool isMobile) {
    const benefits = [
      (
        '01',
        'Earn while you study',
        'Student Assistants are paid through the Hourly Wage Payroll, worked '
            'out from the hours you actually work.',
      ),
      (
        '02',
        'Real office experience',
        'Work in a campus office, learn on the job, and build experience you '
            'can put on your resume.',
      ),
      (
        '03',
        'Matched to your skills',
        'List your skills when you apply. The Head takes them into account '
            'when placing you in an office.',
      ),
      (
        '04',
        'Simple, honest attendance',
        'Clock in and out by scanning a QR code. Your verified hours are the '
            'ones that count.',
      ),
      (
        '05',
        'Paperwork done for you',
        'Your Contract of Appointment, Endorsement Letter and monthly DTR are '
            'filled into the university\'s own templates.',
      ),
      (
        '06',
        'A way to stay on',
        'Your supervisor evaluates you each term, and good performance counts '
            'when the Head decides on rehiring.',
      ),
    ];

    final list = _grid(
      [
        for (final b in benefits)
          LedgerItem(number: b.$1, title: b.$2, body: b.$3),
      ],
      maxColumns: 2,
      minCard: 250,
      gap: 32,
    );

    return _band(
      key: _whyKey,
      color: LandingColors.paper,
      isMobile: isMobile,
      verticalDesktop: 80,
      child: LayoutBuilder(
        builder: (context, constraints) {
          const heading = LandingHeading(
            label: 'Why join',
            title: 'Why be a Student Assistant?',
            subtitle:
                'Get paid, gain experience in a real office, and let the '
                'system handle the paperwork.',
          );
          final photo = ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: _photo(_campusPhoto, alignment: const Alignment(0.55, 0)),
          );
          if (constraints.maxWidth < 860) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                heading,
                const SizedBox(height: 32),
                SizedBox(height: 220, child: photo),
                const SizedBox(height: 36),
                list,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    heading,
                    const SizedBox(height: 36),
                    SizedBox(height: 280, child: photo),
                  ],
                ),
              ),
              const SizedBox(width: 64),
              Expanded(
                flex: 6,
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: list,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ─── How to apply ─────────────────────────────────────────────────────
  Widget _buildHowToApply(bool isMobile) {
    const steps = [
      (
        '1',
        'Create your account',
        'Register with your Gmail or MarSU email, then open the verification '
            'link we send you.',
      ),
      (
        '2',
        'Apply when hiring is open',
        'Sign in and open the Apply page. When the Head opens a hiring call, '
            'add your skills and upload the documents it asks for.',
      ),
      (
        '3',
        'Get screened',
        'The Head reviews applications and picks who to interview. Your Apply '
            'page shows where yours stands.',
      ),
      (
        '4',
        'Start working',
        'If you are approved you get a Student Assistant ID and an office '
            'placement, then your contract.',
      ),
    ];

    final stepList = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < steps.length; i++)
          StepItem(
            number: steps[i].$1,
            title: steps[i].$2,
            body: steps[i].$3,
            last: i == steps.length - 1,
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
              onDark: false,
            ),
            const Text(
              'Opens registration.',
              style: TextStyle(fontSize: 14, color: LandingColors.muted),
            ),
          ],
        ),
      ],
    );

    return _band(
      key: _howKey,
      color: Colors.white,
      isMobile: isMobile,
      child: LayoutBuilder(
        builder: (context, constraints) {
          const heading = LandingHeading(
            label: 'How to apply',
            title: 'Four steps from sign-up to your first shift',
            subtitle:
                'You apply once, through the hiring call, and you submit '
                'everything online.',
          );
          if (constraints.maxWidth < 860) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                heading,
                const SizedBox(height: 40),
                stepList,
                const SizedBox(height: 48),
                const IdCard(),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 6,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [heading, const SizedBox(height: 44), stepList],
                ),
              ),
              const SizedBox(width: 72),
              const Expanded(
                flex: 5,
                child: Padding(padding: EdgeInsets.zero, child: IdCard()),
              ),
            ],
          );
        },
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
      color: LandingColors.sand,
      isMobile: isMobile,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const LandingHeading(
            label: 'Before you start',
            title: 'What to have ready',
            subtitle:
                'A few things make applying quick. The hiring call tells you '
                'exactly what it needs.',
          ),
          const SizedBox(height: 40),
          _grid(
            [
              for (final i in items)
                // Even bottoms across a row of four.
                ConstrainedBox(
                  constraints: BoxConstraints(minHeight: isMobile ? 0 : 236),
                  child: PrepareItem(icon: i.$1, title: i.$2, body: i.$3),
                ),
            ],
            maxColumns: 4,
            minCard: 230,
          ),
        ],
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
      color: LandingColors.paper,
      isMobile: isMobile,
      child: LayoutBuilder(
        builder: (context, constraints) {
          const heading = LandingHeading(
            label: 'FAQ',
            title: 'Questions students ask',
            subtitle:
                'Still unsure? The hiring call on the Apply page has '
                'the details for each round.',
          );
          final list = Container(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: LandingColors.rule)),
            ),
            child: Column(children: items),
          );
          if (constraints.maxWidth < 860) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [heading, const SizedBox(height: 32), list],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(flex: 4, child: heading),
              const SizedBox(width: 64),
              Expanded(flex: 6, child: list),
            ],
          );
        },
      ),
    );
  }

  // ─── Closing call to action ───────────────────────────────────────────
  Widget _buildClosingCta(bool isMobile) {
    return SizedBox(
      width: double.infinity,
      child: Stack(
        children: [
          Positioned.fill(
            child: _photo(_campusPhoto, alignment: const Alignment(0, -0.2)),
          ),
          Positioned.fill(
            child: ColoredBox(
              color: LandingColors.maroonDeep.withValues(alpha: 0.88),
            ),
          ),
          _band(
            color: Colors.transparent,
            isMobile: isMobile,
            verticalMobile: 64,
            verticalDesktop: 64,
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
                      Semantics(
                        header: true,
                        child: Text(
                          'Ready to apply?',
                          style: TextStyle(
                            fontFamily: landingSerif,
                            fontSize: isMobile ? 34 : 44,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                            height: 1.1,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Create your account today, so you are ready the '
                        'moment a hiring call opens.',
                        style: TextStyle(
                          fontSize: 16.5,
                          height: 1.6,
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: isMobile ? 0 : 48, height: isMobile ? 28 : 0),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: isMobile ? double.infinity : 300,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _applyButton(
                        'Create my account',
                        large: true,
                        stretch: true,
                        icon: Icons.arrow_forward_rounded,
                        onDark: true,
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: widget.onSignIn,
                        style: _outlineStyle(onDark: true),
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
      color: LandingColors.paper,
      isMobile: isMobile,
      verticalMobile: 56,
      verticalDesktop: 72,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const LandingHeading(
            label: 'For offices & staff',
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
            style: _outlineStyle(onDark: false),
          ),
        ],
      ),
    );
  }

  // ─── Footer ───────────────────────────────────────────────────────────
  Widget _buildFooter(bool isMobile) {
    return Container(
      width: double.infinity,
      color: LandingColors.maroonDeep,
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
                            fontFamily: landingSerif,
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          'Student Assistant Information System · '
                          'Marinduque State University',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.75),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              Divider(color: Colors.white.withValues(alpha: 0.15), height: 1),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      '© ${DateTime.now().year} SAIS. All rights reserved.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 12,
                      ),
                    ),
                    Wrap(
                      children: [
                        TextButton(
                          onPressed: widget.onGetStarted,
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Apply now'),
                        ),
                        TextButton(
                          onPressed: widget.onSignIn,
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white.withValues(
                              alpha: 0.85,
                            ),
                          ),
                          child: const Text('Sign in'),
                        ),
                        if (widget.onShowPrivacy != null)
                          TextButton(
                            onPressed: widget.onShowPrivacy,
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.white.withValues(
                                alpha: 0.85,
                              ),
                            ),
                            child: const Text('Privacy Notice'),
                          ),
                      ],
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

  // ─── Buttons ──────────────────────────────────────────────────────────

  /// On the photo and dark bands the button is white with maroon text; on
  /// light backgrounds it is maroon with white text.
  ButtonStyle _buttonStyle({
    required bool onDark,
    bool large = false,
    bool compact = false,
  }) {
    final background = onDark ? Colors.white : LandingColors.maroon;
    final foreground = onDark ? LandingColors.maroon : Colors.white;
    return ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.hovered)
            ? Color.lerp(
                background,
                onDark ? LandingColors.sand : Colors.black,
                0.12,
              )
            : background,
      ),
      foregroundColor: WidgetStatePropertyAll(foreground),
      overlayColor: WidgetStatePropertyAll(foreground.withValues(alpha: 0.08)),
      elevation: const WidgetStatePropertyAll(0),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      padding: WidgetStatePropertyAll(
        EdgeInsets.symmetric(
          horizontal: compact ? 18 : (large ? 28 : 24),
          vertical: compact ? 12 : (large ? 18 : 15),
        ),
      ),
      textStyle: WidgetStatePropertyAll(
        TextStyle(
          fontFamily: 'Inter',
          fontWeight: FontWeight.w700,
          fontSize: compact ? 13.5 : 15.5,
        ),
      ),
    );
  }

  ButtonStyle _outlineStyle({required bool onDark}) {
    return OutlinedButton.styleFrom(
      foregroundColor: onDark ? Colors.white : LandingColors.maroon,
      side: BorderSide(
        color: onDark
            ? Colors.white.withValues(alpha: 0.65)
            : LandingColors.maroon.withValues(alpha: 0.5),
        width: 1.5,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 17),
      textStyle: const TextStyle(
        fontFamily: 'Inter',
        fontWeight: FontWeight.w600,
        fontSize: 15,
      ),
    );
  }

  /// Every "Apply" on the page goes to registration.
  Widget _applyButton(
    String label, {
    bool compact = false,
    bool large = false,
    bool stretch = false,
    bool onDark = false,
    IconData? icon,
  }) {
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
      style: _buttonStyle(onDark: onDark, large: large, compact: compact),
      child: child,
    );
    return stretch ? SizedBox(width: double.infinity, child: button) : button;
  }
}
