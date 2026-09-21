import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/app_state.dart';
import '../../models/models.dart';
import '../../services/payroll_document_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/web_download_stub.dart'
    if (dart.library.html) '../../utils/web_download.dart'
    as web_download;
import '../../widgets/shared_widgets.dart';

/// Admin form for reviewing and correcting the Hourly Wage Payroll before it
/// is printed — the payroll counterpart of the Applicant Screening form. It
/// opens on the period's saved sheet (or one freshly built from the system's
/// payroll data) and is laid out like the printed payroll: the header fields,
/// every student row grouped by campus, and signatory boxes A–D. Amounts are
/// recomputed as the Admin types; Save keeps the edits, and Download prints
/// exactly what's on screen.
class PayrollSheetEditor extends StatefulWidget {
  final PayrollSheet sheet;

  /// Rows rebuilt from the system's current payroll data, for "Reload".
  final List<PayrollSheetEntry> Function() systemEntries;
  final VoidCallback onClose;

  const PayrollSheetEditor({
    super.key,
    required this.sheet,
    required this.systemEntries,
    required this.onClose,
  });

  @override
  State<PayrollSheetEditor> createState() => _PayrollSheetEditorState();
}

class _PayrollSheetEditorState extends State<PayrollSheetEditor> {
  static const _unspecifiedCampus = 'Unspecified Campus';

  // Captions of signatory boxes A–D, as worded on the printed payroll.
  static const _signatoryCaptions = [
    'Certified: Services duly rendered as stated',
    'Certified: Supporting documents complete and proper, and cash available',
    'Approved for payment',
    'Certified: Each employee has been paid the amount indicated',
  ];

  late final TextEditingController _entityName;
  late final TextEditingController _payrollNo;
  late final TextEditingController _fundCluster;
  late final List<({TextEditingController name, TextEditingController title})>
  _signatories;
  late List<_EntryFields> _rows;

  final _dirty = ValueNotifier(false);
  bool _saving = false;
  bool _downloading = false;
  String? _savedAt;
  String? _savedBy;

  @override
  void initState() {
    super.initState();
    final sheet = widget.sheet;
    _entityName = TextEditingController(text: sheet.entityName);
    _payrollNo = TextEditingController(text: sheet.payrollNo);
    _fundCluster = TextEditingController(text: sheet.fundCluster);
    _signatories = [
      for (final s in sheet.signatories)
        (
          name: TextEditingController(text: s.name),
          title: TextEditingController(text: s.title),
        ),
    ];
    _rows = sheet.entries.map(_EntryFields.new).toList();
    _savedAt = sheet.updatedAt;
    _savedBy = sheet.updatedBy;
  }

  @override
  void dispose() {
    _entityName.dispose();
    _payrollNo.dispose();
    _fundCluster.dispose();
    for (final s in _signatories) {
      s.name.dispose();
      s.title.dispose();
    }
    for (final row in _rows) {
      row.dispose();
    }
    _dirty.dispose();
    super.dispose();
  }

  void _changed() => _dirty.value = true;

  bool get _busy => _saving || _downloading;

  PayrollSheet get _current => widget.sheet.copyWith(
    entityName: _entityName.text.trim(),
    payrollNo: _payrollNo.text.trim(),
    fundCluster: _fundCluster.text.trim(),
    entries: _rows.map((row) => row.toEntry()).toList(),
    signatories: [
      for (final s in _signatories)
        PayrollSignatory(name: s.name.text.trim(), title: s.title.text.trim()),
    ],
  );

  String _campusKey(String campus) =>
      campus.trim().isEmpty ? _unspecifiedCampus : campus.trim();

  // ─── Actions ──────────────────────────────────────────────────────────

  Future<void> _close() async {
    if (_dirty.value) {
      final discard = await showConfirmDialog(
        context,
        title: 'Discard Changes',
        message:
            'You have unsaved changes to this payroll sheet. Leave without '
            'saving them?',
        confirmLabel: 'Discard',
        confirmColor: AppTheme.red500,
      );
      if (!discard) return;
    }
    widget.onClose();
  }

  Future<void> _reload() async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Reload from System',
      message:
          'Replace every row with the latest payroll data for this period? '
          'The payroll details and signatories are kept, but changes made to '
          'the rows will be lost.',
      confirmLabel: 'Reload',
      confirmColor: AppTheme.maroon,
    );
    if (!confirmed || !mounted) return;
    final fresh = widget.systemEntries();
    setState(() {
      for (final row in _rows) {
        row.dispose();
      }
      _rows = fresh.map(_EntryFields.new).toList();
    });
    _changed();
  }

  void _addRow(List<String> campusOptions) {
    setState(() {
      _rows.add(
        _EntryFields(
          PayrollSheetEntry(
            campus: campusOptions.isEmpty ? '' : campusOptions.first,
            name: '',
          ),
          isNew: true,
        ),
      );
    });
    _changed();
  }

  Future<void> _removeRow(_EntryFields row) async {
    final name = row.name.text.trim();
    final confirmed = await showConfirmDialog(
      context,
      title: 'Remove Row',
      message: name.isEmpty
          ? 'Remove this blank row from the payroll?'
          : 'Remove $name from this payroll?',
      confirmLabel: 'Remove',
      confirmColor: AppTheme.red500,
    );
    if (!confirmed || !mounted) return;
    setState(() => _rows.remove(row));
    row.dispose();
    _changed();
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      final saved = await context.read<AppState>().savePayrollSheet(_current);
      _dirty.value = false;
      _savedAt = saved.updatedAt;
      _savedBy = saved.updatedBy;
      _snack(messenger, 'Payroll sheet saved.', AppTheme.emerald500);
    } catch (e) {
      _snack(
        messenger,
        'Could not save the payroll sheet: $e',
        AppTheme.red500,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _download() async {
    final messenger = ScaffoldMessenger.of(context);
    final sheet = _current;
    final unnamed = sheet.entries.where((e) => e.name.isEmpty).toList();
    if (unnamed.isNotEmpty) {
      _snack(
        messenger,
        'Every row needs a name — ${unnamed.length} row(s) in '
        '${_campusKey(unnamed.first.campus)} are blank.',
        AppTheme.amber500,
      );
      return;
    }

    setState(() => _downloading = true);
    try {
      final doc = await const PayrollDocumentService().generatePayroll(
        sheet: sheet,
      );
      final bytes = doc.bytes;
      if (bytes == null || bytes.isEmpty) {
        throw Exception('Failed to generate the payroll document.');
      }
      if (kIsWeb) {
        web_download.WebDownloadUtils.downloadBytes(doc.fileName, bytes);
      } else {
        final uri = Uri.dataFromBytes(
          bytes,
          mimeType:
              'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
          parameters: {'filename': doc.fileName},
        );
        final opened = await launchUrl(uri, mode: LaunchMode.platformDefault);
        if (!opened) {
          throw Exception('The browser could not open the document.');
        }
      }
      _snack(
        messenger,
        '${kIsWeb ? 'Downloading' : 'Opening'} ${doc.fileName}...',
        AppTheme.emerald500,
      );
    } catch (e) {
      _snack(messenger, 'Could not generate the payroll: $e', AppTheme.red500);
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  void _snack(ScaffoldMessengerState messenger, String message, Color color) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  // ─── Layout ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 700;
    final hPad = isMobile ? 16.0 : 28.0;
    final campusOptions = {
      ...context.watch<AppState>().campuses,
      for (final row in _rows)
        if (row.campus.trim().isNotEmpty) row.campus.trim(),
    }.toList()..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(hPad - 8, 16, hPad, 0),
          child: Row(
            children: [
              IconButton(
                onPressed: _close,
                icon: const Icon(Icons.arrow_back_rounded),
                color: AppTheme.slate700,
                tooltip: 'Back to Payroll',
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Payroll Sheet',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.slate900,
                        letterSpacing: -0.3,
                      ),
                    ),
                    Text(
                      _savedAt == null
                          ? '${widget.sheet.periodLabel} · not saved yet'
                          : '${widget.sheet.periodLabel} · saved '
                                '${_savedDate(_savedAt!)}'
                                '${_savedBy == null ? '' : ' by $_savedBy'}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppTheme.slate400,
                      ),
                    ),
                  ],
                ),
              ),
              ValueListenableBuilder<bool>(
                valueListenable: _dirty,
                builder: (_, dirty, _) => dirty
                    ? Container(
                        margin: const EdgeInsets.only(left: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.amber50,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          'Unsaved',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.amber500,
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _officialHeader(isMobile),
                const SizedBox(height: 18),
                _section(
                  1,
                  Icons.receipt_long_outlined,
                  'Payroll Details',
                  _detailFields(isMobile),
                  isMobile: isMobile,
                ),
                const SizedBox(height: 18),
                _section(
                  2,
                  Icons.groups_2_outlined,
                  'Payroll Entries',
                  _entryList(campusOptions),
                  trailing: _totalChip(),
                  isMobile: isMobile,
                ),
                const SizedBox(height: 18),
                _section(
                  3,
                  Icons.draw_outlined,
                  'Signatories',
                  _signatoryFields(isMobile),
                  isMobile: isMobile,
                ),
                const SizedBox(height: 20),
                _actions(isMobile),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _officialHeader(bool isMobile) {
    return Container(
      padding: EdgeInsets.all(isMobile ? 16 : 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.slate200),
        boxShadow: [
          BoxShadow(
            color: AppTheme.slate900.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AppLogo(size: isMobile ? 44 : 56),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'MARINDUQUE STATE UNIVERSITY',
                      style: TextStyle(
                        fontSize: isMobile ? 14.5 : 18,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.slate900,
                        letterSpacing: -0.3,
                      ),
                    ),
                    Text(
                      isMobile
                          ? 'OFFICE OF THE VP FOR STUDENT AFFAIRS & SERVICES'
                          : 'OFFICE OF THE VICE PRESIDENT FOR STUDENT AFFAIRS & SERVICES',
                      style: TextStyle(
                        fontSize: isMobile ? 9.5 : 10.5,
                        color: AppTheme.maroon,
                        fontWeight: FontWeight.w800,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: isMobile ? 14 : 18),
          Container(height: 1, color: AppTheme.slate200),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.maroon50,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              'HOURLY WAGE PAYROLL',
              style: TextStyle(
                fontSize: isMobile ? 11.5 : 13.5,
                fontWeight: FontWeight.w800,
                color: AppTheme.maroon,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(
    int number,
    IconData icon,
    String title,
    Widget child, {
    Widget? trailing,
    required bool isMobile,
  }) {
    return Container(
      padding: EdgeInsets.all(isMobile ? 14 : 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.slate200),
        boxShadow: [
          BoxShadow(
            color: AppTheme.slate900.withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: AppTheme.maroon,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    '$number',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Icon(icon, size: 16, color: AppTheme.maroon),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.slate900,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  /// Lays [fields] out [columns] to a row, each field the same width.
  Widget _grid(int columns, List<Widget> fields) =>
      _spanGrid(columns, [for (final field in fields) (field, 1)]);

  /// Like [_grid], but each field spans the given number of columns.
  Widget _spanGrid(int columns, List<(Widget, int)> fields) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Floored so a full row of fields never rounds past the edge and
        // wraps early.
        final width = ((constraints.maxWidth - (columns - 1) * 12) / columns)
            .floorToDouble();
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final (field, span) in fields)
              SizedBox(width: width * span + 12 * (span - 1), child: field),
          ],
        );
      },
    );
  }

  Widget _detailFields(bool isMobile) {
    return _grid(isMobile ? 1 : 3, [
      _input('Entity Name', _entityName),
      _input(
        'Payroll No.',
        _payrollNo,
        hint: 'Leave blank to print a blank line',
      ),
      _input(
        'Fund Cluster',
        _fundCluster,
        hint: 'Leave blank to print a blank line',
      ),
    ]);
  }

  Widget _totalChip() {
    return ListenableBuilder(
      listenable: Listenable.merge([for (final row in _rows) row.amounts]),
      builder: (context, _) {
        final total = _current.totalNetPay;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: AppTheme.emerald50,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '₱${_money(total)}',
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: AppTheme.emerald500,
            ),
          ),
        );
      },
    );
  }

  /// Every row, grouped by campus in the order the printed payroll uses, so
  /// the numbers here match the numbers on the document.
  Widget _entryList(List<String> campusOptions) {
    final groups = <String, List<_EntryFields>>{};
    for (final row in _rows) {
      groups.putIfAbsent(_campusKey(row.campus), () => []).add(row);
    }
    var number = 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Amounts update as you type: Total = hours × rate, Gross = Total − '
          'undertime, Net Pay = Gross − taxes − SSS.',
          style: TextStyle(fontSize: 11.5, color: AppTheme.slate500),
        ),
        const SizedBox(height: 12),
        if (_rows.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 28),
            alignment: Alignment.center,
            child: const Text(
              'No rows yet. Add one, or reload from the system.',
              style: TextStyle(fontSize: 13, color: AppTheme.slate400),
            ),
          ),
        // One flat list, so a row keeps its fields when it moves campus.
        for (final campus in groups.keys.toList()..sort()) ...[
          Padding(
            key: ValueKey('campus-$campus'),
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Text(
              '${campus.toUpperCase()} · ${groups[campus]!.length}',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: AppTheme.maroon,
                letterSpacing: 0.6,
              ),
            ),
          ),
          for (final row in groups[campus]!)
            _entryCard(row, ++number, campusOptions),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _busy ? null : () => _addRow(campusOptions),
            icon: const Icon(Icons.add_rounded, size: 16),
            label: const Text('Add Row'),
            style: TextButton.styleFrom(foregroundColor: AppTheme.maroon),
          ),
        ),
      ],
    );
  }

  Widget _entryCard(_EntryFields row, int number, List<String> campusOptions) {
    return Container(
      key: row.key,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.slate200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: const BoxDecoration(
                  color: AppTheme.maroon50,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '$number',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.maroon,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: _input('Name', row.name, autofocus: row.isNew)),
              IconButton(
                onPressed: _busy ? null : () => _removeRow(row),
                icon: const Icon(Icons.delete_outline_rounded, size: 20),
                color: AppTheme.slate400,
                tooltip: 'Remove from payroll',
              ),
            ],
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 860
                  ? 5
                  : constraints.maxWidth >= 540
                  ? 3
                  : 2;
              // Campus, designation and remarks hold words rather than
              // figures, so they widen whenever a row has room to spare;
              // every row of the grid still fills exactly.
              return _spanGrid(columns, [
                (
                  DropdownButtonFormField<String>(
                    initialValue: row.campus.trim().isEmpty
                        ? null
                        : row.campus.trim(),
                    isExpanded: true,
                    decoration: _decoration('Campus'),
                    items: campusOptions
                        .map(
                          (c) => DropdownMenuItem(
                            value: c,
                            child: Text(c, overflow: TextOverflow.ellipsis),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      setState(() => row.campus = value ?? '');
                      _changed();
                    },
                  ),
                  columns == 2 ? 2 : 1,
                ),
                (_input('Designation', row.designation), columns == 5 ? 1 : 2),
                (_numberInput('Hours Worked', row.hours), 1),
                (_numberInput('Rate per Hour (₱)', row.rate), 1),
                (
                  _numberInput(
                    'Undertime Hrs',
                    row.undertimeHours,
                    whole: true,
                  ),
                  1,
                ),
                (
                  _numberInput(
                    'Undertime Mins',
                    row.undertimeMinutes,
                    whole: true,
                  ),
                  1,
                ),
                (_numberInput('Taxes Withheld (₱)', row.taxes), 1),
                (_numberInput('SSS (₱)', row.sss), 1),
                (_input('Remarks', row.remarks), columns == 5 ? 2 : columns),
              ]);
            },
          ),
          const SizedBox(height: 10),
          ListenableBuilder(
            listenable: row.amounts,
            builder: (context, _) {
              final entry = row.toEntry();
              return Wrap(
                spacing: 16,
                runSpacing: 4,
                children: [
                  _amount('Total', entry.totalAmount),
                  _amount('Undertime', entry.undertimeAmount),
                  _amount('Gross', entry.grossAmount),
                  _amount('Net Pay', entry.netPay, strong: true),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _amount(String label, double value, {bool strong = false}) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$label ',
            style: const TextStyle(color: AppTheme.slate400),
          ),
          TextSpan(
            text: '₱${_money(value)}',
            style: TextStyle(
              fontWeight: strong ? FontWeight.w800 : FontWeight.w700,
              color: strong ? AppTheme.maroon : AppTheme.slate700,
            ),
          ),
        ],
      ),
      style: const TextStyle(fontSize: 12),
    );
  }

  Widget _signatoryFields(bool isMobile) {
    const boxes = ['A', 'B', 'C', 'D'];
    return _grid(isMobile ? 1 : 2, [
      for (var i = 0; i < _signatories.length; i++)
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.slate200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: AppTheme.maroon50,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Center(
                      child: Text(
                        boxes[i],
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.maroon,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _signatoryCaptions[i],
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.slate600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _input('Printed Name', _signatories[i].name),
              const SizedBox(height: 10),
              _input('Position', _signatories[i].title),
            ],
          ),
        ),
    ]);
  }

  Widget _actions(bool isMobile) {
    final spinner = const SizedBox(
      width: 13,
      height: 13,
      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
    );
    final download = FilledButton.icon(
      onPressed: _busy || _rows.isEmpty ? null : _download,
      icon: _downloading
          ? spinner
          : const Icon(Icons.download_rounded, size: 15),
      label: Text(_downloading ? 'Preparing...' : 'Download Payroll'),
      style: FilledButton.styleFrom(
        backgroundColor: AppTheme.maroon,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
    final save = OutlinedButton.icon(
      onPressed: _busy ? null : _save,
      icon: _saving
          ? const SizedBox(
              width: 13,
              height: 13,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppTheme.maroon,
              ),
            )
          : const Icon(Icons.save_outlined, size: 15),
      label: Text(_saving ? 'Saving...' : 'Save Sheet'),
      style: _outlineStyle,
    );
    final reload = OutlinedButton.icon(
      onPressed: _busy ? null : _reload,
      icon: const Icon(Icons.refresh_rounded, size: 15),
      label: const Text('Reload from System'),
      style: _outlineStyle,
    );
    final back = TextButton(
      onPressed: _close,
      child: const Text('Back to Payroll'),
    );

    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          download,
          const SizedBox(height: 10),
          save,
          const SizedBox(height: 10),
          reload,
          const SizedBox(height: 4),
          back,
        ],
      );
    }
    return Wrap(
      alignment: WrapAlignment.end,
      spacing: 8,
      runSpacing: 8,
      children: [back, reload, save, download],
    );
  }

  static final _outlineStyle = OutlinedButton.styleFrom(
    foregroundColor: AppTheme.maroon,
    side: const BorderSide(color: AppTheme.maroon200),
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
  );

  InputDecoration _decoration(String label, {String? hint}) => InputDecoration(
    labelText: label,
    hintText: hint,
    hintStyle: const TextStyle(fontSize: 12, color: AppTheme.slate400),
    isDense: true,
    filled: true,
    fillColor: AppTheme.slate50,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide.none,
    ),
  );

  Widget _input(
    String label,
    TextEditingController controller, {
    String? hint,
    bool autofocus = false,
  }) => TextField(
    controller: controller,
    autofocus: autofocus,
    decoration: _decoration(label, hint: hint),
    onChanged: (_) => _changed(),
  );

  Widget _numberInput(
    String label,
    TextEditingController controller, {
    bool whole = false,
  }) => TextField(
    controller: controller,
    keyboardType: TextInputType.numberWithOptions(decimal: !whole),
    inputFormatters: [
      FilteringTextInputFormatter.allow(
        whole ? RegExp(r'[0-9]') : RegExp(r'[0-9.,]'),
      ),
    ],
    decoration: _decoration(label),
    onChanged: (_) => _changed(),
  );

  static String _savedDate(String iso) {
    final date = DateTime.tryParse(iso)?.toLocal();
    if (date == null) return iso;
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}

/// 2000 → "2,000.00".
String _money(double value) {
  final fixed = value.toStringAsFixed(2);
  final dot = fixed.indexOf('.');
  final negative = fixed.startsWith('-');
  final digits = fixed.substring(negative ? 1 : 0, dot);
  final grouped = digits.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  return '${negative ? '-' : ''}$grouped${fixed.substring(dot)}';
}

double _parse(String text) =>
    double.tryParse(text.replaceAll(',', '').trim()) ?? 0;

/// 80 → "80", 81.5 → "81.5".
String _plain(double value) =>
    value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');

/// The text fields behind one editable payroll row.
class _EntryFields {
  _EntryFields(PayrollSheetEntry entry, {this.isNew = false})
    : studentId = entry.studentId,
      campus = entry.campus,
      name = TextEditingController(text: entry.name),
      designation = TextEditingController(text: entry.designation),
      hours = TextEditingController(text: _plain(entry.hoursWorked)),
      rate = TextEditingController(text: entry.ratePerHour.toStringAsFixed(2)),
      undertimeHours = TextEditingController(text: '${entry.undertimeHours}'),
      undertimeMinutes = TextEditingController(
        text: '${entry.undertimeMinutes}',
      ),
      taxes = TextEditingController(text: _plain(entry.taxesWithheld)),
      sss = TextEditingController(text: _plain(entry.sss)),
      remarks = TextEditingController(text: entry.remarks);

  final Key key = UniqueKey();

  /// A row just added by hand, whose name field takes focus.
  final bool isNew;
  final String studentId;
  String campus;
  final TextEditingController name;
  final TextEditingController designation;
  final TextEditingController hours;
  final TextEditingController rate;
  final TextEditingController undertimeHours;
  final TextEditingController undertimeMinutes;
  final TextEditingController taxes;
  final TextEditingController sss;
  final TextEditingController remarks;

  /// Fires when a field that changes this row's amounts is edited.
  late final Listenable amounts = Listenable.merge([
    hours,
    rate,
    undertimeHours,
    undertimeMinutes,
    taxes,
    sss,
  ]);

  PayrollSheetEntry toEntry() => PayrollSheetEntry(
    studentId: studentId,
    campus: campus.trim(),
    name: name.text.trim(),
    designation: designation.text.trim(),
    hoursWorked: _parse(hours.text),
    ratePerHour: _parse(rate.text),
    undertimeHours: _parse(undertimeHours.text).toInt(),
    undertimeMinutes: _parse(undertimeMinutes.text).toInt(),
    taxesWithheld: _parse(taxes.text),
    sss: _parse(sss.text),
    remarks: remarks.text.trim(),
  );

  void dispose() {
    for (final controller in [
      name,
      designation,
      hours,
      rate,
      undertimeHours,
      undertimeMinutes,
      taxes,
      sss,
      remarks,
    ]) {
      controller.dispose();
    }
  }
}
