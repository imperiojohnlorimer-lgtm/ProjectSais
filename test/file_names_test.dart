import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:projectsais/utils/file_names.dart';

void main() {
  group('randomObjectName', () {
    test('keeps the extension and nothing of the original name', () {
      final name = randomObjectName('Juan Dela Cruz - Contract.PDF');

      expect(name, endsWith('.pdf'));
      expect(name.toLowerCase(), isNot(contains('juan')));
      expect(name.toLowerCase(), isNot(contains('contract')));
      expect(name.length, 16 + '.pdf'.length);
    });

    test('is a safe name for the upload function', () {
      // The upload-document function only takes letters, digits, "." "_" "-".
      for (final original in [
        'a.pdf',
        'photo (1).JPG',
        "María's résumé.docx",
        'noextension',
        'strange.ext*ension',
        'x.toolongextension',
        '.hidden',
      ]) {
        expect(
          RegExp(r'^[a-zA-Z0-9._-]+$').hasMatch(randomObjectName(original)),
          isTrue,
          reason: original,
        );
      }
    });

    test('drops an extension that is not an ordinary one', () {
      expect(randomObjectName('x.toolongextension'), isNot(contains('.')));
      expect(randomObjectName('noextension'), isNot(contains('.')));
      expect(randomObjectName('a.p*f'), isNot(contains('.')));
    });

    test('is different every time', () {
      final names = {for (var i = 0; i < 50; i++) randomObjectName('a.pdf')};

      expect(names, hasLength(50));
    });

    test('can be made repeatable for a test', () {
      expect(
        randomObjectName('a.pdf', random: Random(7)),
        randomObjectName('b.pdf', random: Random(7)),
      );
    });
  });
}
