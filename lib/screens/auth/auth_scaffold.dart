import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../widgets/shared_widgets.dart';

/// The icon column shared by the branding logo and the point tiles below it,
/// so every row in the panel starts on the same left edge and every text
/// block begins at the same offset from it.
const double _iconColumn = 46;
const double _iconGap = 16;

/// One selling point in the auth branding panel.
class AuthBrandPoint {
  final IconData icon;
  final String title;
  final String subtitle;

  const AuthBrandPoint(this.icon, this.title, this.subtitle);
}

/// Shared chrome for the login and register screens.
///
/// Desktop puts the form beside a maroon branding panel that echoes the
/// landing page hero; phones get the same gradient as a hero with the form
/// riding on a white sheet over it. Screens supply only [children] — their
/// own fields, buttons, and footer link.
class AuthScaffold extends StatelessWidget {
  static const double _mobileBreakpoint = 900;

  final String title;
  final String subtitle;

  /// The form itself: fields, submit button, footer link.
  final List<Widget> children;

  /// Caps the form column. Wider for multi-column forms like register.
  final double maxFormWidth;

  /// When provided, a back control returns the visitor to the landing page.
  final VoidCallback? onBack;

  final List<AuthBrandPoint> brandPoints;

  const AuthScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.children,
    required this.brandPoints,
    this.maxFormWidth = 440,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isMobile = constraints.maxWidth < _mobileBreakpoint;
          return SizedBox(
            height: double.infinity,
            width: double.infinity,
            child: Stack(
              children: [
                Positioned.fill(
                  child: isMobile ? _mobileLayout() : _desktopLayout(),
                ),
                if (onBack != null)
                  Positioned(
                    top: 0,
                    left: 0,
                    child: SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: IconButton(
                          onPressed: onBack,
                          tooltip: 'Back to home',
                          icon: Icon(
                            Icons.arrow_back_rounded,
                            // Phones open on the maroon hero, desktop on the
                            // white form column.
                            color: isMobile ? Colors.white : AppTheme.slate600,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ─── Desktop / tablet: form beside the branding panel ─────────────────
  Widget _desktopLayout() {
    return Row(
      children: [
        Expanded(flex: 6, child: _desktopForm()),
        Expanded(flex: 5, child: _brandingPanel()),
      ],
    );
  }

  Widget _desktopForm() {
    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
          physics: const BouncingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxFormWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Column(
                    children: [
                      const AppLogo(size: 72),
                      const SizedBox(height: 22),
                      _headerText(),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                ...children,
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Mobile: gradient hero + overlapping sheet ────────────────────────
  Widget _mobileLayout() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        children: [
          _mobileHero(),
          Transform.translate(
            offset: const Offset(0, -28),
            child: Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
              ),
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 24),
                      decoration: BoxDecoration(
                        color: AppTheme.slate200,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  _headerText(mobile: true),
                  const SizedBox(height: 28),
                  ...children,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _mobileHero() {
    return Container(
      width: double.infinity,
      clipBehavior: Clip.hardEdge,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.maroon, AppTheme.maroonDark],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 60),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 16),
              const AppLogo(size: 64),
              const SizedBox(height: 14),
              const Text(
                'SAIS',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.goldLight,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Student Assistant Information System',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  color: Color(0xFFFFD88A),
                  height: 1.3,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Branding panel (desktop only) ────────────────────────────────────
  Widget _brandingPanel() {
    return Container(
      clipBehavior: Clip.hardEdge,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.maroon, AppTheme.maroonDark],
        ),
      ),
      // Deliberately undecorated. Circles at low opacity showed a hard rim,
      // and softening them into radial glows only traded that for an uneven
      // haze; a plain gradient is the one version that reads as clean. The
      // gold accents are the rule under the wordmark and the icon tiles.
      child: Stack(
        fit: StackFit.expand,
        children: [
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Laptop-height browser windows leave little room once the
                // brand block and three tiles are stacked, so tighten up
                // rather than letting the column overflow.
                final compact = constraints.maxHeight < 680;
                final gap = compact ? 20.0 : 26.0;

                return SingleChildScrollView(
                  child: ConstrainedBox(
                    // Centres the block when it fits and scrolls when it
                    // does not, instead of overflowing.
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 56,
                        vertical: compact ? 36 : 56,
                      ),
                      // Left-aligned, not centred: the panel's left edge is
                      // then a real margin every row lines up on.
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 400),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Logo beside the wordmark, not above it, so
                              // it shares the tiles' icon column and the
                              // whole panel reads off one left edge.
                              const Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  AppLogo(size: _iconColumn),
                                  SizedBox(width: _iconGap),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          'SAIS',
                                          style: TextStyle(
                                            fontSize: 28,
                                            fontWeight: FontWeight.w800,
                                            color: AppTheme.goldLight,
                                            letterSpacing: 0.5,
                                            height: 1.1,
                                          ),
                                        ),
                                        SizedBox(height: 2),
                                        Text(
                                          'Student Assistant Information '
                                          'System',
                                          style: TextStyle(
                                            fontSize: 13.5,
                                            color: Color(0xFFFFD88A),
                                            height: 1.35,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: compact ? 22 : 30),
                              Container(
                                width: 44,
                                height: 3,
                                decoration: BoxDecoration(
                                  color: AppTheme.gold400,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              SizedBox(height: compact ? 22 : 30),
                              // Separators between tiles rather than a
                              // trailing margin, so the block stays
                              // optically centred.
                              for (var i = 0; i < brandPoints.length; i++) ...[
                                if (i > 0) SizedBox(height: gap),
                                _BrandTile(point: brandPoints[i]),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }


  // ─── Shared header ────────────────────────────────────────────────────
  Widget _headerText({bool mobile = false}) {
    final align = mobile ? CrossAxisAlignment.start : CrossAxisAlignment.center;
    final textAlign = mobile ? TextAlign.left : TextAlign.center;

    return Column(
      crossAxisAlignment: align,
      children: [
        Text(
          title,
          textAlign: textAlign,
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: AppTheme.slate900,
            letterSpacing: -0.6,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          textAlign: textAlign,
          style: const TextStyle(
            fontSize: 14.5,
            color: AppTheme.slate500,
            height: 1.5,
          ),
        ),
      ],
    );
  }

}

class _BrandTile extends StatelessWidget {
  final AuthBrandPoint point;

  const _BrandTile({required this.point});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
          Container(
            width: _iconColumn,
            height: _iconColumn,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                color: AppTheme.gold400.withValues(alpha: 0.35),
              ),
            ),
            child: Icon(point.icon, color: AppTheme.goldLight, size: 21),
          ),
          const SizedBox(width: _iconGap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  point.title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: 0.1,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  point.subtitle,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: Colors.white.withValues(alpha: 0.72),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ─── Shared form pieces ─────────────────────────────────────────────────

/// A labelled field. Pair two of these with [AuthFieldPair].
class AuthField extends StatelessWidget {
  final String label;
  final Widget child;

  const AuthField({super.key, required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppTheme.slate700,
          ),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

/// Two fields side by side once there is room for them, stacked otherwise.
class AuthFieldPair extends StatelessWidget {
  static const double _twoColumnMin = 460;

  final Widget left;
  final Widget right;

  const AuthFieldPair({super.key, required this.left, required this.right});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < _twoColumnMin) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [left, const SizedBox(height: 18), right],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: left),
            const SizedBox(width: 18),
            Expanded(child: right),
          ],
        );
      },
    );
  }
}

/// Gold rule + uppercase label, matching the landing page's section eyebrows.
class AuthSectionHeading extends StatelessWidget {
  final String label;

  const AuthSectionHeading({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 18,
          height: 3,
          decoration: BoxDecoration(
            color: AppTheme.gold400,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppTheme.maroon,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(child: Divider(color: AppTheme.slate200, height: 1)),
      ],
    );
  }
}

class AuthErrorBanner extends StatelessWidget {
  final String message;

  const AuthErrorBanner({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.red50,
        border: Border.all(color: AppTheme.red500.withValues(alpha: 0.25)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: AppTheme.red500,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppTheme.red500,
                fontSize: 13,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AuthPrimaryButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isLoading;
  final VoidCallback onPressed;

  const AuthPrimaryButton({
    super.key,
    required this.label,
    required this.icon,
    required this.isLoading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            colors: [AppTheme.maroon, AppTheme.maroonDark],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: AppTheme.maroon.withValues(alpha: 0.32),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ElevatedButton(
          onPressed: isLoading ? null : onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            disabledBackgroundColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: isLoading
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2.5,
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Icon(icon, size: 18, color: Colors.white),
                  ],
                ),
        ),
      ),
    );
  }
}

/// "Already have an account? Log in" style footer link.
class AuthFooterLink extends StatelessWidget {
  final String prompt;
  final String action;
  final VoidCallback onTap;

  const AuthFooterLink({
    super.key,
    required this.prompt,
    required this.action,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: RichText(
            textAlign: TextAlign.center,
            text: TextSpan(
              text: '$prompt ',
              style: const TextStyle(
                color: AppTheme.slate500,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              children: [
                TextSpan(
                  text: action,
                  style: const TextStyle(
                    color: AppTheme.maroon,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
