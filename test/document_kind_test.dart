import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:projectsais/services/supabase_storage_service.dart';
import 'package:projectsais/utils/document_kind.dart';

Uint8List _zip(Map<String, List<int>> files) {
  final archive = Archive();
  files.forEach(
    (name, bytes) => archive.add(ArchiveFile(name, bytes.length, bytes)),
  );
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

final _png = Uint8List.fromList([
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0,
  0,
]);
final _jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0, 0x10]);
final _pdf = Uint8List.fromList(ascii.encode('%PDF-1.7\n1 0 obj\n'));

final _docx = _zip({
  '[Content_Types].xml': ascii.encode('<Types/>'),
  'word/document.xml': ascii.encode('<w:document/>'),
});

void main() {
  group('documentKindForName', () {
    test('goes by the extension, whatever the case', () {
      expect(documentKindForName('Resume.PDF'), DocumentKind.pdf);
      expect(documentKindForName('photo.jpeg'), DocumentKind.image);
      expect(documentKindForName('photo.JPG'), DocumentKind.image);
      expect(documentKindForName('id.png'), DocumentKind.image);
      expect(documentKindForName('cv.docx'), DocumentKind.docx);
    });

    test('the old .doc and anything else cannot be previewed', () {
      expect(documentKindForName('cv.doc'), DocumentKind.other);
      expect(documentKindForName('notes.txt'), DocumentKind.other);
      expect(documentKindForName('noextension'), DocumentKind.other);
      expect(documentKindForName('archive.pdf.exe'), DocumentKind.other);
    });
  });

  group('documentProblem', () {
    test('accepts files that are what their name says', () {
      expect(documentProblem(DocumentKind.image, _png), isNull);
      expect(documentProblem(DocumentKind.image, _jpeg), isNull);
      expect(documentProblem(DocumentKind.pdf, _pdf), isNull);
      expect(documentProblem(DocumentKind.docx, _docx), isNull);
    });

    test('a PDF may have a little before its header', () {
      final padded = Uint8List.fromList([...List.filled(200, 0x20), ..._pdf]);
      expect(documentProblem(DocumentKind.pdf, padded), isNull);
    });

    test('refuses a file that is not what its name says', () {
      expect(documentProblem(DocumentKind.image, _pdf), contains('picture'));
      expect(documentProblem(DocumentKind.pdf, _png), contains('PDF'));
      expect(
        documentProblem(
          DocumentKind.pdf,
          Uint8List.fromList(ascii.encode('<html><script>x</script>')),
        ),
        contains('PDF'),
      );
      expect(documentProblem(DocumentKind.docx, _pdf), contains('Word'));
    });

    test('refuses an empty or oversized file', () {
      expect(
        documentProblem(DocumentKind.pdf, Uint8List(0)),
        contains('empty'),
      );
      expect(
        documentProblem(DocumentKind.image, Uint8List(maxPreviewBytes + 1)),
        contains('too large'),
      );
    });

    test(
      'says why a Word file in the old or protected format cannot be shown',
      () {
        final ole = Uint8List.fromList([
          0xD0,
          0xCF,
          0x11,
          0xE0,
          0xA1,
          0xB1,
          0x1A,
          0xE1,
        ]);
        expect(
          documentProblem(DocumentKind.docx, ole),
          contains('password-protected'),
        );
      },
    );

    test('a damaged zip or a zip that is not a Word package is refused', () {
      final damaged = Uint8List.fromList([
        0x50,
        0x4B,
        0x03,
        0x04,
        1,
        2,
        3,
        4,
        5,
        6,
      ]);
      expect(documentProblem(DocumentKind.docx, damaged), isNotNull);
      final other = _zip({'hello.txt': ascii.encode('hi')});
      expect(documentProblem(DocumentKind.docx, other), contains('Word'));
      final noBody = _zip({'[Content_Types].xml': ascii.encode('<Types/>')});
      expect(documentProblem(DocumentKind.docx, noBody), contains('Word'));
    });

    test('a Word package with too many parts is refused', () {
      final many = <String, List<int>>{
        '[Content_Types].xml': ascii.encode('<Types/>'),
        'word/document.xml': ascii.encode('<w:document/>'),
        for (var i = 0; i < 600; i++) 'word/media/$i.xml': const [1],
      };
      expect(
        documentProblem(DocumentKind.docx, _zip(many)),
        contains('too complex'),
      );
    });

    test('a Word package that inflates enormously is refused', () {
      final bomb = _zip({
        '[Content_Types].xml': ascii.encode('<Types/>'),
        'word/document.xml': List.filled(26 * 1024 * 1024, 0),
      });
      expect(bomb.length, lessThan(maxPreviewBytes));
      expect(documentProblem(DocumentKind.docx, bomb), contains('too large'));
    });

    test('other kinds are never previewed', () {
      expect(
        documentProblem(DocumentKind.other, _png),
        contains("can't be previewed"),
      );
    });
  });

  group('which links the app will fetch itself', () {
    test('only signed links into our own Documents bucket', () {
      const host = 'hksswjhioztqsypbrkjy.supabase.co';
      expect(
        SupabaseStorageService.isStorageSignedUrl(
          Uri.parse(
            'https://$host/storage/v1/object/sign/Documents/applications/a/b.pdf?token=t',
          ),
        ),
        isTrue,
      );
      for (final url in [
        'http://$host/storage/v1/object/sign/Documents/a.pdf?token=t',
        'https://evil.example.com/storage/v1/object/sign/Documents/a.pdf?token=t',
        'https://$host.evil.example.com/storage/v1/object/sign/Documents/a.pdf',
        'https://$host/storage/v1/object/sign/Other/a.pdf?token=t',
        'https://$host/storage/v1/object/public/Documents/a.pdf',
        'https://example.com/resume.pdf',
        'data:application/pdf;base64,AAAA',
      ]) {
        expect(
          SupabaseStorageService.isStorageSignedUrl(Uri.parse(url)),
          isFalse,
          reason: url,
        );
      }
    });
  });

  group('readCapped', () {
    http.StreamedResponse response(List<List<int>> chunks, {int? length}) =>
        http.StreamedResponse(
          Stream.fromIterable(chunks),
          200,
          contentLength: length,
        );

    test('returns the whole body when it fits', () async {
      final bytes = await SupabaseStorageService.readCapped(
        response([
          [1, 2],
          [3],
        ], length: 3),
        maxBytes: 10,
      );
      expect(bytes, [1, 2, 3]);
    });

    test('gives up on a declared size over the cap, before reading', () async {
      await expectLater(
        SupabaseStorageService.readCapped(
          response([
            [1],
          ], length: 11),
          maxBytes: 10,
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test(
      'gives up when the body outgrows the cap whatever it declared',
      () async {
        await expectLater(
          SupabaseStorageService.readCapped(
            response([List.filled(6, 0), List.filled(6, 0)]),
            maxBytes: 10,
          ),
          throwsA(isA<FormatException>()),
        );
      },
    );
  });
}
