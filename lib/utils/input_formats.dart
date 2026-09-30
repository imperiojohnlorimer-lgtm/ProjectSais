import 'package:flutter/services.dart';

/// A Philippine mobile number: 11 digits starting with "09", as in
/// 0917 123 4567. Spaces and dashes don't count.
bool isValidPhoneNumber(String phone) =>
    RegExp(r'^09\d{9}$').hasMatch(phone.replaceAll(RegExp(r'\D'), ''));

/// A MarSU Student ID: two digits, a letter, then four digits, as in
/// 23B0626. Letter case doesn't matter.
bool isValidStudentId(String id) =>
    RegExp(r'^\d{2}[A-Z]\d{4}$').hasMatch(id.trim().toUpperCase());

/// Keeps a phone field to a Philippine mobile number as it's typed: digits
/// only, starting with "09", at most 11, spaced as "09XX XXX XXXX". A pasted
/// +63 number turns into its 09 form. A keystroke that can't lead to such a
/// number is ignored, but deleting always works, so an old, wrong number
/// can still be cleared.
class PhoneNumberFormatter extends TextInputFormatter {
  static final _nonDigit = RegExp(r'\D');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final oldDigits = oldValue.text.replaceAll(_nonDigit, '');
    var digits = newValue.text.replaceAll(_nonDigit, '');
    // How many digits sit before the cursor, to put it back among them.
    final end = newValue.selection.end;
    var cursor = end < 0 || end > newValue.text.length
        ? digits.length
        : newValue.text.substring(0, end).replaceAll(_nonDigit, '').length;

    // Backspace over one of the spaces takes the digit before it, rather
    // than doing nothing once the space is put back.
    if (digits == oldDigits &&
        newValue.text.length < oldValue.text.length &&
        cursor > 0) {
      digits = digits.substring(0, cursor - 1) + digits.substring(cursor);
      cursor--;
    }
    if (digits.startsWith('639')) {
      digits = '0${digits.substring(2)}';
      cursor = cursor > 1 ? cursor - 1 : cursor;
    }

    if (!_onlyRemoves(oldDigits, digits) &&
        !RegExp(r'^(0|09\d{0,9})?$').hasMatch(digits)) {
      return oldValue;
    }

    final text = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i == 4 || i == 7) text.write(' ');
      text.write(digits[i]);
    }
    final offset = cursor + (cursor > 4 ? 1 : 0) + (cursor > 7 ? 1 : 0);
    return TextEditingValue(
      text: text.toString(),
      selection: TextSelection.collapsed(offset: offset),
    );
  }
}

/// Keeps a Student ID field to the 23B0626 shape as it's typed, in
/// capitals: a keystroke that doesn't fit is ignored. Deleting always
/// works, so an ID saved in another shape can still be corrected.
class StudentIdFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (_onlyRemoves(oldValue.text, newValue.text)) return newValue;
    final id = newValue.text.toUpperCase();
    if (!RegExp(r'^(\d{0,2}|\d{2}[A-Z]\d{0,4})$').hasMatch(id)) {
      return oldValue;
    }
    return newValue.copyWith(text: id);
  }
}

/// Whether [after] is [before] with some characters cut out and nothing
/// added: a backspace or delete, not a paste over a selection.
bool _onlyRemoves(String before, String after) {
  if (after.length >= before.length) return false;
  var same = 0;
  while (same < after.length && before[same] == after[same]) {
    same++;
  }
  return before.endsWith(after.substring(same));
}
