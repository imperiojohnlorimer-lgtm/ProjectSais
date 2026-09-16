import 'package:flutter/material.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';

class AnnouncementCard extends StatelessWidget {
  final Announcement announcement;
  final bool showActions;
  final Widget? trailing;
  final List<Widget>? footerActions;
  final Color? borderColor;
  final bool compact;

  const AnnouncementCard({
    super.key,
    required this.announcement,
    this.showActions = false,
    this.trailing,
    this.footerActions,
    this.borderColor,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColorFor(announcement);
    final statusLabel = _statusLabelFor(announcement);
    final statusIcon = _statusIconFor(announcement);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.slate200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: statusColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.campaign_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            announcement.title,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.slate900,
                            ),
                          ),
                        ),
                        if (trailing != null) ...[
                          const SizedBox(width: 8),
                          trailing!,
                        ] else
                          _StatusBadge(
                            color: statusColor,
                            icon: statusIcon,
                            label: statusLabel,
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Posted by ${announcement.postedBy} · ${announcement.postedAt}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.slate400,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            announcement.body,
            style: const TextStyle(
              fontSize: 12.5,
              color: AppTheme.slate600,
              height: 1.6,
            ),
            maxLines: compact ? 2 : 4,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (announcement.officeName != null)
                _Chip(
                  Icons.apartment_rounded,
                  announcement.officeName!,
                  AppTheme.maroon,
                ),
              if (announcement.deadline != null)
                _Chip(
                  Icons.event_rounded,
                  'Due ${announcement.deadline!}',
                  AppTheme.amber500,
                ),
              if (announcement.slots != null)
                _Chip(
                  Icons.people_rounded,
                  '${announcement.slots} slots',
                  AppTheme.blue500,
                ),
            ],
          ),
          if (announcement.requirements.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: announcement.requirements
                  .map((req) => RequirementChip(label: req))
                  .toList(),
            ),
          ],
          if (announcement.isRejected &&
              announcement.rejectionReason != null &&
              announcement.rejectionReason!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.red50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppTheme.red500.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.comment_outlined,
                    size: 14,
                    color: AppTheme.red500,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Reason: ${announcement.rejectionReason}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.slate700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          Divider(color: AppTheme.slate100, height: 1),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Submitted ${announcement.postedAt}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.slate400,
                  ),
                ),
              ),
              if (showActions && footerActions != null) ...footerActions!,
            ],
          ),
        ],
      ),
    );
  }

  Color _statusColorFor(Announcement ann) {
    if (ann.isPending) return AppTheme.amber500;
    if (ann.isRejected) return AppTheme.red500;
    return ann.isOpen ? AppTheme.emerald500 : AppTheme.slate400;
  }

  IconData _statusIconFor(Announcement ann) {
    if (ann.isPending) return Icons.hourglass_top_rounded;
    if (ann.isRejected) return Icons.cancel_rounded;
    return Icons.check_circle_rounded;
  }

  String _statusLabelFor(Announcement ann) {
    if (ann.isPending) return 'Pending Approval';
    if (ann.isRejected) return 'Rejected';
    return ann.isOpen ? 'Live · Open' : 'Live · Closed';
  }
}

Future<void> showAnnouncementDetailsDialog(
  BuildContext context,
  Announcement announcement,
) async {
  return showDialog<void>(
    context: context,
    builder: (_) => AnnouncementDetailsDialog(announcement: announcement),
  );
}

class AnnouncementDetailsDialog extends StatelessWidget {
  final Announcement announcement;

  const AnnouncementDetailsDialog({super.key, required this.announcement});

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    final statusColor = announcement.isPending
        ? AppTheme.amber500
        : announcement.isRejected
        ? AppTheme.red500
        : announcement.isOpen
        ? AppTheme.emerald500
        : AppTheme.slate400;
    final statusLabel = announcement.isPending
        ? 'Pending Approval'
        : announcement.isRejected
        ? 'Rejected'
        : announcement.isOpen
        ? 'Open'
        : 'Closed';

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: isMobile ? double.infinity : 560,
        constraints: BoxConstraints(
          maxWidth: isMobile ? 380 : 560,
          maxHeight:
              MediaQuery.of(context).size.height * (isMobile ? 0.78 : 0.85),
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.14),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppTheme.maroon, AppTheme.maroonDark],
                ),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.campaign_outlined,
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'Announcement Details',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'View the full announcement information.',
                          style: TextStyle(fontSize: 12, color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              fit: FlexFit.loose,
              child: SingleChildScrollView(
                padding: EdgeInsets.all(isMobile ? 18 : 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      announcement.title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.slate900,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        Icon(
                          Icons.person_outline_rounded,
                          size: 14,
                          color: AppTheme.slate400,
                        ),
                        Text(
                          announcement.postedBy,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.slate400,
                          ),
                        ),
                        Text(
                          announcement.postedAt,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.slate400,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Text(
                      announcement.body,
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppTheme.slate700,
                        height: 1.7,
                      ),
                    ),
                    if (announcement.requirements.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      const Text(
                        'Requirements',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.slate500,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: announcement.requirements
                            .map((req) => RequirementChip(label: req))
                            .toList(),
                      ),
                    ],
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        if (announcement.officeName != null)
                          _Chip(
                            Icons.apartment_rounded,
                            announcement.officeName!,
                            AppTheme.maroon,
                          ),
                        if (announcement.deadline != null)
                          _Chip(
                            Icons.event_rounded,
                            'Due ${announcement.deadline!}',
                            AppTheme.amber500,
                          ),
                        if (announcement.slots != null)
                          _Chip(
                            Icons.people_rounded,
                            '${announcement.slots} slots',
                            AppTheme.blue500,
                          ),
                        _Chip(Icons.info_rounded, statusLabel, statusColor),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                isMobile ? 18 : 24,
                0,
                isMobile ? 18 : 24,
                isMobile ? 18 : 24,
              ),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.maroon,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Close',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AnnouncementDialog extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Widget> fields;
  final Widget submitButton;
  final VoidCallback? onClose;

  const AnnouncementDialog({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.fields,
    required this.submitButton,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 500,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppTheme.maroon, AppTheme.maroonDark],
                ),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: onClose ?? () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                        size: 15,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: fields,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: SizedBox(width: double.infinity, child: submitButton),
            ),
          ],
        ),
      ),
    );
  }
}

class AnnouncementTextField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final IconData icon;
  final int maxLines;

  const AnnouncementTextField({
    super.key,
    required this.label,
    required this.controller,
    required this.icon,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: AppTheme.maroon, size: 17),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppTheme.slate200),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppTheme.slate200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppTheme.maroon, width: 1.5),
        ),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
      ),
    );
  }
}

class RequirementChip extends StatelessWidget {
  final String label;

  const RequirementChip({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.maroon.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.maroon.withValues(alpha: 0.2)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: AppTheme.maroon,
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String label;

  const _StatusBadge({
    required this.color,
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _Chip(this.icon, this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}