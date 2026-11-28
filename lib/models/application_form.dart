import '../utils/input_formats.dart';

/// One sibling row in the Family Background table of the Application Form.
class SiblingEntry {
  final String name;
  final String age;
  final String schoolOrOccupation;
  final String program;

  const SiblingEntry({
    this.name = '',
    this.age = '',
    this.schoolOrOccupation = '',
    this.program = '',
  });

  bool get isEmpty =>
      name.trim().isEmpty &&
      age.trim().isEmpty &&
      schoolOrOccupation.trim().isEmpty &&
      program.trim().isEmpty;

  factory SiblingEntry.fromJson(Map<String, dynamic> json) => SiblingEntry(
    name: json['name']?.toString() ?? '',
    age: json['age']?.toString() ?? '',
    schoolOrOccupation: json['schoolOrOccupation']?.toString() ?? '',
    program: json['program']?.toString() ?? '',
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'age': age,
    'schoolOrOccupation': schoolOrOccupation,
    'program': program,
  };

  SiblingEntry copyWith({
    String? name,
    String? age,
    String? schoolOrOccupation,
    String? program,
  }) => SiblingEntry(
    name: name ?? this.name,
    age: age ?? this.age,
    schoolOrOccupation: schoolOrOccupation ?? this.schoolOrOccupation,
    program: program ?? this.program,
  );
}

/// One organization / extra-curricular membership row on the Application Form.
class OrganizationEntry {
  final String name;
  final String position;

  const OrganizationEntry({this.name = '', this.position = ''});

  bool get isEmpty => name.trim().isEmpty && position.trim().isEmpty;

  factory OrganizationEntry.fromJson(Map<String, dynamic> json) =>
      OrganizationEntry(
        name: json['name']?.toString() ?? '',
        position: json['position']?.toString() ?? '',
      );

  Map<String, dynamic> toJson() => {'name': name, 'position': position};

  OrganizationEntry copyWith({String? name, String? position}) =>
      OrganizationEntry(
        name: name ?? this.name,
        position: position ?? this.position,
      );
}

/// Structured responses for the official MarSU "Application Form for
/// Student Assistantship". Kept on [Application] so the filled `.docx` can be
/// generated on submit and re-opened/downloaded by both the Head and the SA.
class ApplicationFormData {
  static const semesters = ['1st Sem', '2nd Sem', 'Midyear'];
  static const residenceOptions = [
    'Boarding House',
    "Parent's House",
    'With Guardian',
  ];

  final String semester;
  final String academicYear;

  // Personal Data
  final String surname;
  final String firstName;
  final String middleName;
  final String studentNumber;
  final String programAndYear;
  final String existingScholarships;
  final String remainingUnits;
  final String remainingTerms;
  final String dateOfBirth;
  final String age;
  final String placeOfBirth;
  final String email;
  final String citizenship;
  final String gender;
  final String civilStatus;
  final String religion;
  final String residingAt;
  final String guardianName;
  final String emergencyContactName;
  final String emergencyContactNumber;
  final String permanentAddress;
  final String contactNumber;
  final String gwa;

  // Family Background
  final String fatherName;
  final String fatherAge;
  final String fatherOccupation;
  final String fatherNetAnnualIncome;
  final String motherName;
  final String motherAge;
  final String motherOccupation;
  final String motherNetAnnualIncome;
  final String familyHomeAddress;
  final String familyContactNumbers;
  final List<SiblingEntry> siblings;
  final String totalSiblings;
  final String workingSiblings;
  final String studyingSiblings;

  // Reasons & Organizations
  final String reasonsForAvailing;
  final List<OrganizationEntry> organizations;
  final String dateSubmitted;

  const ApplicationFormData({
    this.semester = '1st Sem',
    this.academicYear = '',
    this.surname = '',
    this.firstName = '',
    this.middleName = '',
    this.studentNumber = '',
    this.programAndYear = '',
    this.existingScholarships = '',
    this.remainingUnits = '',
    this.remainingTerms = '',
    this.dateOfBirth = '',
    this.age = '',
    this.placeOfBirth = '',
    this.email = '',
    this.citizenship = '',
    this.gender = '',
    this.civilStatus = '',
    this.religion = '',
    this.residingAt = '',
    this.guardianName = '',
    this.emergencyContactName = '',
    this.emergencyContactNumber = '',
    this.permanentAddress = '',
    this.contactNumber = '',
    this.gwa = '',
    this.fatherName = '',
    this.fatherAge = '',
    this.fatherOccupation = '',
    this.fatherNetAnnualIncome = '',
    this.motherName = '',
    this.motherAge = '',
    this.motherOccupation = '',
    this.motherNetAnnualIncome = '',
    this.familyHomeAddress = '',
    this.familyContactNumbers = '',
    this.siblings = const [],
    this.totalSiblings = '',
    this.workingSiblings = '',
    this.studyingSiblings = '',
    this.reasonsForAvailing = '',
    this.organizations = const [],
    this.dateSubmitted = '',
  });

  /// Converts academic settings labels (e.g. `'1st Semester'`) to the form's
  /// compact labels (`'1st Sem'`, `'2nd Sem'`, `'Midyear'`).
  static String normalizeSemester(String raw) {
    final s = raw.trim().toLowerCase();
    if (s.startsWith('2')) return '2nd Sem';
    if (s.contains('mid') || s.contains('sum')) return 'Midyear';
    return '1st Sem';
  }

  /// `"Juan M. Dela Cruz"`
  String get fullNameDisplay {
    final m = middleName.trim();
    final mid = m.isEmpty ? '' : ' ${m[0].toUpperCase()}.';
    return '${firstName.trim()}$mid ${surname.trim()}'.trim();
  }

  /// `"DELA CRUZ, Juan Santos"`
  String get surnameFirstDisplay {
    final sur = surname.trim().toUpperCase();
    final first = firstName.trim();
    final mid = middleName.trim();
    final given = [first, mid].where((p) => p.isNotEmpty).join(' ');
    if (sur.isEmpty) return given;
    if (given.isEmpty) return sur;
    return '$sur, $given';
  }

  /// Missing or invalid fields. Parent info and optional fields (scholarships,
  /// sibling rows, organizations) are left optional so applicants without a
  /// parent or with no organizations are not blocked, but any value entered
  /// must follow its numeric or phone format.
  List<String> problems() {
    final issues = <String>[];
    void req(String value, String label) {
      if (value.trim().isEmpty) issues.add('Enter $label.');
    }

    int? parseIntInRange(String raw, int min, int max) {
      final t = raw.trim();
      if (!RegExp(r'^\d+$').hasMatch(t)) return null;
      final n = int.tryParse(t);
      if (n == null || n < min || n > max) return null;
      return n;
    }

    req(surname, 'your surname');
    req(firstName, 'your first name');
    req(programAndYear, 'your program of study and year');
    if (remainingUnits.trim().isEmpty) {
      issues.add('Enter your remaining units including this term.');
    } else if (parseIntInRange(remainingUnits, 1, 999) == null) {
      issues.add('Enter a valid number for remaining units.');
    }
    if (remainingTerms.trim().isEmpty) {
      issues.add('Enter your remaining terms to graduate.');
    } else if (parseIntInRange(remainingTerms, 1, 99) == null) {
      issues.add('Enter a valid number for remaining terms to graduate.');
    }
    req(dateOfBirth, 'your date of birth');
    if (age.trim().isEmpty) {
      issues.add('Enter your age.');
    } else if (parseIntInRange(age, 10, 99) == null) {
      issues.add('Enter a valid age.');
    }
    req(placeOfBirth, 'your place of birth');
    req(citizenship, 'your citizenship');
    req(gender, 'your gender');
    req(civilStatus, 'your civil status');
    req(religion, 'your religion');
    req(residingAt, 'where you are residing');
    if (residingAt == 'With Guardian') {
      req(guardianName, 'your guardian\'s name');
    }
    req(emergencyContactName, 'an emergency contact person');
    if (emergencyContactNumber.trim().isEmpty) {
      issues.add('Enter an emergency contact number.');
    } else if (!isValidPhoneNumber(emergencyContactNumber)) {
      issues.add(
        'Enter a valid emergency contact number (09XX XXX XXXX).',
      );
    }
    req(permanentAddress, 'your permanent address');
    if (contactNumber.trim().isEmpty) {
      issues.add('Enter your contact number.');
    } else if (!isValidPhoneNumber(contactNumber)) {
      issues.add('Enter a valid contact number (09XX XXX XXXX).');
    }
    final gwaText = gwa.trim();
    if (gwaText.isEmpty) {
      issues.add('Enter your GWA for the last semester attended.');
    } else {
      final gwaVal = double.tryParse(gwaText);
      if (gwaVal == null || gwaVal < 1.0 || gwaVal > 5.0) {
        issues.add('Enter a valid GWA between 1.00 and 5.00.');
      }
    }

    if (fatherAge.trim().isNotEmpty &&
        parseIntInRange(fatherAge, 1, 120) == null) {
      issues.add("Enter a valid number for father's age.");
    }
    if (fatherNetAnnualIncome.trim().isNotEmpty) {
      final v = double.tryParse(fatherNetAnnualIncome.trim());
      if (v == null || v < 0) {
        issues.add("Enter a valid number for father's net annual income.");
      }
    }
    if (motherAge.trim().isNotEmpty &&
        parseIntInRange(motherAge, 1, 120) == null) {
      issues.add("Enter a valid number for mother's age.");
    }
    if (motherNetAnnualIncome.trim().isNotEmpty) {
      final v = double.tryParse(motherNetAnnualIncome.trim());
      if (v == null || v < 0) {
        issues.add("Enter a valid number for mother's net annual income.");
      }
    }
    if (familyContactNumbers.trim().isNotEmpty &&
        !isValidPhoneNumber(familyContactNumbers)) {
      issues.add('Enter a valid family contact number (09XX XXX XXXX).');
    }
    for (var i = 0; i < siblings.length; i++) {
      final sib = siblings[i];
      if (!sib.isEmpty &&
          sib.age.trim().isNotEmpty &&
          parseIntInRange(sib.age, 1, 120) == null) {
        issues.add('Enter a valid age for sibling ${i + 1}.');
      }
    }
    if (totalSiblings.trim().isNotEmpty &&
        parseIntInRange(totalSiblings, 0, 99) == null) {
      issues.add('Enter a valid number for total siblings.');
    }
    if (workingSiblings.trim().isNotEmpty &&
        parseIntInRange(workingSiblings, 0, 99) == null) {
      issues.add('Enter a valid number for working siblings.');
    }
    if (studyingSiblings.trim().isNotEmpty &&
        parseIntInRange(studyingSiblings, 0, 99) == null) {
      issues.add('Enter a valid number for studying siblings.');
    }

    req(reasonsForAvailing, 'your reason(s) for availing Student Assistantship');
    return issues;
  }

  factory ApplicationFormData.fromJson(Map<String, dynamic> json) =>
      ApplicationFormData(
        semester: json['semester']?.toString() ?? '1st Sem',
        academicYear: json['academicYear']?.toString() ?? '',
        surname: json['surname']?.toString() ?? '',
        firstName: json['firstName']?.toString() ?? '',
        middleName: json['middleName']?.toString() ?? '',
        studentNumber: json['studentNumber']?.toString() ?? '',
        programAndYear: json['programAndYear']?.toString() ?? '',
        existingScholarships: json['existingScholarships']?.toString() ?? '',
        remainingUnits: json['remainingUnits']?.toString() ?? '',
        remainingTerms: json['remainingTerms']?.toString() ?? '',
        dateOfBirth: json['dateOfBirth']?.toString() ?? '',
        age: json['age']?.toString() ?? '',
        placeOfBirth: json['placeOfBirth']?.toString() ?? '',
        email: json['email']?.toString() ?? '',
        citizenship: json['citizenship']?.toString() ?? '',
        gender: json['gender']?.toString() ?? '',
        civilStatus: json['civilStatus']?.toString() ?? '',
        religion: json['religion']?.toString() ?? '',
        residingAt: json['residingAt']?.toString() ?? '',
        guardianName: json['guardianName']?.toString() ?? '',
        emergencyContactName: json['emergencyContactName']?.toString() ?? '',
        emergencyContactNumber:
            json['emergencyContactNumber']?.toString() ?? '',
        permanentAddress: json['permanentAddress']?.toString() ?? '',
        contactNumber: json['contactNumber']?.toString() ?? '',
        gwa: json['gwa']?.toString() ?? '',
        fatherName: json['fatherName']?.toString() ?? '',
        fatherAge: json['fatherAge']?.toString() ?? '',
        fatherOccupation: json['fatherOccupation']?.toString() ?? '',
        fatherNetAnnualIncome:
            json['fatherNetAnnualIncome']?.toString() ?? '',
        motherName: json['motherName']?.toString() ?? '',
        motherAge: json['motherAge']?.toString() ?? '',
        motherOccupation: json['motherOccupation']?.toString() ?? '',
        motherNetAnnualIncome:
            json['motherNetAnnualIncome']?.toString() ?? '',
        familyHomeAddress: json['familyHomeAddress']?.toString() ?? '',
        familyContactNumbers: json['familyContactNumbers']?.toString() ?? '',
        siblings:
            (json['siblings'] as List<dynamic>?)
                ?.map(
                  (e) => SiblingEntry.fromJson(
                    Map<String, dynamic>.from(e as Map),
                  ),
                )
                .toList() ??
            const [],
        totalSiblings: json['totalSiblings']?.toString() ?? '',
        workingSiblings: json['workingSiblings']?.toString() ?? '',
        studyingSiblings: json['studyingSiblings']?.toString() ?? '',
        reasonsForAvailing: json['reasonsForAvailing']?.toString() ?? '',
        organizations:
            (json['organizations'] as List<dynamic>?)
                ?.map(
                  (e) => OrganizationEntry.fromJson(
                    Map<String, dynamic>.from(e as Map),
                  ),
                )
                .toList() ??
            const [],
        dateSubmitted: json['dateSubmitted']?.toString() ?? '',
      );

  Map<String, dynamic> toJson() => {
    'semester': semester,
    'academicYear': academicYear,
    'surname': surname,
    'firstName': firstName,
    'middleName': middleName,
    'studentNumber': studentNumber,
    'programAndYear': programAndYear,
    'existingScholarships': existingScholarships,
    'remainingUnits': remainingUnits,
    'remainingTerms': remainingTerms,
    'dateOfBirth': dateOfBirth,
    'age': age,
    'placeOfBirth': placeOfBirth,
    'email': email,
    'citizenship': citizenship,
    'gender': gender,
    'civilStatus': civilStatus,
    'religion': religion,
    'residingAt': residingAt,
    'guardianName': guardianName,
    'emergencyContactName': emergencyContactName,
    'emergencyContactNumber': emergencyContactNumber,
    'permanentAddress': permanentAddress,
    'contactNumber': contactNumber,
    'gwa': gwa,
    'fatherName': fatherName,
    'fatherAge': fatherAge,
    'fatherOccupation': fatherOccupation,
    'fatherNetAnnualIncome': fatherNetAnnualIncome,
    'motherName': motherName,
    'motherAge': motherAge,
    'motherOccupation': motherOccupation,
    'motherNetAnnualIncome': motherNetAnnualIncome,
    'familyHomeAddress': familyHomeAddress,
    'familyContactNumbers': familyContactNumbers,
    'siblings': siblings.map((s) => s.toJson()).toList(),
    'totalSiblings': totalSiblings,
    'workingSiblings': workingSiblings,
    'studyingSiblings': studyingSiblings,
    'reasonsForAvailing': reasonsForAvailing,
    'organizations': organizations.map((o) => o.toJson()).toList(),
    'dateSubmitted': dateSubmitted,
  };

  ApplicationFormData copyWith({
    String? semester,
    String? academicYear,
    String? surname,
    String? firstName,
    String? middleName,
    String? studentNumber,
    String? programAndYear,
    String? existingScholarships,
    String? remainingUnits,
    String? remainingTerms,
    String? dateOfBirth,
    String? age,
    String? placeOfBirth,
    String? email,
    String? citizenship,
    String? gender,
    String? civilStatus,
    String? religion,
    String? residingAt,
    String? guardianName,
    String? emergencyContactName,
    String? emergencyContactNumber,
    String? permanentAddress,
    String? contactNumber,
    String? gwa,
    String? fatherName,
    String? fatherAge,
    String? fatherOccupation,
    String? fatherNetAnnualIncome,
    String? motherName,
    String? motherAge,
    String? motherOccupation,
    String? motherNetAnnualIncome,
    String? familyHomeAddress,
    String? familyContactNumbers,
    List<SiblingEntry>? siblings,
    String? totalSiblings,
    String? workingSiblings,
    String? studyingSiblings,
    String? reasonsForAvailing,
    List<OrganizationEntry>? organizations,
    String? dateSubmitted,
  }) => ApplicationFormData(
    semester: semester ?? this.semester,
    academicYear: academicYear ?? this.academicYear,
    surname: surname ?? this.surname,
    firstName: firstName ?? this.firstName,
    middleName: middleName ?? this.middleName,
    studentNumber: studentNumber ?? this.studentNumber,
    programAndYear: programAndYear ?? this.programAndYear,
    existingScholarships: existingScholarships ?? this.existingScholarships,
    remainingUnits: remainingUnits ?? this.remainingUnits,
    remainingTerms: remainingTerms ?? this.remainingTerms,
    dateOfBirth: dateOfBirth ?? this.dateOfBirth,
    age: age ?? this.age,
    placeOfBirth: placeOfBirth ?? this.placeOfBirth,
    email: email ?? this.email,
    citizenship: citizenship ?? this.citizenship,
    gender: gender ?? this.gender,
    civilStatus: civilStatus ?? this.civilStatus,
    religion: religion ?? this.religion,
    residingAt: residingAt ?? this.residingAt,
    guardianName: guardianName ?? this.guardianName,
    emergencyContactName: emergencyContactName ?? this.emergencyContactName,
    emergencyContactNumber:
        emergencyContactNumber ?? this.emergencyContactNumber,
    permanentAddress: permanentAddress ?? this.permanentAddress,
    contactNumber: contactNumber ?? this.contactNumber,
    gwa: gwa ?? this.gwa,
    fatherName: fatherName ?? this.fatherName,
    fatherAge: fatherAge ?? this.fatherAge,
    fatherOccupation: fatherOccupation ?? this.fatherOccupation,
    fatherNetAnnualIncome:
        fatherNetAnnualIncome ?? this.fatherNetAnnualIncome,
    motherName: motherName ?? this.motherName,
    motherAge: motherAge ?? this.motherAge,
    motherOccupation: motherOccupation ?? this.motherOccupation,
    motherNetAnnualIncome:
        motherNetAnnualIncome ?? this.motherNetAnnualIncome,
    familyHomeAddress: familyHomeAddress ?? this.familyHomeAddress,
    familyContactNumbers: familyContactNumbers ?? this.familyContactNumbers,
    siblings: siblings ?? this.siblings,
    totalSiblings: totalSiblings ?? this.totalSiblings,
    workingSiblings: workingSiblings ?? this.workingSiblings,
    studyingSiblings: studyingSiblings ?? this.studyingSiblings,
    reasonsForAvailing: reasonsForAvailing ?? this.reasonsForAvailing,
    organizations: organizations ?? this.organizations,
    dateSubmitted: dateSubmitted ?? this.dateSubmitted,
  );
}
