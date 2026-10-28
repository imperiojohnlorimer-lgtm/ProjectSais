import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// The landing page's palette, taken from the campus itself: MarSU maroon, the
/// building's warm cream, warm ink. There is no bright yellow: a muted brass
/// appears only as thin rules on dark backgrounds, never as text or as a fill
/// behind text.
class LandingColors {
  const LandingColors._();

  static const Color maroon = AppTheme.maroon;
  static const Color maroonDeep = Color(0xFF5A1027);
  static const Color maroonTint = Color(0xFFF6ECEE);
  static const Color paper = Color(0xFFFBF8F3);
  static const Color sand = Color(0xFFF2EADC);
  static const Color brass = Color(0xFFC9AC72);
  static const Color ink = Color(0xFF231419);

  /// Body text on paper, sand and white.
  static const Color body = Color(0xFF4D3F45);

  /// Small print on paper, sand and white (above 5:1).
  static const Color muted = Color(0xFF6E5F66);

  /// A hairline on light backgrounds.
  static Color get rule => ink.withValues(alpha: 0.14);
}

/// The display serif used for headings on this page only.
const landingSerif = 'SourceSerifDisplay';

// ─── Section heading ────────────────────────────────────────────────────
class LandingHeading extends StatelessWidget {
  final String label;
  final String title;
  final String? subtitle;
  final bool centered;
  final bool onDark;

  const LandingHeading({
    super.key,
    required this.label,
    required this.title,
    this.subtitle,
    this.centered = false,
    this.onDark = false,
  });

  @override
  Widget build(BuildContext context) {
    final accent = onDark ? LandingColors.brass : LandingColors.maroon;
    final phone = MediaQuery.sizeOf(context).width < 600;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 640),
      child: Column(
        crossAxisAlignment: centered
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: onDark ? Colors.white.withValues(alpha: 0.85) : accent,
              letterSpacing: 1.8,
            ),
          ),
          const SizedBox(height: 14),
          Semantics(
            header: true,
            child: Text(
              title,
              textAlign: centered ? TextAlign.center : TextAlign.start,
              style: TextStyle(
                fontFamily: landingSerif,
                fontSize: phone ? 32 : 40,
                fontWeight: FontWeight.w600,
                color: onDark ? Colors.white : LandingColors.ink,
                height: 1.12,
                letterSpacing: -0.6,
              ),
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 16),
            Text(
              subtitle!,
              textAlign: centered ? TextAlign.center : TextAlign.start,
              style: TextStyle(
                fontSize: 16.5,
                height: 1.65,
                color: onDark
                    ? Colors.white.withValues(alpha: 0.86)
                    : LandingColors.body,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Ledger item ────────────────────────────────────────────────────────
/// One reason to join: a serif numeral on a hairline, then title and text.
class LedgerItem extends StatelessWidget {
  final String number;
  final String title;
  final String body;

  const LedgerItem({
    super.key,
    required this.number,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(top: 18),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: LandingColors.rule)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 44,
            child: Text(
              number,
              style: const TextStyle(
                fontFamily: landingSerif,
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: LandingColors.maroon,
                height: 1.2,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: LandingColors.ink,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  body,
                  style: const TextStyle(
                    fontSize: 14.5,
                    height: 1.6,
                    color: LandingColors.body,
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

// ─── Step ───────────────────────────────────────────────────────────────
/// A step on the way in, in a vertical list joined by a thin line.
class StepItem extends StatelessWidget {
  final String number;
  final String title;
  final String body;
  final bool last;

  const StepItem({
    super.key,
    required this.number,
    required this.title,
    required this.body,
    this.last = false,
  });

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 40,
            child: Column(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: LandingColors.maroon,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    number,
                    style: const TextStyle(
                      fontFamily: landingSerif,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
                if (!last)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      color: LandingColors.maroon.withValues(alpha: 0.18),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: 8, bottom: last ? 0 : 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 17.5,
                      fontWeight: FontWeight.w700,
                      color: LandingColors.ink,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    body,
                    style: const TextStyle(
                      fontSize: 14.5,
                      height: 1.6,
                      color: LandingColors.body,
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

// ─── What to prepare ────────────────────────────────────────────────────
class PrepareItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const PrepareItem({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: LandingColors.rule),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ExcludeSemantics(
            child: Icon(icon, size: 24, color: LandingColors.maroon),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: const TextStyle(
              fontSize: 16.5,
              fontWeight: FontWeight.w700,
              color: LandingColors.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: const TextStyle(
              fontSize: 14,
              height: 1.6,
              color: LandingColors.body,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── FAQ ────────────────────────────────────────────────────────────────
/// A row that opens to its answer, with a plus or a minus.
class FaqItem extends StatefulWidget {
  final String question;
  final String answer;
  final String? linkLabel;
  final VoidCallback? onLink;

  const FaqItem({
    super.key,
    required this.question,
    required this.answer,
    this.linkLabel,
    this.onLink,
  });

  @override
  State<FaqItem> createState() => _FaqItemState();
}

class _FaqItemState extends State<FaqItem> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: LandingColors.rule)),
      ),
      // ExpansionTile brings keyboard focus, Enter/Space and screen-reader
      // expanded/collapsed state with it.
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
          splashColor: LandingColors.maroon.withValues(alpha: 0.05),
        ),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(vertical: 8),
          childrenPadding: const EdgeInsets.only(bottom: 22, right: 48),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          expandedAlignment: Alignment.centerLeft,
          shape: const Border(),
          collapsedShape: const Border(),
          onExpansionChanged: (open) => setState(() => _open = open),
          trailing: Icon(
            _open ? Icons.remove_rounded : Icons.add_rounded,
            color: LandingColors.maroon,
            size: 24,
          ),
          title: Text(
            widget.question,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: LandingColors.ink,
            ),
          ),
          children: [
            Text(
              widget.answer,
              style: const TextStyle(
                fontSize: 15.5,
                height: 1.65,
                color: LandingColors.body,
              ),
            ),
            if (widget.linkLabel != null && widget.onLink != null) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: widget.onLink,
                style: TextButton.styleFrom(
                  foregroundColor: LandingColors.maroon,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 36),
                  alignment: Alignment.centerLeft,
                ),
                child: Text(
                  widget.linkLabel!,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Sample ID card ─────────────────────────────────────────────────────
/// What a Student Assistant's record looks like: a campus ID card with the
/// application's stages down it. It is a sample, and says so, so it promises
/// nothing about a real application.
class IdCard extends StatelessWidget {
  const IdCard({super.key});

  static const _stages = [
    ('Application submitted', 'Your skills and documents are in.', _Stamp.done),
    ('Screening', 'The Head reviews and picks who to interview.', _Stamp.done),
    ('Approved', 'You get your Student Assistant ID.', _Stamp.current),
    (
      'Placed in an office',
      'Matched to an office that fits your skills.',
      _Stamp.next,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label:
          'Sample student assistant ID card with the application tracker: '
          'submitted, screening, approved, then placed in an office.',
      child: ExcludeSemantics(
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: LandingColors.rule),
            boxShadow: [
              BoxShadow(
                color: LandingColors.maroonDeep.withValues(alpha: 0.08),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 20, 22, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _identity(),
                    const SizedBox(height: 20),
                    const Text(
                      'APPLICATION STATUS',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.5,
                        color: LandingColors.muted,
                      ),
                    ),
                    const SizedBox(height: 14),
                    for (var i = 0; i < _stages.length; i++)
                      _StampRow(
                        title: _stages[i].$1,
                        note: _stages[i].$2,
                        stamp: _stages[i].$3,
                        last: i == _stages.length - 1,
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 14,
                ),
                color: LandingColors.paper,
                child: const Row(
                  children: [
                    Icon(
                      Icons.notifications_none_rounded,
                      size: 18,
                      color: LandingColors.maroon,
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'You are notified when you are picked for screening '
                        'and when a decision is made.',
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.45,
                          color: LandingColors.body,
                        ),
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

  Widget _header() {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 16, 16, 14),
      decoration: const BoxDecoration(
        color: LandingColors.maroonDeep,
        border: Border(
          bottom: BorderSide(color: LandingColors.brass, width: 2),
        ),
      ),
      child: Row(
        children: [
          ClipOval(
            child: Image.asset(
              'assets/images/seal.png',
              width: 34,
              height: 34,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'MARINDUQUE STATE UNIVERSITY',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Student Assistant',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Color(0xFFE9DCC4),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.white.withValues(alpha: 0.6)),
            ),
            child: const Text(
              'SAMPLE',
              style: TextStyle(
                color: Colors.white,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _identity() {
    Widget field(String label, String value) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.3,
            color: LandingColors.muted,
          ),
        ),
        const SizedBox(height: 3),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.only(bottom: 4),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: LandingColors.rule)),
          ),
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: LandingColors.ink,
            ),
          ),
        ),
      ],
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 62,
          height: 76,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: LandingColors.maroonTint,
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Text(
            'J',
            style: TextStyle(
              fontFamily: landingSerif,
              fontSize: 30,
              fontWeight: FontWeight.w600,
              color: LandingColors.maroon,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            children: [
              field('NAME', 'Juan D. (sample)'),
              const SizedBox(height: 10),
              field('PROGRAM', 'Your program and year level'),
            ],
          ),
        ),
      ],
    );
  }
}

enum _Stamp { done, current, next }

class _StampRow extends StatelessWidget {
  final String title;
  final String note;
  final _Stamp stamp;
  final bool last;

  const _StampRow({
    required this.title,
    required this.note,
    required this.stamp,
    required this.last,
  });

  @override
  Widget build(BuildContext context) {
    final done = stamp == _Stamp.done;
    final current = stamp == _Stamp.current;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 24,
            child: Column(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: done ? LandingColors.maroon : Colors.white,
                    border: Border.all(
                      color: done || current
                          ? LandingColors.maroon
                          : LandingColors.rule,
                      width: 2,
                    ),
                  ),
                  child: done
                      ? const Icon(Icons.check, size: 14, color: Colors.white)
                      : current
                      ? Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: LandingColors.maroon,
                            shape: BoxShape.circle,
                          ),
                        )
                      : null,
                ),
                if (!last)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: done
                          ? LandingColors.maroon.withValues(alpha: 0.5)
                          : LandingColors.rule,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 14 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: stamp == _Stamp.next
                          ? LandingColors.muted
                          : LandingColors.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    note,
                    style: const TextStyle(
                      fontSize: 13.5,
                      height: 1.45,
                      color: LandingColors.body,
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

// ─── Small bits ─────────────────────────────────────────────────────────
class HeroNote extends StatelessWidget {
  final IconData icon;
  final String label;

  const HeroNote({super.key, required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ExcludeSemantics(
          child: Icon(
            icon,
            size: 17,
            color: Colors.white.withValues(alpha: 0.8),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w500,
              color: Colors.white.withValues(alpha: 0.92),
            ),
          ),
        ),
      ],
    );
  }
}

/// One of the three quick facts on the card under the hero.
class FactItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const FactItem({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: LandingColors.maroonTint,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: LandingColors.maroon, size: 22),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: LandingColors.ink,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                body,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.45,
                  color: LandingColors.muted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A capability the offices side of SAIS covers.
class StaffChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const StaffChip({super.key, required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: LandingColors.rule),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ExcludeSemantics(
            child: Icon(icon, size: 16, color: LandingColors.maroon),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: LandingColors.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
