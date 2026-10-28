import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// The small pieces the landing page is built from.

// ─── Section heading ────────────────────────────────────────────────────
class LandingSectionHeading extends StatelessWidget {
  final String eyebrow;
  final String title;
  final String? subtitle;
  final bool centered;

  const LandingSectionHeading({
    super.key,
    required this.eyebrow,
    required this.title,
    this.subtitle,
    this.centered = false,
  });

  @override
  Widget build(BuildContext context) {
    final align = centered
        ? CrossAxisAlignment.center
        : CrossAxisAlignment.start;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 680),
      child: Column(
        crossAxisAlignment: align,
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
          Semantics(
            header: true,
            child: Text(
              title,
              textAlign: centered ? TextAlign.center : TextAlign.start,
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w800,
                color: AppTheme.slate900,
                height: 1.18,
                letterSpacing: -0.9,
              ),
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 12),
            Text(
              subtitle!,
              textAlign: centered ? TextAlign.center : TextAlign.start,
              style: const TextStyle(
                fontSize: 15.5,
                height: 1.6,
                color: AppTheme.slate600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Benefit card ───────────────────────────────────────────────────────
class BenefitCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final String body;

  const BenefitCard({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  State<BenefitCard> createState() => _BenefitCardState();
}

class _BenefitCardState extends State<BenefitCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    // Lift on hover only for those who haven't asked for less motion.
    final lift = _hover && !MediaQuery.disableAnimationsOf(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        transform: Matrix4.translationValues(0, lift ? -4 : 0, 0),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: _hover ? AppTheme.maroon200 : AppTheme.slate200,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: _hover ? 0.07 : 0.03),
              blurRadius: _hover ? 22 : 10,
              offset: Offset(0, _hover ? 10 : 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppTheme.maroon50,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(widget.icon, color: AppTheme.maroon, size: 24),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              widget.title,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppTheme.slate900,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.body,
              style: const TextStyle(
                fontSize: 14,
                height: 1.6,
                color: AppTheme.slate600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Step card ──────────────────────────────────────────────────────────
class StepCard extends StatelessWidget {
  final String number;
  final String title;
  final String body;

  const StepCard({
    super.key,
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
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.maroon100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            number,
            style: const TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w800,
              color: AppTheme.maroon,
              height: 1,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            width: 28,
            height: 3,
            decoration: BoxDecoration(
              color: AppTheme.gold400,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppTheme.slate900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: const TextStyle(
              fontSize: 14,
              height: 1.6,
              color: AppTheme.slate600,
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppTheme.gold100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppTheme.maroon, size: 20),
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
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.slate900,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                body,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.55,
                  color: AppTheme.slate600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── FAQ ────────────────────────────────────────────────────────────────
class FaqItem extends StatelessWidget {
  final String question;
  final String answer;

  /// A link under the answer (the Privacy Notice, say).
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
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.slate200),
      ),
      clipBehavior: Clip.antiAlias,
      // ExpansionTile brings keyboard focus, Enter/Space and screen-reader
      // expanded/collapsed state with it.
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          expandedAlignment: Alignment.centerLeft,
          iconColor: AppTheme.maroon,
          collapsedIconColor: AppTheme.slate500,
          title: Text(
            question,
            style: const TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w700,
              color: AppTheme.slate900,
            ),
          ),
          children: [
            Text(
              answer,
              style: const TextStyle(
                fontSize: 14.5,
                height: 1.65,
                color: AppTheme.slate600,
              ),
            ),
            if (linkLabel != null && onLink != null) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: onLink,
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.maroon,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 36),
                  alignment: Alignment.centerLeft,
                ),
                child: Text(
                  linkLabel!,
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

// ─── The hero's sample application card ─────────────────────────────────
/// What a student sees after applying: a sample, labelled as one, so the page
/// shows what happens next without claiming anything about a real application.
class SampleApplicationCard extends StatelessWidget {
  const SampleApplicationCard({super.key});

  static const _stages = [
    ('Application submitted', 'Your skills and documents are in.', _Stage.done),
    ('Screening', 'The Head reviews and picks who to interview.', _Stage.done),
    ('Approved', 'You get your Student Assistant ID.', _Stage.current),
    (
      'Placed in an office',
      'Matched to an office that fits your skills.',
      _Stage.next,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label:
          'Sample of the application tracker: submitted, screening, approved, '
          'then placed in an office.',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppTheme.slate200),
            boxShadow: [
              BoxShadow(
                color: AppTheme.maroon.withValues(alpha: 0.10),
                blurRadius: 40,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: AppTheme.maroon50,
                      shape: BoxShape.circle,
                    ),
                    child: const Text(
                      'J',
                      style: TextStyle(
                        color: AppTheme.maroon,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'My application',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.slate900,
                          ),
                        ),
                        Text(
                          'Student Assistant · sample',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: AppTheme.slate600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.gold100,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      'Sample',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.maroonDark,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              for (var i = 0; i < _stages.length; i++)
                _StageRow(
                  title: _stages[i].$1,
                  note: _stages[i].$2,
                  stage: _stages[i].$3,
                  last: i == _stages.length - 1,
                ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.slate50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.notifications_active_outlined,
                      size: 18,
                      color: AppTheme.maroon,
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'You are notified when you are picked for screening and when a decision is made.',
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.4,
                          color: AppTheme.slate600,
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
}

enum _Stage { done, current, next }

class _StageRow extends StatelessWidget {
  final String title;
  final String note;
  final _Stage stage;
  final bool last;

  const _StageRow({
    required this.title,
    required this.note,
    required this.stage,
    required this.last,
  });

  @override
  Widget build(BuildContext context) {
    final done = stage == _Stage.done;
    final current = stage == _Stage.current;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 28,
            child: Column(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: done
                        ? AppTheme.emerald500
                        : current
                        ? AppTheme.maroon
                        : Colors.white,
                    border: Border.all(
                      color: done
                          ? AppTheme.emerald500
                          : current
                          ? AppTheme.maroon
                          : AppTheme.slate300,
                      width: 2,
                    ),
                  ),
                  child: done
                      ? const Icon(Icons.check, size: 14, color: Colors.white)
                      : current
                      ? Container(
                          margin: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                        )
                      : null,
                ),
                if (!last)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: done ? AppTheme.emerald500 : AppTheme.slate200,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 12 : 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: stage == _Stage.next
                          ? AppTheme.slate600
                          : AppTheme.slate900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    note,
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.4,
                      color: AppTheme.slate600,
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
        ExcludeSemantics(child: Icon(icon, size: 17, color: AppTheme.maroon)),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: AppTheme.slate700,
            ),
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
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.slate200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ExcludeSemantics(child: Icon(icon, size: 16, color: AppTheme.maroon)),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.slate700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
