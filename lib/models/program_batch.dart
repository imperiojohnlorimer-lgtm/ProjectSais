import 'models.dart';

// Adding several programs at once: what one row of the form holds, how a
// pasted list becomes rows, and the checks made before anything is saved.

/// The most programs one "Add" saves (one atomic write, well under
/// Firestore's 500 per batch).
const maxProgramRows = 50;

/// One row of the Add Program form.
typedef ProgramRow = ({String code, String name});

/// A row with nothing typed in it is skipped, not an error.
bool programRowIsEmpty(ProgramRow row) =>
    row.code.trim().isEmpty && row.name.trim().isEmpty;

/// What is wrong with each of [rows] (null when nothing is), in the same
/// order, judged against the [existing] programs. Codes are compared ignoring
/// case across the whole list, since a student's profile keeps only the code.
/// A code is flagged when another program has it already, then when an
/// earlier row in this list does; the existing-program message names that
/// program the way the one-at-a-time form always did.
List<String?> planProgramBatch(
  List<ProgramRow> rows,
  Iterable<Program> existing,
) {
  final byCode = <String, Program>{};
  for (final p in existing) {
    final key = p.code.trim().toLowerCase();
    if (key.isNotEmpty) byCode.putIfAbsent(key, () => p);
  }
  // How many rows use each code, to flag every one of a repeated code.
  final uses = <String, int>{};
  for (final row in rows) {
    final key = row.code.trim().toLowerCase();
    if (key.isNotEmpty && !programRowIsEmpty(row)) {
      uses[key] = (uses[key] ?? 0) + 1;
    }
  }
  return [for (final row in rows) _problem(row, byCode, uses)];
}

String? _problem(
  ProgramRow row,
  Map<String, Program> byCode,
  Map<String, int> uses,
) {
  if (programRowIsEmpty(row)) return null;
  final code = row.code.trim();
  final name = row.name.trim();
  if (code.isEmpty || name.isEmpty) {
    return 'Fill in both the code and the name.';
  }
  final key = code.toLowerCase();
  final clash = byCode[key];
  if (clash != null) return '"${clash.code}" is already used by ${clash.name}.';
  if ((uses[key] ?? 0) > 1) return '"$code" is listed more than once here.';
  return null;
}

/// The result of reading a pasted list.
typedef ParsedPrograms = ({List<ProgramRow> rows, List<String> unreadable});

/// Reads one program per line: the code, then the name. A line with a tab (a
/// table copied from Word or Excel) is read as exactly two cells; otherwise a
/// comma or " - " splits it, whichever comes first, so a name may itself
/// contain commas and a code may contain a hyphen (`BSIT-Drafting`). Blank
/// lines are skipped; a line that does not give both a code and a name (or has
/// more than two cells) is returned in [ParsedPrograms.unreadable].
ParsedPrograms parseProgramLines(String text) {
  final rows = <ProgramRow>[];
  final unreadable = <String>[];
  for (final raw in text.split(RegExp(r'\r\n|\r|\n'))) {
    // Only the right side is trimmed: a leading tab is an empty first cell
    // (no code), not padding.
    final line = raw.trimRight();
    if (line.trim().isEmpty) continue;

    // A copied table (tabs) is split into its cells, so a comma inside a
    // cell stays in it. A row needs exactly a code cell and a name cell.
    if (line.contains('\t')) {
      final cells = [for (final cell in line.split('\t')) cell.trim()];
      if (cells.length != 2 || cells[0].isEmpty || cells[1].isEmpty) {
        unreadable.add(line.trim());
      } else {
        rows.add((code: cells[0], name: cells[1]));
      }
      continue;
    }

    final text = line.trim();
    var cut = -1;
    var width = 0;
    for (final separator in const [',', ' - ', ' – ']) {
      final at = text.indexOf(separator);
      if (at > 0 && (cut == -1 || at < cut)) {
        cut = at;
        width = separator.length;
      }
    }
    if (cut == -1) {
      unreadable.add(text);
      continue;
    }
    final code = text.substring(0, cut).trim();
    final name = text.substring(cut + width).trim();
    if (code.isEmpty || name.isEmpty) {
      unreadable.add(text);
      continue;
    }
    rows.add((code: code, name: name));
  }
  return (rows: rows, unreadable: unreadable);
}

/// How an attempt to save several programs ended.
class ProgramBatchResult {
  /// How many programs were saved (0 unless [ok]).
  final int saved;

  /// What is wrong with each submitted row, in order (null = fine). Empty
  /// when the problem is not with a row.
  final List<String?> rowErrors;

  /// A problem with the request as a whole, or null.
  final String? message;

  const ProgramBatchResult({
    this.saved = 0,
    this.rowErrors = const [],
    this.message,
  });

  bool get ok => message == null && !rowErrors.any((e) => e != null);
}
