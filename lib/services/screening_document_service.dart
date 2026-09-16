import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../models/models.dart';

class ScreeningDocumentService {
  const ScreeningDocumentService();

  static const _template =
      'assets/templates/interview_assessment_form_template.docx';
  static const _skills = [
    'Communication Skills',
    'Time Management',
    'Technical Proficiency',
    'Initiative & Problem-Solving',
    'Professionalism & Work Ethic',
    'Adaptability & Learning Ability',
    'Teamwork & Collaboration',
  ];
  static const _overall = [
    'Suitability for the Role',
    'Enthusiasm & Motivation',
    'Potential for Growth',
    'Overall Impression',
  ];

  Future<ApplicationDocument> generateScreeningResult({
    required ScreeningRecord record,
    String? academicYear,
    Uint8List? photoBytes,
    String? photoExtension,
  }) async {
    final template = (await rootBundle.load(_template)).buffer.asUint8List();
    final replacements = <String, String>{
      '{{ACADEMIC_YEAR}}': academicYear ?? _academicYear(),
      '{{FULL_NAME}}': record.fullName,
      '{{STUDENT_NUMBER}}': record.studentNumber,
      '{{ACADEMIC_PROGRAM}}': record.academicProgram,
      '{{YEAR_LEVEL}}': record.yearLevel,
      '{{ADDRESS}}': record.presentAddress.isNotEmpty
          ? record.presentAddress
          : record.permanentAddress,
      '{{CONTACT}}': record.contactInformation,
      '{{TARGET_OFFICE}}': record.targetOfficeName.isEmpty
          ? '____________'
          : record.targetOfficeName,
      '{{REMARKS}}': record.generalNotes.isEmpty ? 'None' : record.generalNotes,
      '{{INTERVIEWER_NAME}}': record.interviewerName,
      '{{INTERVIEW_DATE}}': record.interviewerDate,
      '{{NOTED_BY_NAME}}': record.notedByName,
      '{{NOTED_BY_TITLE}}': record.notedByTitle,
      '{{OVERALL_SCORE}}': _score(record).toStringAsFixed(1),
      '{{GENERATED_DATE}}': _date(DateTime.now()),
      '{{REC_HIGHLY}}': _check(record.recommendation, 'Highly Recommended'),
      '{{REC_RECOMMENDED}}': _check(record.recommendation, 'Recommended'),
      '{{REC_RESERVATIONS}}': _check(
        record.recommendation,
        'Recommended with Reservations',
      ),
      '{{REC_NOT}}': _check(record.recommendation, 'Not Recommended'),
    };
    for (var i = 0; i < _skills.length; i++) {
      replacements['{{SKILL_${i + 1}_RATING}}'] =
          '${record.skills[_skills[i]] ?? 0}';
      final skillNote = record.skillNotes[_skills[i]] ?? '';
      replacements['{{SKILL_${i + 1}_NOTES}}'] = skillNote.isEmpty
          ? '-'
          : skillNote;
    }
    for (var i = 0; i < _overall.length; i++) {
      replacements['{{OVERALL_${i + 1}_RATING}}'] =
          '${record.overall[_overall[i]] ?? 0}';
      final overallNote = record.overallNotes[_overall[i]] ?? '';
      replacements['{{OVERALL_${i + 1}_NOTES}}'] = overallNote.isEmpty
          ? '-'
          : overallNote;
    }
    final bytes = _fill(
      template,
      replacements,
      photoBytes: photoBytes,
      photoExtension: photoExtension ?? 'jpeg',
    );
    final safeName = record.fullName
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-')
        .toLowerCase();
    return ApplicationDocument(
      id: 'doc_${DateTime.now().microsecondsSinceEpoch}',
      applicationId: record.applicationId,
      requirementName: 'Interview and Assessment Form',
      fileName: 'interview-assessment-form-$safeName.docx',
      uploadedAt: DateTime.now().toIso8601String(),
      description: 'System-generated Interview and Assessment Form',
      fileSize: bytes.lengthInBytes / (1024 * 1024),
      bytes: bytes,
    );
  }

  String _check(String actual, String expected) =>
      actual == expected ? '☒' : '☐';
  double _score(ScreeningRecord record) {
    final values = [...record.skills.values, ...record.overall.values];
    return values.isEmpty ? 0 : values.reduce((a, b) => a + b) / values.length;
  }

  String _academicYear() {
    final year = DateTime.now().month >= 6
        ? DateTime.now().year
        : DateTime.now().year - 1;
    return '$year-${year + 1}';
  }

  String _date(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  // Relationship id used for the embedded 2x2 photo. Anything unique and
  // XML-name-safe works here; it doesn't need to follow Word's "rIdN"
  // numbering since we fully control document.xml.rels ourselves.
  static const _photoRelId = 'rIdApplicantPhoto2x2';
  static const _photoMediaBaseName = 'word/media/applicant_photo_2x2';

  Uint8List _fill(
    Uint8List source,
    Map<String, String> replacements, {
    Uint8List? photoBytes,
    String photoExtension = 'jpeg',
  }) {
    final hasPhoto = photoBytes != null && photoBytes.isNotEmpty;
    final ext = _normalizedExtension(photoExtension);
    final mediaName = '$_photoMediaBaseName.$ext';

    final archive = ZipDecoder().decodeBytes(source);
    final output = Archive();
    for (final file in archive) {
      if (!file.isFile) continue;
      if (file.name == 'word/document.xml') {
        var xml = utf8.decode(file.content as List<int>);
        replacements.forEach(
          (key, value) => xml = xml.replaceAll(key, _escape(value)),
        );
        if (hasPhoto) {
          xml = _insertPhoto(xml);
        }
        final bytes = utf8.encode(xml);
        output.addFile(ArchiveFile(file.name, bytes.length, bytes));
      } else if (hasPhoto && file.name == 'word/_rels/document.xml.rels') {
        var xml = utf8.decode(file.content as List<int>);
        xml = _insertRelationship(xml, mediaName);
        final bytes = utf8.encode(xml);
        output.addFile(ArchiveFile(file.name, bytes.length, bytes));
      } else if (hasPhoto && file.name == '[Content_Types].xml') {
        var xml = utf8.decode(file.content as List<int>);
        xml = _ensureContentType(xml, ext);
        final bytes = utf8.encode(xml);
        output.addFile(ArchiveFile(file.name, bytes.length, bytes));
      } else {
        output.addFile(
          ArchiveFile(
            file.name,
            file.content.length,
            file.content as List<int>,
          ),
        );
      }
    }
    if (hasPhoto) {
      output.addFile(
        ArchiveFile(mediaName, photoBytes.length, photoBytes),
      );
    }
    final encoded = ZipEncoder().encode(output);
    return Uint8List.fromList(encoded);
  }

  String _normalizedExtension(String extension) {
    var ext = extension.trim().toLowerCase();
    if (ext.startsWith('.')) ext = ext.substring(1);
    if (ext == 'jpg') ext = 'jpeg';
    if (ext.isEmpty) ext = 'jpeg';
    return ext;
  }

  /// Replaces the "Paste your 2x2 / pic here" placeholder shape in the
  /// template with an actual picture of the applicant, keeping the same
  /// position/size the template author set up for the photo box.
  String _insertPhoto(String documentXml) {
    final markerIndex = documentXml.indexOf('Paste your 2x2');
    if (markerIndex < 0) return documentXml;
    final start = documentXml.lastIndexOf('<w:drawing', markerIndex);
    final endTag = '</w:drawing>';
    final endTagIndex = documentXml.indexOf(endTag, markerIndex);
    if (start < 0 || endTagIndex < 0) return documentXml;
    final end = endTagIndex + endTag.length;

    final original = documentXml.substring(start, end);
    final extent = RegExp(
      r'<wp:extent\s+cx="(\d+)"\s+cy="(\d+)"/>',
    ).firstMatch(original);
    final cx = extent?.group(1) ?? '847264';
    final cy = extent?.group(2) ?? '784068';
    final posH = RegExp(
      r'<wp:positionH[^>]*>.*?</wp:positionH>',
      dotAll: true,
    ).firstMatch(original)?.group(0) ??
        '<wp:positionH relativeFrom="column"><wp:posOffset>0</wp:posOffset></wp:positionH>';
    final posV = RegExp(
      r'<wp:positionV[^>]*>.*?</wp:positionV>',
      dotAll: true,
    ).firstMatch(original)?.group(0) ??
        '<wp:positionV relativeFrom="paragraph"><wp:posOffset>0</wp:posOffset></wp:positionV>';

    final replacement =
        '<w:drawing>'
        '<wp:anchor distT="0" distB="0" distL="114300" distR="114300" '
        'simplePos="0" relativeHeight="251659264" behindDoc="0" locked="0" '
        'layoutInCell="1" allowOverlap="1" wp14:anchorId="2C1594DB" '
        'wp14:editId="29EFBA68">'
        '<wp:simplePos x="0" y="0"/>'
        '$posH'
        '$posV'
        '<wp:extent cx="$cx" cy="$cy"/>'
        '<wp:effectExtent l="0" t="0" r="0" b="0"/>'
        '<wp:wrapNone/>'
        '<wp:docPr id="587476882" name="Applicant 2x2 Photo"/>'
        '<wp:cNvGraphicFramePr>'
        '<a:graphicFrameLocks xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" noChangeAspect="1"/>'
        '</wp:cNvGraphicFramePr>'
        '<a:graphic xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">'
        '<a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">'
        '<pic:pic xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">'
        '<pic:nvPicPr><pic:cNvPr id="0" name="Applicant 2x2 Photo"/><pic:cNvPicPr/></pic:nvPicPr>'
        '<pic:blipFill><a:blip r:embed="$_photoRelId"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>'
        '<pic:spPr>'
        '<a:xfrm><a:off x="0" y="0"/><a:ext cx="$cx" cy="$cy"/></a:xfrm>'
        '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom>'
        '</pic:spPr>'
        '</pic:pic>'
        '</a:graphicData>'
        '</a:graphic>'
        '<wp14:sizeRelH relativeFrom="margin"><wp14:pctWidth>0</wp14:pctWidth></wp14:sizeRelH>'
        '<wp14:sizeRelV relativeFrom="margin"><wp14:pctHeight>0</wp14:pctHeight></wp14:sizeRelV>'
        '</wp:anchor>'
        '</w:drawing>';

    return documentXml.replaceRange(start, end, replacement);
  }

  String _insertRelationship(String relsXml, String mediaName) {
    final target = mediaName.replaceFirst('word/', '');
    final relationship =
        '<Relationship Id="$_photoRelId" '
        'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" '
        'Target="$target"/>';
    return relsXml.replaceFirst('</Relationships>', '$relationship</Relationships>');
  }

  String _ensureContentType(String contentTypesXml, String extension) {
    if (contentTypesXml.contains('Extension="$extension"')) {
      return contentTypesXml;
    }
    const mimeByExtension = {
      'jpeg': 'image/jpeg',
      'png': 'image/png',
      'gif': 'image/gif',
      'bmp': 'image/bmp',
      'webp': 'image/webp',
    };
    final mime = mimeByExtension[extension] ?? 'image/jpeg';
    final entry = '<Default Extension="$extension" ContentType="$mime"/>';
    final match = RegExp(r'<Types[^>]*>').firstMatch(contentTypesXml);
    if (match == null) return contentTypesXml;
    return contentTypesXml.replaceRange(match.end, match.end, entry);
  }

  String _escape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}