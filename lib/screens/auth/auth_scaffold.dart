import 'package:flutter/material.dart';
import '../../widgets/offline_banner.dart';
import '../../widgets/shared_widgets.dart';
import '../landing/landing_widgets.dart' show LandingColors, landingSerif;

/// Colours the forms need beyond the landing palette, each checked against
/// the background it sits on (WCAG): a field's outline has to reach 3:1 to
/// mark where the field is, and the text in a banner 4.5:1.
class AuthColors {
  const AuthColors._();

  /// A field's outline: 4.0:1 on white, 3.8:1 on paper.
  static const Color outline = Color(0xFF8A7B82);

  /// Error text on [errorTint]: 6.0:1.
  static const Color errorText = Color(0xFFB42318);
  static const Color errorTint = Color(0xFFFEF2F2);

  /// Confirmation text on [successTint]: 5.2:1.
  static const Color successText = Color(0xFF047857);
  static const Color successTint = Color(0xFFECFDF5);
}

/// One line of the numbered list beside the form.
class AuthBrandPoint {
  final String title;
  final String subtitle;

  const AuthBrandPoint(this.title, this.subtitle);
}

/// Shared chrome for the login and register screens, in the landing page's
/// style: cream paper, serif headings, flat maroon, thin rules.
///
/// Desktop puts the form beside the campus photo under a flat maroon wash
/// with a short numbered list; phones get a slim maroon bar and the form on
/// paper. Screens supply only [children]: their own fields, buttons and
/// footer link.
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
    return Theme(
      data: _formTheme(Theme.of(context)),
      child: Scaffold(
        backgroundColor: LandingColors.paper,
        body: Column(
          children: [
            const OfflineBanner(onAuthPage: true),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isMobile = constraints.maxWidth < _mobileBreakpoint;
                  return isMobile ? _mobileLayout() : _desktopLayout();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Fields sit on warm cream inside a crisp white card, with an outline dark
  /// enough to find cleanly.
  static ThemeData _formTheme(ThemeData base) {
    OutlineInputBorder outline(Color color, double width) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: color, width: width),
    );
    return base.copyWith(
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: LandingColors.paper,
        prefixIconColor: LandingColors.muted,
        suffixIconColor: LandingColors.muted,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        hintStyle: const TextStyle(color: LandingColors.muted, fontSize: 14),
        border: outline(AuthColors.outline, 1),
        enabledBorder: outline(AuthColors.outline, 1),
        focusedBorder: outline(LandingColors.maroon, 2),
        errorBorder: outline(AuthColors.errorText, 1),
        focusedErrorBorder: outline(AuthColors.errorText, 2),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        side: const BorderSide(color: AuthColors.outline, width: 1.5),
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? LandingColors.maroon
              : Colors.white,
        ),
      ),
    );
  }

  // ─── Desktop / tablet: form beside the photo ──────────────────────────
  Widget _desktopLayout() {
    return Row(
      children: [
        Expanded(flex: 6, child: _desktopForm()),
        Expanded(flex: 5, child: _photoPanel()),
      ],
    );
  }

  Widget _desktopForm() {
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 540;
          final wideHeader = constraints.maxWidth >= 520;
          return Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  onBack != null ? 12 : 32,
                  18,
                  32,
                  0,
                ),
                child: Row(
                  children: [
                    if (onBack != null) _backButton(LandingColors.ink),
                    const _Lockup(size: 34, onDark: false),
                    if (wideHeader) ...[
                      const SizedBox(width: 14),
                      Container(
                        width: 1,
                        height: 18,
                        color: LandingColors.rule,
                      ),
                      const SizedBox(width: 14),
                      const Flexible(
                        child: Text(
                          'Marinduque State University',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                            color: LandingColors.muted,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.symmetric(
                      horizontal: narrow ? 20 : 36,
                      vertical: 20,
                    ),
                    physics: const BouncingScrollPhysics(),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: maxFormWidth + (narrow ? 48 : 72),
                      ),
                      child: _formCard(
                        mobile: false,
                        narrow: narrow,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _header(mobile: false),
                            const SizedBox(height: 26),
                            ...children,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _formCard({
    required bool mobile,
    required bool narrow,
    required Widget child,
  }) {
    final radius = mobile ? 14.0 : 18.0;
    final padding = mobile
        ? EdgeInsets.fromLTRB(
            narrow ? 16 : 22,
            narrow ? 20 : 24,
            narrow ? 16 : 22,
            narrow ? 20 : 24,
          )
        : EdgeInsets.fromLTRB(
            narrow ? 24 : 36,
            narrow ? 26 : 32,
            narrow ? 24 : 36,
            narrow ? 24 : 30,
          );
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: LandingColors.ink.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: LandingColors.ink.withValues(alpha: 0.06),
            blurRadius: mobile ? 18 : 28,
            offset: Offset(0, mobile ? 6 : 10),
          ),
          BoxShadow(
            color: LandingColors.ink.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 3.5,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    LandingColors.maroonDeep,
                    LandingColors.maroon,
                    LandingColors.brass,
                  ],
                  stops: [0.0, 0.72, 1.0],
                ),
              ),
            ),
            Padding(padding: padding, child: child),
          ],
        ),
      ),
    );
  }

  Widget _backButton(Color color) => IconButton(
    onPressed: onBack,
    tooltip: 'Back to home',
    icon: Icon(Icons.arrow_back_rounded, color: color),
  );

  // ─── Mobile: a slim bar, then the form on paper ───────────────────────
  Widget _mobileLayout() {
    return Column(
      children: [
        ColoredBox(
          color: LandingColors.maroonDeep,
          child: SafeArea(
            bottom: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 56),
                  child: Row(
                    children: [
                      if (onBack != null)
                        _backButton(Colors.white)
                      else
                        const SizedBox(width: 20),
                      const _Lockup(size: 28, onDark: true),
                    ],
                  ),
                ),
                Container(
                  height: 2,
                  color: LandingColors.brass.withValues(alpha: 0.7),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 380;
              return SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  narrow ? 12 : 18,
                  18,
                  narrow ? 12 : 18,
                  28,
                ),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxFormWidth + 44),
                    child: _formCard(
                      mobile: true,
                      narrow: narrow,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _header(mobile: true),
                          const SizedBox(height: 22),
                          ...children,
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ─── Photo panel (desktop only) ───────────────────────────────────────
  Widget _photoPanel() {
    return Stack(
      fit: StackFit.expand,
      children: [
        // The campus under a directional maroon wash so the building stays
        // visible while keeping the typography crisp; a failed image leaves
        // the deep maroon gradient.
        ExcludeSemantics(
          child: Image.asset(
            'assets/images/marsu_campus.jpg',
            fit: BoxFit.cover,
            frameBuilder: (context, child, frame, sync) =>
                frame == null && !sync
                ? const ColoredBox(color: LandingColors.maroonDeep)
                : child,
            errorBuilder: (_, _, _) =>
                const ColoredBox(color: LandingColors.maroonDeep),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [
                LandingColors.maroonDeep.withValues(alpha: 0.56),
                LandingColors.maroonDeep.withValues(alpha: 0.80),
                const Color(0xFF3E0A1B).withValues(alpha: 0.94),
              ],
              stops: const [0.0, 0.45, 1.0],
            ),
          ),
        ),
        SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Laptop-height windows leave little room: tighten rather than
              // overflow.
              final compact = constraints.maxHeight < 680;
              return SingleChildScrollView(
                child: ConstrainedBox(
                  // Centred when it fits, scrolls when it does not.
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: 48,
                      vertical: compact ? 24 : 48,
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 400),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.18),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: const BoxDecoration(
                                      color: LandingColors.brass,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      'MARINDUQUE STATE UNIVERSITY',
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 1.4,
                                        color: LandingColors.paper.withValues(
                                          alpha: 0.94,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              'STUDENT ASSISTANT INFORMATION SYSTEM',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.6,
                                height: 1.4,
                                color: LandingColors.paper.withValues(
                                  alpha: 0.85,
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            Container(
                              width: 32,
                              height: 2.5,
                              decoration: BoxDecoration(
                                color: LandingColors.brass,
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                            SizedBox(height: compact ? 14 : 24),
                            for (var i = 0; i < brandPoints.length; i++)
                              _LedgerRow(
                                number: i + 1,
                                point: brandPoints[i],
                                first: i == 0,
                                compact: compact,
                              ),
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
    );
  }

  // ─── Shared header ────────────────────────────────────────────────────
  Widget _header({required bool mobile}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            title,
            style: TextStyle(
              fontFamily: landingSerif,
              fontSize: mobile ? 28 : 34,
              fontWeight: FontWeight.w600,
              color: LandingColors.ink,
              letterSpacing: -0.8,
              height: 1.12,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: const TextStyle(
            fontSize: 15,
            color: LandingColors.muted,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}

/// The seal beside the wordmark.
class _Lockup extends StatelessWidget {
  final double size;
  final bool onDark;

  const _Lockup({required this.size, required this.onDark});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // The wordmark beside it says "SAIS", so a screen reader skips it.
        SaisLogo(size: size, shadow: const [], excludeFromSemantics: true),
        const SizedBox(width: 10),
        Text(
          'SAIS',
          style: TextStyle(
            fontFamily: landingSerif,
            fontSize: size * 0.62,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.6,
            color: onDark ? Colors.white : LandingColors.ink,
          ),
        ),
      ],
    );
  }
}

/// One numbered line of the list beside the form: frosted brass badge,
/// title, one sentence, and a thin hairline between lines.
class _LedgerRow extends StatelessWidget {
  final int number;
  final AuthBrandPoint point;
  final bool first;
  final bool compact;

  const _LedgerRow({
    required this.number,
    required this.point,
    required this.first,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final verticalPad = compact ? 14.0 : 18.0;
    return Container(
      decoration: BoxDecoration(
        border: first
            ? null
            : Border(
                top: BorderSide(color: Colors.white.withValues(alpha: 0.16)),
              ),
      ),
      padding: EdgeInsets.only(top: first ? 0 : verticalPad, bottom: verticalPad),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: LandingColors.brass.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: LandingColors.brass.withValues(alpha: 0.35),
              ),
            ),
            child: Text(
              number.toString().padLeft(2, '0'),
              style: const TextStyle(
                fontFamily: landingSerif,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: LandingColors.brass,
                height: 1.0,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  point.title,
                  style: const TextStyle(
                    fontSize: 16.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  point.subtitle,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: Colors.white.withValues(alpha: 0.84),
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

// ─── Shared form pieces ─────────────────────────────────────────────────

/// A labelled field. Pair two of these with [AuthFieldPair]. A screen reader
/// reads the label with the field it names.
class AuthField extends StatelessWidget {
  final String label;
  final Widget child;

  /// Whether the label and the field are read as one. Not for a field with a
  /// button of its own (the show-password eye), which must stay a separate
  /// control.
  final bool merge;

  const AuthField({
    super.key,
    required this.label,
    required this.child,
    this.merge = true,
  });

  @override
  Widget build(BuildContext context) {
    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: LandingColors.ink,
          ),
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
    return merge ? MergeSemantics(child: column) : column;
  }
}

/// A checkbox with its text: one focus stop, the label read with the box,
/// and a click anywhere on the row toggles it.
class AuthCheckRow extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  /// What a screen reader calls the checkbox.
  final String semanticsLabel;

  /// The visible text; it is not read a second time.
  final Widget label;

  const AuthCheckRow({
    super.key,
    required this.value,
    required this.onChanged,
    required this.semanticsLabel,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      // The checkbox is the one focus stop and the one control to a screen
      // reader; this only widens the click.
      canRequestFocus: false,
      excludeFromSemantics: true,
      borderRadius: BorderRadius.circular(8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              label: semanticsLabel,
              child: SizedBox(
                width: 44,
                height: 44,
                child: Checkbox(
                  value: value,
                  onChanged: (v) => onChanged(v ?? false),
                ),
              ),
            ),
            Flexible(child: ExcludeSemantics(child: label)),
            const SizedBox(width: 4),
          ],
        ),
      ),
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
            children: [left, const SizedBox(height: 16), right],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: left),
            const SizedBox(width: 14),
            Expanded(child: right),
          ],
        );
      },
    );
  }
}

/// Brass rule + uppercase label, like the landing page's section eyebrows.
class AuthSectionHeading extends StatelessWidget {
  final String label;

  const AuthSectionHeading({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Row(
        children: [
          Container(width: 20, height: 2, color: LandingColors.brass),
          const SizedBox(width: 10),
          // Flexible: large text sizes wrap the label rather than overflow.
          Flexible(
            child: Text(
              label.toUpperCase(),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: LandingColors.maroon,
                letterSpacing: 1.6,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Divider(color: LandingColors.rule, height: 1)),
        ],
      ),
    );
  }
}

class AuthErrorBanner extends StatelessWidget {
  final String message;

  /// A button under the message, such as Login's "Send a new link".
  final Widget? action;

  const AuthErrorBanner({super.key, required this.message, this.action});

  @override
  Widget build(BuildContext context) {
    return _AuthBanner(
      message: message,
      icon: Icons.error_outline_rounded,
      color: AuthColors.errorText,
      background: AuthColors.errorTint,
      action: action,
    );
  }
}

/// Green counterpart of [AuthErrorBanner], for something that worked.
class AuthNoticeBanner extends StatelessWidget {
  final String message;

  const AuthNoticeBanner({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return _AuthBanner(
      message: message,
      icon: Icons.mark_email_read_outlined,
      color: AuthColors.successText,
      background: AuthColors.successTint,
    );
  }
}

class _AuthBanner extends StatelessWidget {
  final String message;
  final IconData icon;
  final Color color;
  final Color background;
  final Widget? action;

  const _AuthBanner({
    required this.message,
    required this.icon,
    required this.color,
    required this.background,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    // A live region: a screen reader announces the message when it appears.
    return Semantics(
      liveRegion: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Container(
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.22)),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 3.5, color: color),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(icon, color: color, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                message,
                                style: TextStyle(
                                  color: color,
                                  fontSize: 13.5,
                                  height: 1.45,
                                ),
                              ),
                              if (action != null) ...[
                                const SizedBox(height: 10),
                                action!,
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
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

/// The form's main button: flat maroon, like the landing page's.
class AuthPrimaryButton extends StatelessWidget {
  final String label;
  final bool isLoading;
  final VoidCallback onPressed;

  /// What a screen reader says while [isLoading].
  final String loadingLabel;

  const AuthPrimaryButton({
    super.key,
    required this.label,
    required this.isLoading,
    required this.onPressed,
    this.loadingLabel = 'Please wait',
  });

  @override
  Widget build(BuildContext context) {
    final hover = Color.lerp(
      LandingColors.maroon,
      LandingColors.maroonDeep,
      0.35,
    )!;
    return ElevatedButton(
      onPressed: isLoading ? null : onPressed,
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(double.infinity, 50)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
        elevation: const WidgetStatePropertyAll(0),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        foregroundColor: const WidgetStatePropertyAll(Colors.white),
        // Stays maroon while the spinner shows, rather than greying out.
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.hovered) ||
                  states.contains(WidgetState.pressed)
              ? hover
              : LandingColors.maroon,
        ),
        // A ButtonStyle's text style replaces the theme's, family included.
        textStyle: const WidgetStatePropertyAll(
          TextStyle(
            fontFamily: 'Inter',
            fontSize: 15.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      child: isLoading
          ? Semantics(
              label: loadingLabel,
              liveRegion: true,
              child: const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.5,
                ),
              ),
            )
          : Text(label, textAlign: TextAlign.center),
    );
  }
}

/// A quiet button beside the main one: white, hairline outline.
ButtonStyle authSecondaryButtonStyle() => OutlinedButton.styleFrom(
  foregroundColor: LandingColors.ink,
  backgroundColor: Colors.white,
  overlayColor: LandingColors.paper,
  side: const BorderSide(color: AuthColors.outline),
  minimumSize: const Size(double.infinity, 50),
  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
  textStyle: const TextStyle(
    fontFamily: 'Inter',
    fontSize: 15,
    fontWeight: FontWeight.w600,
  ),
);

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
      child: TapTarget(
        onTap: onTap,
        label: '$prompt $action',
        focusColor: LandingColors.maroon,
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: RichText(
              textAlign: TextAlign.center,
              textScaler: MediaQuery.textScalerOf(context),
              text: TextSpan(
                text: '$prompt ',
                style: const TextStyle(
                  fontFamily: 'Inter',
                  color: LandingColors.muted,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w500,
                ),
                children: [
                  TextSpan(
                    text: action,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      color: LandingColors.maroon,
                      fontWeight: FontWeight.w700,
                      fontSize: 14.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
