import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A small outlined button beside a screen's filters that saves what the
/// screen lists as a spreadsheet file. Disabled while there is nothing to
/// save.
class ExportCsvButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final String label;

  const ExportCsvButton({
    super.key,
    required this.onPressed,
    this.label = 'Export CSV',
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Tooltip(
      message: enabled
          ? 'Save this list as a spreadsheet (opens in Excel)'
          : 'Nothing to export',
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onPressed,
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 13),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.slate200),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.download_rounded,
                size: 16,
                color: enabled ? AppTheme.maroon : AppTheme.slate400,
              ),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: enabled ? AppTheme.slate700 : AppTheme.slate400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
