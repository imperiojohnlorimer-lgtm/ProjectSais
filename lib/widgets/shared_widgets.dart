import 'dart:convert';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

// ─── Avatar Widget ──────────────────────────────────
class UserAvatar extends StatelessWidget {
  final String? avatarUrl;
  final String initials;
  final double size;

  const UserAvatar({
    super.key,
    this.avatarUrl,
    required this.initials,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.maroonLight, AppTheme.maroonDark],
        ),
        border: Border.all(color: AppTheme.gold300, width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: avatarUrl != null && avatarUrl!.isNotEmpty
          ? (avatarUrl!.startsWith('data:image')
                ? _buildDataImage(avatarUrl!)
                : Image.network(
                    avatarUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _initials(),
                  ))
          : _initials(),
    );
  }

  Widget _buildDataImage(String dataUrl) {
    try {
      final prefixEnd = dataUrl.indexOf(',');
      if (prefixEnd < 0) return _initials();
      final payload = dataUrl
          .substring(prefixEnd + 1)
          .replaceAll(RegExp(r'\s+'), '');
      if (payload.isEmpty) return _initials();
      final bytes = base64Decode(payload);
      if (bytes.isEmpty) return _initials();
      return Image.memory(
        bytes,
        width: size,
        height: size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => _initials(),
      );
    } catch (_) {
      return _initials();
    }
  }

  Widget _initials() => Center(
    child: Text(
      initials,
      style: TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w700,
        fontSize: size * 0.33,
      ),
    ),
  );
}

// ─── Logo Widget ────────────────────────────────────
class AppLogo extends StatelessWidget {
  final double size;
  final BoxBorder? border;
  final List<BoxShadow>? shadow;

  const AppLogo({super.key, this.size = 52, this.border, this.shadow});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: border ?? Border.all(color: AppTheme.gold400, width: 2),
        boxShadow:
            shadow ??
            [
              BoxShadow(
                color: AppTheme.maroon.withValues(alpha: 0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.asset('assets/images/logo.jpg', fit: BoxFit.cover),
    );
  }
}

// ─── Status Badge ───────────────────────────────────
class StatusBadge extends StatelessWidget {
  final String label;
  final Color bgColor;
  final Color textColor;

  const StatusBadge({
    super.key,
    required this.label,
    required this.bgColor,
    required this.textColor,
  });

  factory StatusBadge.fromStatus(String status) {
    switch (status) {
      case 'Active':
      case 'Approved':
      case 'Completed':
        return StatusBadge(
          label: status,
          bgColor: AppTheme.emerald50,
          textColor: AppTheme.emerald500,
        );
      case 'Pending':
      case 'In Progress':
      case 'Not Started':
        return StatusBadge(
          label: status,
          bgColor: AppTheme.amber50,
          textColor: AppTheme.amber500,
        );
      case 'Rejected':
      case 'Inactive':
        return StatusBadge(
          label: status,
          bgColor: AppTheme.red50,
          textColor: AppTheme.red500,
        );
      case 'On Duty':
        return StatusBadge(
          label: status,
          bgColor: AppTheme.maroon100,
          textColor: AppTheme.maroon,
        );
      default:
        return StatusBadge(
          label: status,
          bgColor: AppTheme.slate100,
          textColor: AppTheme.slate600,
        );
    }
  }

  factory StatusBadge.fromPriority(String priority) {
    switch (priority) {
      case 'High':
        return StatusBadge(
          label: priority,
          bgColor: AppTheme.red50,
          textColor: AppTheme.red500,
        );
      case 'Medium':
        return StatusBadge(
          label: priority,
          bgColor: AppTheme.amber50,
          textColor: AppTheme.amber500,
        );
      case 'Low':
        return StatusBadge(
          label: priority,
          bgColor: AppTheme.blue50,
          textColor: AppTheme.blue500,
        );
      default:
        return StatusBadge(
          label: priority,
          bgColor: AppTheme.slate100,
          textColor: AppTheme.slate600,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontWeight: FontWeight.w600,
          fontSize: 11,
        ),
      ),
    );
  }
}

// ─── Section Header ─────────────────────────────────
class SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? action;

  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.slate900,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.slate500,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (action != null) action!,
      ],
    );
  }
}

// ─── Empty State ────────────────────────────────────
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;

  const EmptyState({super.key, required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppTheme.slate100,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 32, color: AppTheme.slate300),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: const TextStyle(
                color: AppTheme.slate400,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Primary Button ─────────────────────────────────
class PrimaryButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback onTap;
  final bool isLoading;

  const PrimaryButton({
    super.key,
    required this.label,
    this.icon,
    required this.onTap,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: isLoading ? null : onTap,
        child: isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 18),
                    const SizedBox(width: 8),
                  ],
                  Text(label),
                ],
              ),
      ),
    );
  }
}

// ─── Confirm Dialog ─────────────────────────────────
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  Color? confirmColor,
}) async {
  return await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
          ),
          content: Text(
            message,
            style: const TextStyle(color: AppTheme.slate600, fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text(
                'Cancel',
                style: TextStyle(color: AppTheme.slate500),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: confirmColor ?? AppTheme.red500,
              ),
              child: Text(confirmLabel),
            ),
          ],
        ),
      ) ??
      false;
}

// ─── Stat Card ──────────────────────────────────────
class StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? accentColor;

  const StatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final accent = accentColor ?? AppTheme.maroon;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.slate200, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  accent.withValues(alpha: 0.16),
                  accent.withValues(alpha: 0.06),
                ],
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: accent.withValues(alpha: 0.28),
                width: 1.3,
              ),
            ),
            child: Icon(icon, size: 21, color: accent),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.slate900,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppTheme.slate500,
                    fontWeight: FontWeight.w600,
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

/// True on layouts without a hover pointer, where hover-revealed controls
/// have to stay visible.
bool isTouchLayout(BuildContext context) =>
    MediaQuery.of(context).size.width < 700;

// ─── Hero Banner ────────────────────────────────────
/// One stat inside a [HeroBanner].
class HeroStatData {
  final String label;
  final String value;
  final IconData icon;

  const HeroStatData({
    required this.label,
    required this.value,
    required this.icon,
  });
}

/// Maroon gradient page header: title, stat chips, a search field and a
/// primary action, used at the top of the management screens.
/// Page header used at the top of the management screens: title on the left,
/// compact figures beside it, and a single toolbar row holding the search
/// field with any filter controls. Deliberately light — no colour panel and
/// no full-width stacked bars.
class HeroBanner extends StatelessWidget {
  final bool isMobile;
  final IconData icon;
  final String title;
  final String subtitle;

  /// Optional primary action; screens without one leave both null.
  final String? addLabel;

  /// Search box; screens without one (a calendar, say) leave both null.
  final String? searchHint;
  final VoidCallback? onAdd;
  final ValueChanged<String>? onSearch;
  final List<HeroStatData> stats;

  /// Extra controls placed beside the search field, such as dropdowns.
  final List<Widget> filters;

  const HeroBanner({
    super.key,
    required this.isMobile,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.addLabel,
    this.searchHint,
    this.onAdd,
    this.onSearch,
    required this.stats,
    this.filters = const [],
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        // Below this the figures move under the title instead of sitting
        // beside it.
        final stacked = width < 760;
        final hasAdd = onAdd != null && addLabel != null;

        final addButton = ElevatedButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add_rounded, size: 18),
          label: Text(addLabel ?? ''),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.maroon,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        );

        final titleBlock = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 3,
              height: 32,
              margin: const EdgeInsets.only(top: 3),
              decoration: BoxDecoration(
                color: AppTheme.maroon,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 11),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 17, color: AppTheme.maroon),
                      const SizedBox(width: 7),
                      Flexible(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.slate900,
                            letterSpacing: -0.3,
                            height: 1.1,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.slate400,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );

        final metrics = Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [for (final stat in stats) _MetricChip(data: stat)],
        );

        final searchField = SizedBox(
          height: 40,
          child: TextField(
            onChanged: onSearch,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            decoration: InputDecoration(
              hintText: searchHint ?? '',
              isDense: true,
              prefixIcon: const Icon(
                Icons.search_rounded,
                size: 18,
                color: AppTheme.slate400,
              ),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
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
                borderSide: const BorderSide(
                  color: AppTheme.maroon,
                  width: 1.5,
                ),
              ),
            ),
          ),
        );

        // One toolbar: search takes the slack, filters and the action sit
        // next to it rather than on their own rows.
        final hasSearch = onSearch != null;
        final Widget toolbar;
        if (!hasSearch) {
          // No search box: the filters and action are the whole toolbar.
          toolbar = Wrap(
            spacing: 9,
            runSpacing: 9,
            children: [...filters, if (hasAdd) addButton],
          );
        } else if (width < 520) {
          toolbar = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              searchField,
              if (filters.isNotEmpty || hasAdd) ...[
                const SizedBox(height: 9),
                Wrap(
                  spacing: 9,
                  runSpacing: 9,
                  children: [...filters, if (hasAdd) addButton],
                ),
              ],
            ],
          );
        } else {
          toolbar = Row(
            children: [
              Expanded(child: searchField),
              for (final filter in filters) ...[
                const SizedBox(width: 9),
                filter,
              ],
              if (hasAdd) ...[const SizedBox(width: 9), addButton],
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (stacked) ...[
              titleBlock,
              const SizedBox(height: 12),
              metrics,
            ] else
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Flexible(child: titleBlock),
                  const SizedBox(width: 20),
                  Flexible(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: metrics,
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 14),
            toolbar,
          ],
        );
      },
    );
  }
}

/// One figure from the header, as a compact pill that hugs its content.
class _MetricChip extends StatelessWidget {
  final HeroStatData data;

  const _MetricChip({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.slate200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            data.icon,
            size: 14,
            color: AppTheme.maroon.withValues(alpha: 0.7),
          ),
          const SizedBox(width: 7),
          Text(
            data.value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppTheme.slate900,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            data.label,
            style: const TextStyle(
              fontSize: 11.5,
              color: AppTheme.slate500,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Progress Strip ─────────────────────────────────
/// Slim completion bar for page headers: a label, an animated maroon bar and
/// a count on the right. Replaces the older filled summary panels.
class ProgressStrip extends StatelessWidget {
  final String label;
  final IconData icon;
  final double progress;
  final String trailing;

  const ProgressStrip({
    super.key,
    required this.label,
    required this.progress,
    required this.trailing,
    this.icon = Icons.donut_small_rounded,
  });

  @override
  Widget build(BuildContext context) {
    final value = progress.clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.slate200),
      ),
      child: Row(
        children: [
          Icon(icon, size: 15, color: AppTheme.maroon),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: AppTheme.slate700,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                children: [
                  Container(height: 8, color: AppTheme.slate100),
                  LayoutBuilder(
                    builder: (context, constraints) =>
                        TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: value),
                          duration: const Duration(milliseconds: 500),
                          curve: Curves.easeOutCubic,
                          builder: (context, animated, _) => Container(
                            height: 8,
                            width: constraints.maxWidth * animated,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [AppTheme.maroon, AppTheme.maroonLight],
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            trailing,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: AppTheme.slate900,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '(${(value * 100).round()}%)',
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: AppTheme.slate400,
            ),
          ),
        ],
      ),
    );
  }
}
