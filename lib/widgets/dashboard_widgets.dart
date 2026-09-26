import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Shared building blocks for the four role dashboards.
///
/// Each dashboard used to carry its own copy of the breakpoint arithmetic,
/// its own page heading, and — the expensive one — two separate definitions
/// of its stat cards: a list for wide screens and a hand-written 2x2 grid for
/// phones, with the same numbers spelled out twice. Everything visual lives
/// here now so a stat is declared once.

/// Breakpoints and spacing, worked out once per build.
class DashboardMetrics {
  final double width;

  const DashboardMetrics(this.width);

  factory DashboardMetrics.of(BuildContext context) =>
      DashboardMetrics(MediaQuery.sizeOf(context).width);

  bool get isMobile => width < 480;
  bool get isSmall => width < 768;

  /// One column only on the narrowest phones; two until there is room for
  /// the full row of four.
  int get statColumns => width < 380 ? 1 : (isSmall ? 2 : 4);

  double get statTileHeight => isMobile ? 84 : (isSmall ? 90 : 94);

  EdgeInsets get pagePadding => EdgeInsets.symmetric(
    horizontal: isMobile ? 16 : (isSmall ? 20 : 32),
    vertical: isMobile ? 16 : (isSmall ? 20 : 28),
  );

  double get gap => isMobile ? 12 : 16;
  double get sectionGap => isMobile ? 24 : 32;
}

/// What a stat's colour is allowed to mean.
///
/// Status colours are reserved for status: a tile is only [good] or
/// [attention] when the number itself reports a state someone should act on.
/// Plain counts stay on the brand colour rather than picking a hue for
/// decoration.
enum StatTone { brand, good, attention, muted }

extension _StatToneColor on StatTone {
  Color get color => switch (this) {
    StatTone.brand => AppTheme.maroon,
    StatTone.good => AppTheme.emerald500,
    StatTone.attention => AppTheme.amber500,
    StatTone.muted => AppTheme.slate400,
  };
}

/// A headline number. Not a chart — the number is the point.
class DashboardStatTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final StatTone tone;

  const DashboardStatTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.tone = StatTone.brand,
  });

  @override
  Widget build(BuildContext context) {
    final accent = tone.color;
    final metrics = DashboardMetrics.of(context);
    final chip = metrics.isMobile ? 34.0 : 40.0;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.slate200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Accent rule rather than a coloured border, so the card keeps its
          // outline on all four sides.
          Container(width: 4, height: double.infinity, color: accent),
          Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: metrics.isMobile ? 12 : 16,
              ),
              child: Row(
                children: [
                  Container(
                    width: chip,
                    height: chip,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(
                      icon,
                      size: metrics.isMobile ? 17 : 19,
                      color: accent,
                    ),
                  ),
                  SizedBox(width: metrics.isMobile ? 10 : 13),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: metrics.isMobile ? 20 : 23,
                            fontWeight: FontWeight.w800,
                            // Text keeps its own token; the accent rule and
                            // the icon carry the colour.
                            color: AppTheme.slate900,
                            height: 1.15,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppTheme.slate500,
                            fontWeight: FontWeight.w600,
                            height: 1.25,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The row of headline numbers a dashboard opens with.
class DashboardStatRow extends StatelessWidget {
  final List<DashboardStatTile> tiles;

  const DashboardStatRow({super.key, required this.tiles});

  @override
  Widget build(BuildContext context) {
    final metrics = DashboardMetrics.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        // Fewer tiles than columns share the row instead of leaving a gap.
        final columns = tiles.length < metrics.statColumns
            ? tiles.length
            : metrics.statColumns;
        final gap = metrics.gap;
        double widthFor(int perRow) =>
            (constraints.maxWidth - gap * (perRow - 1)) / perRow;
        // A part-filled last row (three tiles on two columns) shares the
        // full width rather than leaving a hole.
        final lastRowStart = tiles.length - (tiles.length % columns);
        final lastRowCount = tiles.length - lastRowStart;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (var i = 0; i < tiles.length; i++)
              SizedBox(
                width: i >= lastRowStart && lastRowCount > 0
                    ? widthFor(lastRowCount)
                    : widthFor(columns),
                height: metrics.statTileHeight,
                child: tiles[i],
              ),
          ],
        );
      },
    );
  }
}

/// Page title and one line of context.
class DashboardHeading extends StatelessWidget {
  final String title;
  final String subtitle;

  const DashboardHeading({
    super.key,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final metrics = DashboardMetrics.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 4,
          height: metrics.isMobile ? 34 : 40,
          margin: const EdgeInsets.only(top: 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(2),
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [AppTheme.maroon, AppTheme.gold400],
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: metrics.isMobile ? 21 : 27,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.slate900,
                  letterSpacing: -0.6,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: metrics.isMobile ? 12.5 : 14,
                  fontWeight: FontWeight.w400,
                  color: AppTheme.slate500,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// White panel with a title and an optional "view all" action.
class DashboardSectionCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Widget child;

  const DashboardSectionCard({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 15.5,
            fontWeight: FontWeight.w800,
            color: AppTheme.slate900,
            letterSpacing: -0.2,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(
            subtitle!,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppTheme.slate400,
              height: 1.35,
            ),
          ),
        ],
      ],
    );

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.slate200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Deliberately not a LayoutBuilder: that cannot report intrinsic
          // dimensions, so a card containing one throws inside any
          // IntrinsicHeight — which is how the dashboards make side-by-side
          // columns match heights. Expanded plus ellipsis handles narrow
          // cards without needing to measure.
          if (actionLabel == null)
            heading
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: heading),
                const SizedBox(width: 12),
                _action(),
              ],
            ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _action() {
    return GestureDetector(
      onTap: onAction,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              actionLabel!,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: AppTheme.maroon,
              ),
            ),
            const SizedBox(width: 2),
            const Icon(
              Icons.arrow_forward_rounded,
              size: 14,
              color: AppTheme.maroon,
            ),
          ],
        ),
      ),
    );
  }
}

/// Placeholder for a section with nothing in it yet.
class DashboardEmptyRow extends StatelessWidget {
  final IconData icon;
  final String message;

  const DashboardEmptyRow({
    super.key,
    required this.icon,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 22),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              color: AppTheme.slate100,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 22, color: AppTheme.slate300),
          ),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppTheme.slate400,
            ),
          ),
        ],
      ),
    );
  }
}

/// Categorical chart colours, in fixed order.
///
/// Validated for the light chart surface: all three sit inside the lightness
/// band, clear the chroma floor, hold ΔE 21+ separation under deuteranopia
/// and tritanopia, and reach 3:1 against the surface. They are deliberately
/// not the status colours — those mean good/warning and are never spent on
/// identity. Assign by position and never cycle: a fourth category folds
/// into "Other" rather than reusing a hue.
class ChartPalette {
  const ChartPalette._();

  static const Color slot1 = Color(0xFFA63A5D);
  static const Color slot2 = Color(0xFF3B82F6);
  static const Color slot3 = Color(0xFFB8860B);

  static const List<Color> categorical = [slot1, slot2, slot3];

  /// A single series gets one colour; the axis already carries identity.
  static const Color series = AppTheme.maroon;
}
