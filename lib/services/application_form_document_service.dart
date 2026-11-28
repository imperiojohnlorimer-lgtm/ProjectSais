import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../models/models.dart';

/// Generates the filled official MarSU "Application Form for Student
/// Assistantship" (.docx) from [assets/templates/application_form_template.docx].
class ApplicationFormDocumentService {
  const ApplicationFormDocumentService();

  static const String templateAssetPath =
      'assets/templates/application_form_template.docx';
  static const String _photoRelId = 'rIdApplicantPhoto2x2';
  static const String _photoMediaBaseName = 'word/media/applicant_photo_2x2';

  Future<ApplicationDocument> generateApplicationForm({
    required ApplicationFormData data,
    required String applicationId,
    Uint8List? photoBytes,
    String? photoExtension,
  }) async {
    final templateBytes = (await rootBundle.load(templateAssetPath))
        .buffer
        .asUint8List();

    final semester = ApplicationFormData.normalizeSemester(data.semester);
    final residing = data.residingAt.trim();
    final guardianName = residing == 'With Guardian'
        ? data.guardianName.trim()
        : '';

    final replacements = <String, String>{
      '{{SEM_1ST}}': _box(semester == '1st Sem'),
      '{{SEM_2ND}}': _box(semester == '2nd Sem'),
      '{{SEM_MIDYEAR}}': _box(semester == 'Midyear'),
      '{{ACADEMIC_YEAR}}': data.academicYear.trim(),
      '{{APPLICANT_FULL_NAME_PARTS}}': data.surnameFirstDisplay,
      '{{STUDENT_NUMBER}}': data.studentNumber.trim(),
      '{{PROGRAM_AND_YEAR}}': data.programAndYear.trim(),
      '{{EXISTING_SCHOLARSHIPS}}': data.existingScholarships.trim().isEmpty
          ? 'None'
          : data.existingScholarships.trim(),
      '{{REMAINING_UNITS}}': data.remainingUnits.trim(),
      '{{REMAINING_TERMS}}': data.remainingTerms.trim(),
      '{{DATE_OF_BIRTH}}': data.dateOfBirth.trim(),
      '{{AGE}}': data.age.trim(),
      '{{PLACE_OF_BIRTH}}': data.placeOfBirth.trim(),
      '{{EMAIL}}': data.email.trim(),
      '{{CITIZENSHIP}}': data.citizenship.trim(),
      '{{GENDER}}': data.gender.trim(),
      '{{CIVIL_STATUS}}': data.civilStatus.trim(),
      '{{RELIGION}}': data.religion.trim(),
      '{{RES_BOARDING}}': _box(residing == 'Boarding House'),
      '{{RES_PARENTS}}': _box(residing == "Parent's House"),
      '{{RES_GUARDIAN}}': _box(residing == 'With Guardian'),
      '{{GUARDIAN_NAME}}': guardianName,
      '{{EMERGENCY_CONTACT_NAME}}': data.emergencyContactName.trim(),
      '{{EMERGENCY_CONTACT_NUMBER}}': data.emergencyContactNumber.trim(),
      '{{PERMANENT_ADDRESS}}': data.permanentAddress.trim(),
      '{{CONTACT_NUMBER}}': data.contactNumber.trim(),
      '{{GWA}}': data.gwa.trim(),
      '{{FATHER_NAME}}': data.fatherName.trim(),
      '{{FATHER_AGE}}': data.fatherAge.trim(),
      '{{FATHER_OCCUPATION}}': data.fatherOccupation.trim(),
      '{{FATHER_INCOME}}': data.fatherNetAnnualIncome.trim(),
      '{{MOTHER_NAME}}': data.motherName.trim(),
      '{{MOTHER_AGE}}': data.motherAge.trim(),
      '{{MOTHER_OCCUPATION}}': data.motherOccupation.trim(),
      '{{MOTHER_INCOME}}': data.motherNetAnnualIncome.trim(),
      '{{FAMILY_HOME_ADDRESS}}': data.familyHomeAddress.trim(),
      '{{FAMILY_CONTACT_NUMBERS}}': data.familyContactNumbers.trim(),
      '{{TOTAL_SIBLINGS}}': data.totalSiblings.trim(),
      '{{WORKING_SIBLINGS}}': data.workingSiblings.trim(),
      '{{STUDYING_SIBLINGS}}': data.studyingSiblings.trim(),
      '{{STUDENT_PRINTED_NAME}}': data.fullNameDisplay.toUpperCase(),
      '{{DATE_SUBMITTED}}': data.dateSubmitted.trim(),
    };

    final docBytes = _fillTemplate(
      templateBytes,
      replacements,
      reasonsForAvailing: data.reasonsForAvailing.trim(),
      siblings: data.siblings,
      organizations: data.organizations,
      photoBytes: photoBytes,
      photoExtension: photoExtension ?? 'jpeg',
    );

    final baseName = data.fullNameDisplay.isEmpty
        ? 'applicant'
        : data.fullNameDisplay;
    final safeName = baseName
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '')
        .toLowerCase();

    return ApplicationDocument(
      id: 'doc_${DateTime.now().microsecondsSinceEpoch}',
      applicationId: applicationId,
      requirementName: Application.applicationFormDocument,
      fileName: 'application-form-${safeName.isEmpty ? 'applicant' : safeName}.docx',
      uploadedAt: DateTime.now().toIso8601String(),
      description: 'Filled Application Form for Student Assistantship',
      fileSize: docBytes.lengthInBytes / (1024 * 1024),
      bytes: docBytes,
    );
  }

  /// Decodes a `data:image/<ext>;base64,...` avatar string when present, or
  /// returns null.
  static ({Uint8List bytes, String ext})? decodeAvatarDataUri(String? avatar) {
    final raw = avatar?.trim() ?? '';
    final match = RegExp(
      r'^data:image/(png|jpe?g|webp|gif);base64,(.+)$',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(raw);
    if (match == null) return null;
    try {
      final bytes = base64Decode(match.group(2)!.replaceAll(RegExp(r'\s+'), ''));
      if (bytes.isEmpty) return null;
      var ext = match.group(1)!.toLowerCase();
      if (ext == 'jpg') ext = 'jpeg';
      return (bytes: bytes, ext: ext);
    } catch (_) {
      return null;
    }
  }

  String _box(bool checked) => checked ? '[X]' : '[ ]';

  Uint8List _fillTemplate(
    Uint8List source,
    Map<String, String> replacements, {
    required String reasonsForAvailing,
    required List<SiblingEntry> siblings,
    required List<OrganizationEntry> organizations,
    Uint8List? photoBytes,
    String photoExtension = 'jpeg',
  }) {
    final hasPhoto = photoBytes != null && photoBytes.isNotEmpty;
    final ext = _normalizedExtension(photoExtension);
    final mediaName = '$_photoMediaBaseName.$ext';

    final archive = ZipDecoder().decodeBytes(source);
    final outArchive = Archive();

    for (final file in archive) {
      if (!file.isFile) continue;
      if (file.name == 'word/document.xml') {
        var xml = utf8.decode(file.content as List<int>);
        xml = _normalizeRuns(xml);
        xml = _expandSiblingRows(xml, siblings);
        xml = _expandOrganizationRows(xml, organizations);
        xml = xml.replaceAll(
          '{{REASONS_FOR_AVAILING}}',
          _escapeMultilineXml(reasonsForAvailing),
        );
        replacements.forEach(
          (key, value) => xml = xml.replaceAll(key, _escapeXml(value)),
        );
        xml = hasPhoto
            ? _insertPhoto(xml)
            : xml.replaceAll('{{PHOTO_2X2}}', '2 x 2');
        final bytes = utf8.encode(xml);
        outArchive.addFile(ArchiveFile(file.name, bytes.length, bytes));
      } else if (hasPhoto && file.name == 'word/_rels/document.xml.rels') {
        var xml = utf8.decode(file.content as List<int>);
        xml = _insertRelationship(xml, mediaName);
        final bytes = utf8.encode(xml);
        outArchive.addFile(ArchiveFile(file.name, bytes.length, bytes));
      } else if (hasPhoto && file.name == '[Content_Types].xml') {
        var xml = utf8.decode(file.content as List<int>);
        xml = _ensureContentType(xml, ext);
        final bytes = utf8.encode(xml);
        outArchive.addFile(ArchiveFile(file.name, bytes.length, bytes));
      } else {
        outputCopy(outArchive, file);
      }
    }

    if (hasPhoto) {
      outArchive.addFile(
        ArchiveFile(mediaName, photoBytes.length, photoBytes),
      );
    }

    final encoded = ZipEncoder().encode(outArchive);
    return Uint8List.fromList(encoded);
  }

  void outputCopy(Archive outArchive, ArchiveFile file) {
    outArchive.addFile(
      ArchiveFile(file.name, file.content.length, file.content as List<int>),
    );
  }

  String _normalizeRuns(String xml) {
    var normalized = xml
        .replaceAll(RegExp(r'<w:proofErr[^>]*/>'), '')
        .replaceAll(RegExp(r'<w:bookmarkStart[^>]*/>'), '')
        .replaceAll(RegExp(r'<w:bookmarkEnd[^>]*/>'), '');

    final pairPattern = RegExp(
      r'<w:r(?: [^>]*)?><w:rPr>(.*?)</w:rPr><w:t([^>]*)>([^<]*)</w:t></w:r>'
      r'<w:r(?: [^>]*)?><w:rPr>(.*?)</w:rPr><w:t([^>]*)>([^<]*)</w:t></w:r>',
    );

    for (var i = 0; i < 10; i++) {
      var changed = false;
      final merged = normalized.replaceAllMapped(pairPattern, (match) {
        final rpr1 = match.group(1)!;
        final text1 = match.group(3)!;
        final rpr2 = match.group(4)!;
        final text2 = match.group(6)!;
        if (rpr1 != rpr2) return match.group(0)!;
        changed = true;
        return '<w:r><w:rPr>$rpr1</w:rPr>'
            '<w:t xml:space="preserve">$text1$text2</w:t></w:r>';
      });
      normalized = merged;
      if (!changed) break;
    }

    return normalized;
  }

  String _expandSiblingRows(String xml, List<SiblingEntry> siblings) {
    final rowPattern = RegExp(r'<w:tr\b[^>]*>.*?</w:tr>', dotAll: true);
    final templateRow = rowPattern
        .allMatches(xml)
        .map((m) => m.group(0)!)
        .where((row) => row.contains('{{SIB_NAME}}'))
        .firstOrNull;
    if (templateRow == null) return xml;

    final nonEmpty = siblings.where((s) => !s.isEmpty).toList();
    final count = math.max(3, nonEmpty.length);
    final built = StringBuffer();
    for (var i = 0; i < count; i++) {
      final entry = i < nonEmpty.length ? nonEmpty[i] : const SiblingEntry();
      built.write(
        templateRow
            .replaceAll('{{SIB_NAME}}', _escapeXml(entry.name.trim()))
            .replaceAll('{{SIB_AGE}}', _escapeXml(entry.age.trim()))
            .replaceAll(
              '{{SIB_SCHOOL_OR_WORK}}',
              _escapeXml(entry.schoolOrOccupation.trim()),
            )
            .replaceAll('{{SIB_PROGRAM}}', _escapeXml(entry.program.trim())),
      );
    }
    return xml.replaceFirst(templateRow, built.toString());
  }

  String _expandOrganizationRows(
    String xml,
    List<OrganizationEntry> organizations,
  ) {
    final rowPattern = RegExp(r'<w:tr\b[^>]*>.*?</w:tr>', dotAll: true);
    final templateRow = rowPattern
        .allMatches(xml)
        .map((m) => m.group(0)!)
        .where((row) => row.contains('{{ORG_NAME}}'))
        .firstOrNull;
    if (templateRow == null) return xml;

    final nonEmpty = organizations.where((o) => !o.isEmpty).toList();
    final count = math.max(3, nonEmpty.length);
    final built = StringBuffer();
    for (var i = 0; i < count; i++) {
      final entry = i < nonEmpty.length
          ? nonEmpty[i]
          : const OrganizationEntry();
      built.write(
        templateRow
            .replaceAll('{{ORG_NAME}}', _escapeXml(entry.name.trim()))
            .replaceAll('{{ORG_POSITION}}', _escapeXml(entry.position.trim())),
      );
    }
    return xml.replaceFirst(templateRow, built.toString());
  }

  String _insertPhoto(String documentXml) {
    final runPattern = RegExp(
      r'<w:r\b[^>]*>(?:(?!<w:r\b).)*?\{\{PHOTO_2X2\}\}.*?</w:r>',
      dotAll: true,
    );
    final match = runPattern.firstMatch(documentXml);
    if (match == null) {
      return documentXml.replaceAll('{{PHOTO_2X2}}', '2 x 2');
    }
    const cx = '1200000';
    const cy = '1200000';
    final drawingRun =
        '<w:r><w:drawing>'
        '<wp:inline distT="0" distB="0" distL="0" distR="0">'
        '<wp:extent cx="$cx" cy="$cy"/>'
        '<wp:effectExtent l="0" t="0" r="0" b="0"/>'
        '<wp:docPr id="587476883" name="Applicant 2x2 Photo"/>'
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
        '</wp:inline>'
        '</w:drawing></w:r>';

    return documentXml.replaceRange(match.start, match.end, drawingRun);
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

  String _normalizedExtension(String extension) {
    var ext = extension.trim().toLowerCase();
    if (ext.startsWith('.')) ext = ext.substring(1);
    if (ext == 'jpg') ext = 'jpeg';
    if (ext.isEmpty) ext = 'jpeg';
    return ext;
  }

  static String _escapeMultilineXml(String value) {
    final escaped = _escapeXml(value.replaceAll('\r\n', '\n'));
    return escaped.replaceAll('\n', '</w:t><w:br/><w:t xml:space="preserve">');
  }

  static String _escapeXml(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}
