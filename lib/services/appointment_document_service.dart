import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../models/models.dart';

/// Generates the Contract of Appointment by filling in the *actual*
/// university-provided .docx template (assets/templates/contract_of_appointment_template.docx)
/// rather than hand-building OOXML. This preserves the letterhead, logo,
/// footer, fonts and styling exactly as designed in Word.
class AppointmentDocumentService {
  const AppointmentDocumentService();

  static const String _templateAssetPath =
      'assets/templates/contract_of_appointment_template.docx';

  Future<ApplicationDocument> generateContractOfAppointment({
    required Application application,
    required User applicant,
    required String officeName,
    required String supervisorName,
    required String supervisorRole,
    required String startDate,
    required String endDate,
  }) async {
    final templateBytes = (await rootBundle.load(_templateAssetPath))
        .buffer
        .asUint8List();

    final replacements = <String, String>{
      '{{STUDENT_NAME}}': applicant.name,
      '{{OFFICE_COLLEGE}}':
          '$officeName${applicant.department != null ? ' (${applicant.department})' : ''}',
      '{{START_DATE}}': startDate,
      '{{END_DATE}}': endDate,
      // Printed name is known at generation time; the date is left blank
      // for the actual signing date since it isn't known yet.
      '{{STUDENT_SIGNED_NAME}}': applicant.name,
      '{{STUDENT_SIGNED_DATE}}': '____________',
      '{{SUPERVISOR_SIGNED_NAME}}': supervisorName,
      '{{SUPERVISOR_SIGNED_DATE}}': '____________',
    };

    final docBytes = _fillTemplate(templateBytes, replacements);

    final timestamp = DateTime.now().toUtc().toIso8601String();
    return ApplicationDocument(
      id: 'doc_${DateTime.now().microsecondsSinceEpoch}',
      applicationId: application.id,
      requirementName: 'Contract of Appointment',
      fileName:
          'contract-of-appointment-${application.applicantName.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-').toLowerCase()}-${timestamp.replaceAll(RegExp(r'[^0-9]'), '')}.docx',
      uploadedAt: DateTime.now().toIso8601String(),
      description: 'System-generated Contract of Appointment',
      fileSize: docBytes.lengthInBytes / (1024 * 1024),
      bytes: docBytes,
      storagePath: null,
      downloadUrl: null,
    );
  }

  /// Removes Word proofing/bookmark markers (grammar/spell-check adds these
  /// when a template is opened and saved in Word) and merges consecutive
  /// runs that share identical formatting back into one run/text node.
  /// Word's spell-checker can split a placeholder like {{TOKEN}} across two
  /// separate <w:t> runs, which breaks plain string substitution — this
  /// puts split tokens back together first so replacement still works even
  /// if someone has opened and re-saved the template in Word.
  String _normalizeRuns(String xml) {
    var normalized = xml
        .replaceAll(RegExp(r'<w:proofErr[^>]*/>'), '')
        .replaceAll(RegExp(r'<w:bookmarkStart[^>]*/>'), '')
        .replaceAll(RegExp(r'<w:bookmarkEnd[^>]*/>'), '');

    final pairPattern = RegExp(
      r'<w:r(?: [^>]*)?><w:rPr>(.*?)</w:rPr><w:t([^>]*)>([^<]*)</w:t></w:r>'
      r'<w:r(?: [^>]*)?><w:rPr>(.*?)</w:rPr><w:t([^>]*)>([^<]*)</w:t></w:r>',
    );

    // Repeat until stable: merging can create new adjacent same-format
    // pairs when three or more runs in a row were split.
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

  /// Opens the template .docx as a zip, does a straight text substitution
  /// inside word/document.xml, and re-zips. Values are XML-escaped first
  /// so names/offices containing &, <, >, quotes don't corrupt the XML.
  Uint8List _fillTemplate(
    Uint8List templateBytes,
    Map<String, String> replacements,
  ) {
    final archive = ZipDecoder().decodeBytes(templateBytes);
    final outArchive = Archive();

    for (final file in archive) {
      if (!file.isFile) continue;

      if (file.name == 'word/document.xml') {
        var xml = utf8.decode(file.content as List<int>);
        xml = _normalizeRuns(xml);
        replacements.forEach((token, value) {
          xml = xml.replaceAll(token, _escapeXml(value));
        });
        final bytes = utf8.encode(xml);
        outArchive.addFile(ArchiveFile(file.name, bytes.length, bytes));
      } else {
        outArchive.addFile(
          ArchiveFile(file.name, file.content.length, file.content as List<int>),
        );
      }
    }

    final encoded = ZipEncoder().encode(outArchive);
    return Uint8List.fromList(encoded);
  }

  // ---------------------------------------------------------------------
  // Endorsement Letter — now template-based too, same trick as the contract.
  // Extra fields (studentId, courseProgram, yearLevel, contactNumber,
  // scheduleAvailability, validity dates) aren't on User/Application yet,
  // so they're optional params here with placeholder fallbacks. Wire real
  // values in once those fields exist on your models.
  // ---------------------------------------------------------------------

  static const String _endorsementTemplateAssetPath =
      'assets/templates/endorsement_letter_template.docx';

  Future<ApplicationDocument> generateEndorsementLetter({
    required Application application,
    required User applicant,
    required String supervisorName,
    required String officeName,
    required String campusName,
    String? studentId,
    String? courseProgram,
    String? yearLevel,
    String? contactNumber,
    String? scheduleAvailability,
    String? validityStart,
    String? validityEnd,
    DateTime? dateOfEndorsement,
    // "Endorsed By" block — sourced from the admin account generating the
    // document, not hardcoded. Falls back to sensible placeholders/defaults
    // if the admin profile is missing a field.
    String? endorsedByName,
    String? endorsedByContact,
    String? endorsedByEmail,
  }) async {
    final templateBytes = (await rootBundle.load(_endorsementTemplateAssetPath))
        .buffer
        .asUint8List();

    final date = dateOfEndorsement ?? DateTime.now();
    final formattedDate =
        '${_monthName(date.month)} ${date.day.toString().padLeft(2, '0')}, ${date.year}';

    final replacements = <String, String>{
      '{{DATE_OF_ENDORSEMENT}}': formattedDate,
      '{{OFFICE_DEPT}}': officeName,
      '{{IMMEDIATE_SUPERVISOR}}': supervisorName,
      '{{STUDENT_FULL_NAME}}': applicant.name,
      '{{STUDENT_ID}}': studentId ?? '____________',
      '{{COURSE_PROGRAM}}': courseProgram ?? '____________',
      '{{YEAR_LEVEL}}': yearLevel ?? applicant.yearLevel ?? '____________',
      '{{CONTACT_NUMBER}}': contactNumber ?? applicant.phone ?? '____________',
      '{{EMAIL_ADDRESS}}': applicant.email,
      '{{SCHEDULE_AVAILABILITY}}': scheduleAvailability ?? 'See Attached Class Schedule',
      '{{VALIDITY_START}}': validityStart ?? '____________',
      '{{VALIDITY_END}}': validityEnd ?? '____________',
      '{{ENDORSED_BY_NAME}}': endorsedByName ?? '____________',
      '{{ENDORSED_BY_POSITION}}': 'Head of Student Assistantship',
      '{{ENDORSED_BY_CONTACT}}': endorsedByContact ?? '____________',
      '{{ENDORSED_BY_EMAIL}}': endorsedByEmail ?? '____________',
    };

    final docBytes = _fillTemplateGeneric(templateBytes, replacements);
    final timestamp = DateTime.now().toUtc().toIso8601String();
    return ApplicationDocument(
      id: 'doc_${DateTime.now().microsecondsSinceEpoch}',
      applicationId: application.id,
      requirementName: 'Endorsement Letter',
      fileName:
          'endorsement-letter-${application.applicantName.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-').toLowerCase()}-${timestamp.replaceAll(RegExp(r'[^0-9]'), '')}.docx',
      uploadedAt: DateTime.now().toIso8601String(),
      description: 'System-generated Endorsement Letter',
      fileSize: docBytes.lengthInBytes / (1024 * 1024),
      bytes: docBytes,
      storagePath: null,
      downloadUrl: null,
    );
  }

  String _monthName(int month) {
    const names = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return names[month - 1];
  }

  /// Human-readable date like "August 30, 2026" — used for both the
  /// endorsement letter's date and the contract's start date, so a raw
  /// DateTime.now().toString() never leaks into a generated document.
  static String formatDate(DateTime date) {
    const names = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return '${names[date.month - 1]} ${date.day.toString().padLeft(2, '0')}, ${date.year}';
  }

  /// Same substitution logic as _fillTemplate, factored out so both
  /// the contract and endorsement letter templates can share it.
  Uint8List _fillTemplateGeneric(
    Uint8List templateBytes,
    Map<String, String> replacements,
  ) {
    final archive = ZipDecoder().decodeBytes(templateBytes);
    final outArchive = Archive();

    for (final file in archive) {
      if (!file.isFile) continue;

      if (file.name == 'word/document.xml') {
        var xml = utf8.decode(file.content as List<int>);
        xml = _normalizeRuns(xml);
        replacements.forEach((token, value) {
          xml = xml.replaceAll(token, _escapeXml(value));
        });
        final bytes = utf8.encode(xml);
        outArchive.addFile(ArchiveFile(file.name, bytes.length, bytes));
      } else {
        outArchive.addFile(
          ArchiveFile(file.name, file.content.length, file.content as List<int>),
        );
      }
    }

    final encoded = ZipEncoder().encode(outArchive);
    return Uint8List.fromList(encoded);
  }

  String _escapeXml(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }
}