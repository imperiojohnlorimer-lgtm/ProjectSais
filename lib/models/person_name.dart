/// A person's name in the parts the forms ask for: first, middle and last
/// name, and a suffix such as Jr. Empty strings stand for parts left out.
class PersonName {
  final String first;
  final String middle;
  final String last;
  final String suffix;

  /// Each part is trimmed and its inner spaces squeezed to one.
  PersonName({
    String first = '',
    String middle = '',
    String last = '',
    String suffix = '',
  }) : first = _clean(first),
       middle = _clean(middle),
       last = _clean(last),
       suffix = _clean(suffix);

  /// The suffixes the forms offer, in the order they're listed.
  static const suffixes = ['Jr.', 'Sr.', 'II', 'III', 'IV', 'V'];

  static String _clean(String part) =>
      part.trim().replaceAll(RegExp(r'\s+'), ' ');

  /// Whether the name has the parts every account needs.
  bool get isComplete => first.isNotEmpty && last.isNotEmpty;

  /// "S." for a middle name of Santos; empty without one.
  String get middleInitial =>
      middle.isEmpty ? '' : '${middle[0].toUpperCase()}.';

  /// How the app shows the name: "Juan S. Dela Cruz Jr.".
  String get display => [
    first,
    middleInitial,
    last,
    suffix,
  ].where((part) => part.isNotEmpty).join(' ');

  /// Surname first, as on the payroll: "Dela Cruz, Juan Jr. S.".
  String get surnameFirst {
    final given = [
      first,
      suffix,
      middleInitial,
    ].where((part) => part.isNotEmpty).join(' ');
    if (last.isEmpty) return given;
    return given.isEmpty ? last : '$last, $given';
  }

  // Words that start a surname along with the word after them, as in
  // "dela Cruz" or "de los Santos".
  static const _surnameParticles = {
    'da', 'de', 'del', 'dela', 'della', 'delos', 'des', 'di', 'du', //
    'la', 'las', 'le', 'los', 'san', 'santa', 'sta.', 'sto.', 'van', 'von',
  };

  static final _initial = RegExp(r'^\p{L}\.?$', unicode: true);

  /// A best guess at the parts of a name saved as one line, for accounts
  /// made before names were split. The last word is the surname, with any
  /// "dela"/"de los" before it; a lone initial before that is the middle
  /// name; a trailing Jr./Sr./II–IV is the suffix; the rest is the first
  /// name. A full middle name can't be told from a second first name, so
  /// it lands in the first name: someone has to check the guess.
  factory PersonName.guess(String fullName) {
    final words = fullName
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();
    var suffix = '';
    if (words.length > 2) {
      final match = suffixes.where(
        (s) =>
            s.replaceAll('.', '').toLowerCase() ==
            words.last.replaceAll('.', '').toLowerCase(),
      );
      if (match.isNotEmpty && match.first != 'V') {
        suffix = match.first;
        words.removeLast();
      }
    }
    if (words.length < 2) {
      return PersonName(first: words.join(' '), suffix: suffix);
    }

    var surnameStart = words.length - 1;
    while (surnameStart > 1 &&
        _surnameParticles.contains(words[surnameStart - 1].toLowerCase())) {
      surnameStart--;
    }
    var firstEnd = surnameStart;
    var middle = '';
    if (firstEnd > 1 && _initial.hasMatch(words[firstEnd - 1])) {
      middle = words[--firstEnd];
    }
    return PersonName(
      first: words.sublist(0, firstEnd).join(' '),
      middle: middle,
      last: words.sublist(surnameStart).join(' '),
      suffix: suffix,
    );
  }
}
