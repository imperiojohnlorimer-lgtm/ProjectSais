import 'dart:math';

final _random = Random.secure();
const _letters = 'abcdefghijklmnopqrstuvwxyz0123456789';

/// The name a file is stored under: random letters and digits, plus the
/// file's own extension ("x7k2q9m4t1b8w3zc.pdf"). The person's own file name
/// ("Juan-Dela-Cruz-contract.pdf") stays on their record for display and is
/// never part of the storage path, where it would show up in links, function
/// logs and the storage dashboard.
String randomObjectName(String originalName, {Random? random}) {
  final source = random ?? _random;
  final dot = originalName.lastIndexOf('.');
  final raw = dot < 0 ? '' : originalName.substring(dot + 1).toLowerCase();
  // Only an ordinary extension survives (letters and digits, short).
  final extension = RegExp(r'^[a-z0-9]{1,5}$').hasMatch(raw) ? '.$raw' : '';
  final name = String.fromCharCodes([
    for (var i = 0; i < 16; i++)
      _letters.codeUnitAt(source.nextInt(_letters.length)),
  ]);
  return '$name$extension';
}
