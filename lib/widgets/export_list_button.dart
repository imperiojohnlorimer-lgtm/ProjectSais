import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/list_print.dart';

/// The menu's two choices. (Its own type, so a test looking for a page's
/// row menus, which are PopupMenuButton<String>, never finds this one.)
enum _Export { print, csv }

/// A small outlined "Export" button beside a screen's filters. It opens a
/// menu to print what the screen lists or save it as a spreadsheet, so the
/// filters row keeps one button. Disabled while there is nothing listed.
/// Print is left out where printing isn't available (the Android app).
class ExportListButton extends StatelessWidget {
  final VoidCallback? onSaveCsv;
  final VoidCallback? onPrint;

  /// Whether to offer Print; defaults to whether this build can print.
  final bool? showPrint;

  const ExportListButton({
    super.key,
    required this.onSaveCsv,
    required this.onPrint,
    this.showPrint,
  });

  static const printLabel = 'Print';
  static const csvLabel = 'Save as spreadsheet (CSV)';

  @override
  Widget build(BuildContext context) {
    final enabled = onSaveCsv != null || onPrint != null;
    final withPrint = (showPrint ?? canPrintLists) && onPrint != null;
    return PopupMenuButton<_Export>(
      enabled: enabled,
      tooltip: enabled ? 'Print or save this list' : 'Nothing to export',
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: Colors.white,
      onSelected: (choice) {
        if (choice == _Export.print) {
          onPrint?.call();
        } else {
          onSaveCsv?.call();
        }
      },
      itemBuilder: (context) => [
        if (withPrint) _item(_Export.print, printLabel, Icons.print_rounded),
        if (onSaveCsv != null)
          _item(_Export.csv, csvLabel, Icons.table_view_rounded),
      ],
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
              Icons.ios_share_rounded,
              size: 16,
              color: enabled ? AppTheme.maroon : AppTheme.slate400,
            ),
            const SizedBox(width: 7),
            Text(
              'Export',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: enabled ? AppTheme.slate700 : AppTheme.slate400,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.arrow_drop_down_rounded,
              size: 20,
              color: enabled ? AppTheme.slate500 : AppTheme.slate400,
            ),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<_Export> _item(_Export value, String label, IconData icon) =>
      PopupMenuItem(
        value: value,
        height: 42,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17, color: AppTheme.maroon),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                label,
                maxLines: 2,
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
