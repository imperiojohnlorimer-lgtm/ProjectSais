import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/models.dart';
import '../services/application_form_document_service.dart';
import '../theme/app_theme.dart';
import '../utils/input_formats.dart';
import 'document_preview.dart';
import 'shared_widgets.dart';

/// Returned by [showApplicationFormDialog] when the applicant saves the form.
class ApplicationFormDraft {
  final ApplicationFormData data;
  final Uint8List? photoBytes;
  final String? photoExtension;

  const ApplicationFormDraft({
    required this.data,
    this.photoBytes,
    this.photoExtension,
  });
}

/// Opens the official MarSU "Application Form for Student Assistantship" so
/// the applicant can fill it out (or edit it) before submitting.
Future<ApplicationFormDraft?> showApplicationFormDialog(
  BuildContext context, {
  required User user,
  required String academicYear,
  required String semester,
  String? studentNumber,
  ApplicationFormData? initialData,
  Uint8List? initialPhotoBytes,
  String? initialPhotoExt,
}) => showDialog<ApplicationFormDraft>(
  context: context,
  barrierDismissible: false,
  builder: (_) => ApplicationFormDialog(
    user: user,
    academicYear: academicYear,
    semester: semester,
    studentNumber: studentNumber,
    initialData: initialData,
    initialPhotoBytes: initialPhotoBytes,
    initialPhotoExt: initialPhotoExt,
  ),
);

class ApplicationFormDialog extends StatefulWidget {
  final User user;
  final String academicYear;
  final String semester;
  final String? studentNumber;
  final ApplicationFormData? initialData;
  final Uint8List? initialPhotoBytes;
  final String? initialPhotoExt;

  const ApplicationFormDialog({
    super.key,
    required this.user,
    required this.academicYear,
    required this.semester,
    this.studentNumber,
    this.initialData,
    this.initialPhotoBytes,
    this.initialPhotoExt,
  });

  @override
  State<ApplicationFormDialog> createState() => _ApplicationFormDialogState();
}

class _SiblingControllers {
  final TextEditingController name;
  final TextEditingController age;
  final TextEditingController schoolOrWork;
  final TextEditingController program;

  _SiblingControllers([SiblingEntry? entry])
    : name = TextEditingController(text: entry?.name ?? ''),
      age = TextEditingController(text: entry?.age ?? ''),
      schoolOrWork = TextEditingController(
        text: entry?.schoolOrOccupation ?? '',
      ),
      program = TextEditingController(text: entry?.program ?? '');

  SiblingEntry toEntry() => SiblingEntry(
    name: name.text.trim(),
    age: age.text.trim(),
    schoolOrOccupation: schoolOrWork.text.trim(),
    program: program.text.trim(),
  );

  void dispose() {
    name.dispose();
    age.dispose();
    schoolOrWork.dispose();
    program.dispose();
  }
}

class _OrgControllers {
  final TextEditingController name;
  final TextEditingController position;

  _OrgControllers([OrganizationEntry? entry])
    : name = TextEditingController(text: entry?.name ?? ''),
      position = TextEditingController(text: entry?.position ?? '');

  OrganizationEntry toEntry() => OrganizationEntry(
    name: name.text.trim(),
    position: position.text.trim(),
  );

  void dispose() {
    name.dispose();
    position.dispose();
  }
}

class _ApplicationFormDialogState extends State<ApplicationFormDialog> {
  static const _genderOptions = ['Male', 'Female', 'Prefer not to say'];
  static const _civilStatusOptions = [
    'Single',
    'Married',
    'Widowed',
    'Separated',
  ];
  static const _maxPhotoBytes = 5 * 1024 * 1024;

  late String _semester;
  late final TextEditingController _surnameCtrl;
  late final TextEditingController _firstNameCtrl;
  late final TextEditingController _middleNameCtrl;
  late final TextEditingController _studentNumCtrl;
  late final TextEditingController _programYearCtrl;
  late final TextEditingController _scholarshipsCtrl;
  late final TextEditingController _remainingUnitsCtrl;
  late final TextEditingController _remainingTermsCtrl;
  late final TextEditingController _dobCtrl;
  late final TextEditingController _ageCtrl;
  late final TextEditingController _birthPlaceCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _citizenshipCtrl;
  String _gender = '';
  String _civilStatus = '';
  late final TextEditingController _religionCtrl;
  String _residingAt = '';
  late final TextEditingController _guardianCtrl;
  late final TextEditingController _emergencyNameCtrl;
  late final TextEditingController _emergencyPhoneCtrl;
  late final TextEditingController _permanentAddressCtrl;
  late final TextEditingController _contactNumberCtrl;
  late final TextEditingController _gwaCtrl;

  late final TextEditingController _fatherNameCtrl;
  late final TextEditingController _fatherAgeCtrl;
  late final TextEditingController _fatherOccCtrl;
  late final TextEditingController _fatherIncomeCtrl;
  late final TextEditingController _motherNameCtrl;
  late final TextEditingController _motherAgeCtrl;
  late final TextEditingController _motherOccCtrl;
  late final TextEditingController _motherIncomeCtrl;
  late final TextEditingController _familyAddressCtrl;
  late final TextEditingController _familyContactCtrl;
  late final TextEditingController _totalSiblingsCtrl;
  late final TextEditingController _workingSiblingsCtrl;
  late final TextEditingController _studyingSiblingsCtrl;
  late final TextEditingController _reasonsCtrl;

  final List<_SiblingControllers> _siblings = [];
  final List<_OrgControllers> _orgs = [];

  Uint8List? _photoBytes;
  String? _photoExt;
  String? _error;

  @override
  void initState() {
    super.initState();
    final init = widget.initialData;
    final parts = widget.user.nameParts;
    final defaultProgram = [
      widget.user.courseProgram?.trim() ?? '',
      widget.user.yearLevel?.trim() ?? '',
    ].where((p) => p.isNotEmpty).join(' - ');
    final linkedStudentNo = (widget.studentNumber ?? '').trim().isNotEmpty
        ? widget.studentNumber!.trim().toUpperCase()
        : (widget.user.studentId ?? '').trim().toUpperCase();

    _semester = init != null && init.semester.trim().isNotEmpty
        ? ApplicationFormData.normalizeSemester(init.semester)
        : ApplicationFormData.normalizeSemester(widget.semester);
    _surnameCtrl = TextEditingController(
      text: init?.surname.isNotEmpty == true ? init!.surname : parts.last,
    );
    _firstNameCtrl = TextEditingController(
      text: init?.firstName.isNotEmpty == true ? init!.firstName : parts.first,
    );
    _middleNameCtrl = TextEditingController(
      text: init?.middleName.isNotEmpty == true
          ? init!.middleName
          : parts.middle,
    );
    _studentNumCtrl = TextEditingController(text: linkedStudentNo);
    _programYearCtrl = TextEditingController(
      text: init?.programAndYear.isNotEmpty == true
          ? init!.programAndYear
          : defaultProgram,
    );
    _scholarshipsCtrl = TextEditingController(
      text: init?.existingScholarships ?? '',
    );
    _remainingUnitsCtrl = TextEditingController(
      text: init?.remainingUnits ?? '',
    );
    _remainingTermsCtrl = TextEditingController(
      text: init?.remainingTerms ?? '',
    );
    _dobCtrl = TextEditingController(text: init?.dateOfBirth ?? '');
    _ageCtrl = TextEditingController(text: init?.age ?? '');
    _birthPlaceCtrl = TextEditingController(text: init?.placeOfBirth ?? '');
    _emailCtrl = TextEditingController(
      text: init?.email.isNotEmpty == true ? init!.email : widget.user.email,
    );
    _citizenshipCtrl = TextEditingController(
      text: init?.citizenship.isNotEmpty == true ? init!.citizenship : 'Filipino',
    );
    _gender = _genderOptions.contains(init?.gender) ? init!.gender : '';
    _civilStatus = _civilStatusOptions.contains(init?.civilStatus)
        ? init!.civilStatus
        : '';
    _religionCtrl = TextEditingController(text: init?.religion ?? '');
    _residingAt = ApplicationFormData.residenceOptions.contains(init?.residingAt)
        ? init!.residingAt
        : '';
    _guardianCtrl = TextEditingController(text: init?.guardianName ?? '');
    _emergencyNameCtrl = TextEditingController(
      text: init?.emergencyContactName ?? '',
    );
    _emergencyPhoneCtrl = TextEditingController(
      text: init?.emergencyContactNumber ?? '',
    );
    _permanentAddressCtrl = TextEditingController(
      text: init?.permanentAddress.isNotEmpty == true
          ? init!.permanentAddress
          : (widget.user.address ?? ''),
    );
    _contactNumberCtrl = TextEditingController(
      text: init?.contactNumber.isNotEmpty == true
          ? init!.contactNumber
          : (widget.user.phone ?? ''),
    );
    _gwaCtrl = TextEditingController(text: init?.gwa ?? '');

    _fatherNameCtrl = TextEditingController(text: init?.fatherName ?? '');
    _fatherAgeCtrl = TextEditingController(text: init?.fatherAge ?? '');
    _fatherOccCtrl = TextEditingController(text: init?.fatherOccupation ?? '');
    _fatherIncomeCtrl = TextEditingController(
      text: init?.fatherNetAnnualIncome ?? '',
    );
    _motherNameCtrl = TextEditingController(text: init?.motherName ?? '');
    _motherAgeCtrl = TextEditingController(text: init?.motherAge ?? '');
    _motherOccCtrl = TextEditingController(text: init?.motherOccupation ?? '');
    _motherIncomeCtrl = TextEditingController(
      text: init?.motherNetAnnualIncome ?? '',
    );
    _familyAddressCtrl = TextEditingController(
      text: init?.familyHomeAddress ?? '',
    );
    _familyContactCtrl = TextEditingController(
      text: init?.familyContactNumbers ?? '',
    );
    _totalSiblingsCtrl = TextEditingController(text: init?.totalSiblings ?? '');
    _workingSiblingsCtrl = TextEditingController(
      text: init?.workingSiblings ?? '',
    );
    _studyingSiblingsCtrl = TextEditingController(
      text: init?.studyingSiblings ?? '',
    );
    _reasonsCtrl = TextEditingController(text: init?.reasonsForAvailing ?? '');

    if (init != null && init.siblings.isNotEmpty) {
      for (final sib in init.siblings) {
        _siblings.add(_SiblingControllers(sib));
      }
    }
    if (init != null && init.organizations.isNotEmpty) {
      for (final org in init.organizations) {
        _orgs.add(_OrgControllers(org));
      }
    }

    if (widget.initialPhotoBytes != null &&
        widget.initialPhotoBytes!.isNotEmpty) {
      _photoBytes = widget.initialPhotoBytes;
      _photoExt = widget.initialPhotoExt ?? 'jpeg';
    } else {
      final avatar = ApplicationFormDocumentService.decodeAvatarDataUri(
        widget.user.avatar,
      );
      if (avatar != null) {
        _photoBytes = avatar.bytes;
        _photoExt = avatar.ext;
      }
    }
  }

  @override
  void dispose() {
    for (final c in [
      _surnameCtrl,
      _firstNameCtrl,
      _middleNameCtrl,
      _studentNumCtrl,
      _programYearCtrl,
      _scholarshipsCtrl,
      _remainingUnitsCtrl,
      _remainingTermsCtrl,
      _dobCtrl,
      _ageCtrl,
      _birthPlaceCtrl,
      _emailCtrl,
      _citizenshipCtrl,
      _religionCtrl,
      _guardianCtrl,
      _emergencyNameCtrl,
      _emergencyPhoneCtrl,
      _permanentAddressCtrl,
      _contactNumberCtrl,
      _gwaCtrl,
      _fatherNameCtrl,
      _fatherAgeCtrl,
      _fatherOccCtrl,
      _fatherIncomeCtrl,
      _motherNameCtrl,
      _motherAgeCtrl,
      _motherOccCtrl,
      _motherIncomeCtrl,
      _familyAddressCtrl,
      _familyContactCtrl,
      _totalSiblingsCtrl,
      _workingSiblingsCtrl,
      _studyingSiblingsCtrl,
      _reasonsCtrl,
    ]) {
      c.dispose();
    }
    for (final s in _siblings) {
      s.dispose();
    }
    for (final o in _orgs) {
      o.dispose();
    }
    super.dispose();
  }

  ApplicationFormData _buildFormData() {
    final now = DateTime.now().toUtc().add(const Duration(hours: 8));
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final today = '${months[now.month - 1]} ${now.day}, ${now.year}';
    return ApplicationFormData(
      semester: _semester,
      academicYear: widget.academicYear,
      surname: _surnameCtrl.text.trim(),
      firstName: _firstNameCtrl.text.trim(),
      middleName: _middleNameCtrl.text.trim(),
      studentNumber: _studentNumCtrl.text.trim().toUpperCase(),
      programAndYear: _programYearCtrl.text.trim(),
      existingScholarships: _scholarshipsCtrl.text.trim(),
      remainingUnits: _remainingUnitsCtrl.text.trim(),
      remainingTerms: _remainingTermsCtrl.text.trim(),
      dateOfBirth: _dobCtrl.text.trim(),
      age: _ageCtrl.text.trim(),
      placeOfBirth: _birthPlaceCtrl.text.trim(),
      email: _emailCtrl.text.trim(),
      citizenship: _citizenshipCtrl.text.trim(),
      gender: _gender,
      civilStatus: _civilStatus,
      religion: _religionCtrl.text.trim(),
      residingAt: _residingAt,
      guardianName: _residingAt == 'With Guardian'
          ? _guardianCtrl.text.trim()
          : '',
      emergencyContactName: _emergencyNameCtrl.text.trim(),
      emergencyContactNumber: _emergencyPhoneCtrl.text.trim(),
      permanentAddress: _permanentAddressCtrl.text.trim(),
      contactNumber: _contactNumberCtrl.text.trim(),
      gwa: _gwaCtrl.text.trim(),
      fatherName: _fatherNameCtrl.text.trim(),
      fatherAge: _fatherAgeCtrl.text.trim(),
      fatherOccupation: _fatherOccCtrl.text.trim(),
      fatherNetAnnualIncome: _fatherIncomeCtrl.text.trim(),
      motherName: _motherNameCtrl.text.trim(),
      motherAge: _motherAgeCtrl.text.trim(),
      motherOccupation: _motherOccCtrl.text.trim(),
      motherNetAnnualIncome: _motherIncomeCtrl.text.trim(),
      familyHomeAddress: _familyAddressCtrl.text.trim(),
      familyContactNumbers: _familyContactCtrl.text.trim(),
      siblings: [
        for (final s in _siblings)
          if (!s.toEntry().isEmpty) s.toEntry(),
      ],
      totalSiblings: _totalSiblingsCtrl.text.trim(),
      workingSiblings: _workingSiblingsCtrl.text.trim(),
      studyingSiblings: _studyingSiblingsCtrl.text.trim(),
      reasonsForAvailing: _reasonsCtrl.text.trim(),
      organizations: [
        for (final o in _orgs)
          if (!o.toEntry().isEmpty) o.toEntry(),
      ],
      dateSubmitted: widget.initialData?.dateSubmitted.isNotEmpty == true
          ? widget.initialData!.dateSubmitted
          : today,
    );
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year - 19, 1, 1),
      firstDate: DateTime(1970),
      lastDate: DateTime(now.year - 12, 12, 31),
    );
    if (picked == null || !mounted) return;
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    var age = now.year - picked.year;
    if (now.month < picked.month ||
        (now.month == picked.month && now.day < picked.day)) {
      age--;
    }
    setState(() {
      _dobCtrl.text =
          '${months[picked.month - 1]} ${picked.day}, ${picked.year}';
      _ageCtrl.text = '$age';
      _error = null;
    });
  }

  Future<void> _pickPhoto() async {
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['jpg', 'jpeg', 'png'],
        allowMultiple: false,
        withData: true,
      );
      if (res == null || res.files.isEmpty || !mounted) return;
      final file = res.files.single;
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) {
        setState(() => _error = 'Could not read the selected photo.');
        return;
      }
      if (bytes.length > _maxPhotoBytes) {
        setState(() => _error = 'The 2x2 photo must be 5 MB or smaller.');
        return;
      }
      setState(() {
        _photoBytes = bytes;
        _photoExt = (file.extension ?? 'jpeg').toLowerCase();
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not pick photo: $e');
    }
  }

  Future<void> _previewForm() async {
    final data = _buildFormData();
    try {
      final doc = await const ApplicationFormDocumentService()
          .generateApplicationForm(
            data: data,
            applicationId: Application.idFor(
              widget.user.id,
              widget.academicYear,
            ),
            photoBytes: _photoBytes,
            photoExtension: _photoExt,
          );
      if (!mounted) return;
      await showDocumentPreview(
        context,
        fileName: doc.fileName,
        bytes: doc.bytes,
      );
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Could not preview form: $e');
      }
    }
  }

  void _save() {
    final data = _buildFormData();
    final problems = data.problems();
    if (problems.isNotEmpty) {
      setState(() => _error = problems.first);
      return;
    }
    Navigator.of(context).pop(
      ApplicationFormDraft(
        data: data,
        photoBytes: _photoBytes,
        photoExtension: _photoExt,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final narrow = size.width < 600;
    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: narrow ? 10 : 24,
        vertical: narrow ? 16 : 24,
      ),
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 760,
          maxHeight: size.height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LightDialogHeader(
              icon: Icons.assignment_outlined,
              title: 'Application Form for Student Assistantship',
              subtitle:
                  'Fill out all required fields. This generates your official form.',
              onClose: () => Navigator.of(context).maybePop(),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  narrow ? 16 : 24,
                  18,
                  narrow ? 16 : 24,
                  24,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _summaryBanner(narrow),
                    const SizedBox(height: 20),
                    _sectionTitle('1. PERSONAL DATA'),
                    const SizedBox(height: 12),
                    _photoPicker(),
                    const SizedBox(height: 14),
                    _responsivePair(
                      narrow,
                      _field(
                        'Surname *',
                        _surnameCtrl,
                        inputFormatters: [nameFormatter],
                      ),
                      _field(
                        'First Name *',
                        _firstNameCtrl,
                        inputFormatters: [nameFormatter],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _responsivePair(
                      narrow,
                      _field(
                        'Middle Name',
                        _middleNameCtrl,
                        inputFormatters: [nameFormatter],
                      ),
                      _field(
                        'Student Number',
                        _studentNumCtrl,
                        readOnly: true,
                        hint: 'Auto-filled from your Student ID',
                        helperText:
                            'Linked to your Student ID (cannot be edited manually).',
                      ),
                    ),
                    const SizedBox(height: 12),
                    _responsivePair(
                      narrow,
                      _field(
                        'Program of Study & Year *',
                        _programYearCtrl,
                        hint: 'e.g. BSIT - 3rd Year',
                      ),
                      _field(
                        'Existing Scholarship/s (if any)',
                        _scholarshipsCtrl,
                        hint: 'Leave blank or write None',
                      ),
                    ),
                    const SizedBox(height: 12),
                    _responsivePair(
                      narrow,
                      _field(
                        'Remaining Units Including This Term *',
                        _remainingUnitsCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(3),
                        ],
                        hint: 'e.g. 24',
                      ),
                      _field(
                        'Remaining Terms to Graduate *',
                        _remainingTermsCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(2),
                        ],
                        hint: 'e.g. 2',
                      ),
                    ),
                    const SizedBox(height: 12),
                    _responsivePair(
                      narrow,
                      TextField(
                        controller: _dobCtrl,
                        readOnly: true,
                        onTap: _pickDob,
                        decoration: _decoration(
                          'Date of Birth *',
                          hint: 'Tap to pick date',
                          suffixIcon: IconButton(
                            tooltip: 'Pick date of birth',
                            onPressed: _pickDob,
                            icon: const Icon(
                              Icons.calendar_today_outlined,
                              size: 18,
                            ),
                          ),
                        ),
                      ),
                      _field(
                        'Age *',
                        _ageCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(2),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _responsivePair(
                      narrow,
                      _field('Place of Birth *', _birthPlaceCtrl),
                      _field('E-mail Address', _emailCtrl, readOnly: true),
                    ),
                    const SizedBox(height: 12),
                    _responsivePair(
                      narrow,
                      _field(
                        'Citizenship *',
                        _citizenshipCtrl,
                        inputFormatters: [nameFormatter],
                      ),
                      _dropdown(
                        'Gender *',
                        _gender,
                        _genderOptions,
                        (v) => setState(() {
                          _gender = v ?? '';
                          _error = null;
                        }),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _responsivePair(
                      narrow,
                      _dropdown(
                        'Civil Status *',
                        _civilStatus,
                        _civilStatusOptions,
                        (v) => setState(() {
                          _civilStatus = v ?? '';
                          _error = null;
                        }),
                      ),
                      _field(
                        'Religion *',
                        _religionCtrl,
                        inputFormatters: [nameFormatter],
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Residing at *',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.slate700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final option
                            in ApplicationFormData.residenceOptions)
                          ChoiceChip(
                            label: Text(option),
                            selected: _residingAt == option,
                            selectedColor: AppTheme.maroon,
                            labelStyle: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _residingAt == option
                                  ? Colors.white
                                  : AppTheme.slate700,
                            ),
                            showCheckmark: false,
                            onSelected: (_) => setState(() {
                              _residingAt = option;
                              _error = null;
                            }),
                          ),
                      ],
                    ),
                    if (_residingAt == 'With Guardian') ...[
                      const SizedBox(height: 12),
                      _field(
                        'Guardian Name *',
                        _guardianCtrl,
                        inputFormatters: [nameFormatter],
                      ),
                    ],
                    const SizedBox(height: 12),
                    _responsivePair(
                      narrow,
                      _field(
                        'Emergency Contact Person *',
                        _emergencyNameCtrl,
                        inputFormatters: [nameFormatter],
                      ),
                      _field(
                        'Emergency Contact Number *',
                        _emergencyPhoneCtrl,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [PhoneNumberFormatter()],
                        hint: '09XX XXX XXXX',
                      ),
                    ),
                    const SizedBox(height: 12),
                    _responsivePair(
                      narrow,
                      _field('Permanent Address *', _permanentAddressCtrl),
                      _field(
                        'Contact Number *',
                        _contactNumberCtrl,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [PhoneNumberFormatter()],
                        hint: '09XX XXX XXXX',
                      ),
                    ),
                    const SizedBox(height: 12),
                    _field(
                      'General Weighted Average (Last Semester Attended) *',
                      _gwaCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        DecimalNumberFormatter(
                          maxWholeDigits: 1,
                          maxDecimalDigits: 2,
                        ),
                      ],
                      hint: 'e.g. 1.75',
                    ),
                    const SizedBox(height: 24),
                    _sectionTitle('2. FAMILY BACKGROUND'),
                    const SizedBox(height: 12),
                    _responsivePair(
                      narrow,
                      _field(
                        "Father's Name",
                        _fatherNameCtrl,
                        inputFormatters: [nameFormatter],
                      ),
                      _field(
                        "Father's Age",
                        _fatherAgeCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(3),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _responsivePair(
                      narrow,
                      _field("Father's Occupation", _fatherOccCtrl),
                      _field(
                        "Father's Net Annual Income",
                        _fatherIncomeCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          DecimalNumberFormatter(
                            maxWholeDigits: 9,
                            maxDecimalDigits: 2,
                          ),
                        ],
                        hint: 'e.g. 120000',
                      ),
                    ),
                    const SizedBox(height: 12),
                    _responsivePair(
                      narrow,
                      _field(
                        "Mother's Name",
                        _motherNameCtrl,
                        inputFormatters: [nameFormatter],
                      ),
                      _field(
                        "Mother's Age",
                        _motherAgeCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(3),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _responsivePair(
                      narrow,
                      _field("Mother's Occupation", _motherOccCtrl),
                      _field(
                        "Mother's Net Annual Income",
                        _motherIncomeCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          DecimalNumberFormatter(
                            maxWholeDigits: 9,
                            maxDecimalDigits: 2,
                          ),
                        ],
                        hint: 'e.g. 120000',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () => setState(
                          () => _familyAddressCtrl.text =
                              _permanentAddressCtrl.text,
                        ),
                        icon: const Icon(Icons.copy_all_outlined, size: 15),
                        label: const Text('Same as Permanent Address'),
                        style: TextButton.styleFrom(
                          foregroundColor: AppTheme.maroon,
                          textStyle: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    _responsivePair(
                      narrow,
                      _field('Family Home Address', _familyAddressCtrl),
                      _field(
                        'Family Contact Number/s',
                        _familyContactCtrl,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [PhoneNumberFormatter()],
                        hint: '09XX XXX XXXX',
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Brothers / Sisters (Optional)',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.slate800,
                            ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () => setState(
                            () => _siblings.add(_SiblingControllers()),
                          ),
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('Add sibling'),
                        ),
                      ],
                    ),
                    for (var i = 0; i < _siblings.length; i++)
                      _siblingCard(i, narrow),
                    const SizedBox(height: 10),
                    _responsiveTriple(
                      narrow,
                      _field(
                        'Total Siblings',
                        _totalSiblingsCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(2),
                        ],
                      ),
                      _field(
                        'Working Siblings',
                        _workingSiblingsCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(2),
                        ],
                      ),
                      _field(
                        'Studying Siblings',
                        _studyingSiblingsCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(2),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    _sectionTitle('3. REASONS & ORGANIZATIONS'),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _reasonsCtrl,
                      minLines: 3,
                      maxLines: 6,
                      onChanged: (_) {
                        if (_error != null) setState(() => _error = null);
                      },
                      decoration: _decoration(
                        'Reason/s for Availing Student Assistantship *',
                        hint:
                            'Explain briefly why you are applying to be a Student Assistant.',
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Current Membership in Organizations (Optional)',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.slate800,
                            ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () =>
                              setState(() => _orgs.add(_OrgControllers())),
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('Add organization'),
                        ),
                      ],
                    ),
                    for (var i = 0; i < _orgs.length; i++) _orgCard(i, narrow),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.slate50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.slate200),
                      ),
                      child: const Text(
                        'I hereby certify that the above information is true '
                        'and correct. Any misinterpretation of facts will '
                        'render this form invalid and will immediately '
                        'disqualify my application to this student '
                        'assistantship.',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AppTheme.slate600,
                          fontStyle: FontStyle.italic,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _footer(narrow),
          ],
        ),
      ),
    );
  }

  Widget _summaryBanner(bool narrow) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.slate50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.slate200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'A.Y. ${widget.academicYear}',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: AppTheme.maroon,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text(
                'Semester:',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.slate700,
                ),
              ),
              for (final sem in ApplicationFormData.semesters)
                ChoiceChip(
                  label: Text(sem),
                  selected: _semester == sem,
                  selectedColor: AppTheme.maroon,
                  labelStyle: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: _semester == sem ? Colors.white : AppTheme.slate700,
                  ),
                  showCheckmark: false,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => setState(() => _semester = sem),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _photoPicker() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.slate50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.slate200),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.slate200),
            ),
            child: _photoBytes != null
                ? Image.memory(_photoBytes!, fit: BoxFit.cover)
                : const Center(
                    child: Text(
                      '2x2',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.slate500,
                      ),
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '2 x 2 ID Picture (Optional)',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.slate800,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Embedded into the form box (JPG or PNG, up to 5 MB).',
                  style: TextStyle(fontSize: 11, color: AppTheme.slate500),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _pickPhoto,
                      icon: const Icon(Icons.photo_camera_outlined, size: 15),
                      label: Text(
                        _photoBytes == null
                            ? 'Choose 2x2 photo'
                            : 'Change photo',
                      ),
                    ),
                    if (_photoBytes != null)
                      TextButton(
                        onPressed: () => setState(() {
                          _photoBytes = null;
                          _photoExt = null;
                        }),
                        child: const Text('Remove'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _siblingCard(int index, bool narrow) {
    final s = _siblings[index];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.slate50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.slate200),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Sibling ${index + 1}',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.slate600,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Remove sibling',
                onPressed: () {
                  setState(() {
                    _siblings.removeAt(index).dispose();
                  });
                },
                icon: const Icon(
                  Icons.delete_outline,
                  size: 18,
                  color: AppTheme.red500,
                ),
              ),
            ],
          ),
          _responsivePair(
            narrow,
            _field('Name', s.name, inputFormatters: [nameFormatter]),
            _field(
              'Age',
              s.age,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(3),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _responsivePair(
            narrow,
            _field('School / Location or Occupation / Company', s.schoolOrWork),
            _field('Program Presently Taking / Finished', s.program),
          ),
        ],
      ),
    );
  }

  Widget _orgCard(int index, bool narrow) {
    final o = _orgs[index];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.slate50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.slate200),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Organization ${index + 1}',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.slate600,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Remove organization',
                onPressed: () {
                  setState(() {
                    _orgs.removeAt(index).dispose();
                  });
                },
                icon: const Icon(
                  Icons.delete_outline,
                  size: 18,
                  color: AppTheme.red500,
                ),
              ),
            ],
          ),
          _responsivePair(
            narrow,
            _field('Name of Organization/s', o.name),
            _field('Position', o.position),
          ),
        ],
      ),
    );
  }

  Widget _footer(bool narrow) {
    final buttons = [
      AsyncButton(
        kind: AsyncButtonKind.outlined,
        onPressed: _previewForm,
        icon: Icons.visibility_outlined,
        label: 'Preview Form',
        busyLabel: 'Preparing…',
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.maroon,
          side: const BorderSide(color: AppTheme.maroon),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
      ElevatedButton.icon(
        onPressed: _save,
        icon: const Icon(Icons.check_rounded, size: 17),
        label: const Text('Save Form'),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.maroon,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    ];

    return Container(
      padding: EdgeInsets.fromLTRB(
        narrow ? 16 : 24,
        12,
        narrow ? 16 : 24,
        16,
      ),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppTheme.slate100)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.red50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppTheme.red500.withValues(alpha: 0.4),
                ),
              ),
              child: Text(
                _error!,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.red500,
                ),
              ),
            ),
          ],
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 10,
            runSpacing: 10,
            children: buttons,
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) => Text(
    title,
    style: const TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w800,
      color: AppTheme.maroon,
      letterSpacing: 0.8,
    ),
  );

  Widget _responsivePair(bool narrow, Widget first, Widget second) {
    if (narrow) {
      return Column(children: [first, const SizedBox(height: 12), second]);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: first),
        const SizedBox(width: 12),
        Expanded(child: second),
      ],
    );
  }

  Widget _responsiveTriple(
    bool narrow,
    Widget first,
    Widget second,
    Widget third,
  ) {
    if (narrow) {
      return Column(
        children: [
          first,
          const SizedBox(height: 10),
          second,
          const SizedBox(height: 10),
          third,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: first),
        const SizedBox(width: 10),
        Expanded(child: second),
        const SizedBox(width: 10),
        Expanded(child: third),
      ],
    );
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    bool readOnly = false,
    String? hint,
    String? helperText,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
  }) => TextField(
    controller: controller,
    readOnly: readOnly,
    keyboardType: keyboardType,
    inputFormatters: inputFormatters,
    onChanged: (_) {
      if (_error != null) setState(() => _error = null);
    },
    style: const TextStyle(fontSize: 13, color: AppTheme.slate800),
    decoration: _decoration(
      label,
      hint: hint,
      helperText: helperText,
      readOnly: readOnly,
    ),
  );

  Widget _dropdown(
    String label,
    String value,
    List<String> options,
    ValueChanged<String?> onChanged,
  ) => DropdownButtonFormField<String>(
    initialValue: options.contains(value) ? value : null,
    isExpanded: true,
    items: [
      for (final opt in options)
        DropdownMenuItem<String>(
          value: opt,
          child: Text(opt, overflow: TextOverflow.ellipsis),
        ),
    ],
    onChanged: onChanged,
    style: const TextStyle(
      fontFamily: 'Inter',
      fontSize: 13,
      color: AppTheme.slate800,
    ),
    decoration: _decoration(label),
  );

  InputDecoration _decoration(
    String label, {
    String? hint,
    String? helperText,
    bool readOnly = false,
    Widget? suffixIcon,
  }) => InputDecoration(
    labelText: label,
    hintText: hint,
    helperText: helperText,
    helperMaxLines: 2,
    suffixIcon: suffixIcon,
    isDense: true,
    filled: true,
    fillColor: readOnly ? AppTheme.slate100 : Colors.white,
    labelStyle: const TextStyle(fontSize: 12, color: AppTheme.slate600),
    hintStyle: const TextStyle(fontSize: 12, color: AppTheme.slate400),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: AppTheme.slate200),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: AppTheme.slate200),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: AppTheme.maroon, width: 1.5),
    ),
  );
}
