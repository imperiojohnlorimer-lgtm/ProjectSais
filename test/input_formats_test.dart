import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:projectsais/utils/input_formats.dart';

TextEditingValue _at(String text, [int? offset]) => TextEditingValue(
  text: text,
  selection: TextSelection.collapsed(offset: offset ?? text.length),
);

/// Types [keys] one at a time at the cursor, the way a keyboard would.
String _type(TextInputFormatter formatter, String keys, {String start = ''}) {
  var value = _at(start);
  for (final key in keys.split('')) {
    final at = value.selection.end;
    final typed = value.text.substring(0, at) + key + value.text.substring(at);
    value = formatter.formatEditUpdate(value, _at(typed, at + 1));
  }
  return value.text;
}

/// Replaces all of [before] with [pasted], as a paste over a selection does.
String _paste(TextInputFormatter formatter, String before, String pasted) =>
    formatter.formatEditUpdate(_at(before), _at(pasted)).text;

void main() {
  group('Phone number', () {
    final formatter = PhoneNumberFormatter();

    test('only a number starting with 09 can be typed', () {
      expect(_type(formatter, '12345678912'), '');
      expect(_type(formatter, '0817'), '0');
      expect(_type(formatter, '09ab17-'), '0917');
    });

    test('is spaced as it is typed and stops at 11 digits', () {
      expect(_type(formatter, '09171234567'), '0917 123 4567');
      expect(_type(formatter, '0917123456789'), '0917 123 4567');
    });

    test('a pasted +63 number turns into its 09 form', () {
      expect(_paste(formatter, '', '+63 917 123 4567'), '0917 123 4567');
    });

    test('a paste that is not a mobile number is refused', () {
      expect(_paste(formatter, '0917 123 4567', '123'), '0917 123 4567');
    });

    test('backspace over a space takes the digit before it', () {
      // The cursor sits just after the first space.
      final result = formatter.formatEditUpdate(
        _at('0917 123 4567', 5),
        _at('0917123 4567', 4),
      );
      expect(result.text, '0911 234 567');
      expect(result.selection.end, 3);
    });

    test('an old, wrong number can still be deleted', () {
      expect(
        formatter.formatEditUpdate(_at('12345678912'), _at('1234567891')).text,
        '1234 567 891',
      );
    });

    test('checks for a whole mobile number', () {
      expect(isValidPhoneNumber('0917 123 4567'), isTrue);
      expect(isValidPhoneNumber('09171234567'), isTrue);
      expect(isValidPhoneNumber('12345678912'), isFalse);
      expect(isValidPhoneNumber('0917 123 456'), isFalse);
    });
  });

  group('Student ID', () {
    final formatter = StudentIdFormatter();

    test('takes two digits, a letter, then four digits, in capitals', () {
      expect(_type(formatter, '23b0626'), '23B0626');
      expect(_type(formatter, '23B06267'), '23B0626');
    });

    test('ignores a keystroke that does not fit', () {
      expect(_type(formatter, '2B'), '2');
      expect(_type(formatter, '23BB'), '23B');
      expect(_type(formatter, '23-'), '23');
      expect(_type(formatter, 'ABC'), '');
    });

    test('a paste that does not fit is refused', () {
      expect(_paste(formatter, '23B0626', 'x'), '23B0626');
    });

    test('an old ID in another shape can still be deleted', () {
      expect(formatter.formatEditUpdate(_at('new1'), _at('new')).text, 'new');
    });

    test('checks for a whole ID', () {
      expect(isValidStudentId('23B0626'), isTrue);
      expect(isValidStudentId(' 23b0626 '), isTrue);
      expect(isValidStudentId('23B062'), isFalse);
      expect(isValidStudentId('new1'), isFalse);
    });
  });
}
