import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../models/app_state.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../utils/password_validator.dart';
import 'auth_scaffold.dart';

/// Formats digits as the user types into "09XX XXX XXXX" and caps the
/// input at 11 digits (the length of a PH mobile number).
class _PhilippineMobileNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text
        .replaceAll(RegExp(r'\D'), '')
        .substring(0, newValue.text.replaceAll(RegExp(r'\D'), '').length > 11
            ? 11
            : newValue.text.replaceAll(RegExp(r'\D'), '').length);

    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      buffer.write(digits[i]);
      if (i == 3 || i == 6) {
        if (i != digits.length - 1) buffer.write(' ');
      }
    }

    final formatted = buffer.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class RegisterScreen extends StatefulWidget {
  final VoidCallback onBackToLogin;

  /// When provided, the back control returns the visitor to the landing page
  /// rather than to login — they may have arrived straight from "Get started".
  final VoidCallback? onBack;

  const RegisterScreen({
    super.key,
    required this.onBackToLogin,
    this.onBack,
  });

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _studentIdCtrl = TextEditingController();
  final _courseProgramCtrl = TextEditingController();
  final String _role = 'Student';
  String _department = 'College of Information and Computing Sciences';
  String _campus = 'Boac Campus';
  String _yearLevel = '1st Year';
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _error;
  PasswordValidationResult? _passwordValidation;

  bool _isValidEmail(String email) {
    return RegExp(
      r"^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@(gmail\.com|marsu\.edu\.ph)$",
    ).hasMatch(email);
  }

  bool _isValidPhoneNumber(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    // PH mobile numbers are 11 digits starting with "09" (e.g. 09171234567).
    return RegExp(r'^09\d{9}$').hasMatch(digits);
  }

  void _handleRegister() async {
    if (_nameCtrl.text.trim().isEmpty ||
        _emailCtrl.text.trim().isEmpty ||
        _passwordCtrl.text.isEmpty ||
        _phoneCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Please fill in all required fields.');
      return;
    }

    final email = _emailCtrl.text.trim().toLowerCase();
    if (!_isValidEmail(email)) {
      setState(
        () => _error =
            'Enter a valid Gmail address or MSU email (@marsu.edu.ph).',
      );
      return;
    }

    if (!_isValidPhoneNumber(_phoneCtrl.text)) {
      setState(
        () => _error = 'Enter a valid phone number, e.g. 09XX XXX XXXX.',
      );
      return;
    }

    final validation = PasswordValidator.validate(_passwordCtrl.text);
    if (!validation.isValid) {
      setState(() {
        _passwordValidation = validation;
        _error = 'Please meet the password requirements below.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
      _passwordValidation = null;
    });
    await Future.delayed(const Duration(milliseconds: 800));

    if (!mounted) return;
    final user = User(
      id: 'u_${DateTime.now().millisecondsSinceEpoch}',
      name: _nameCtrl.text.trim(),
      email: email,
      role: _role,
      department: _department,
      campus: _campus,
      phone: _phoneCtrl.text.trim(),
      studentId: _studentIdCtrl.text.trim().isEmpty
          ? null
          : _studentIdCtrl.text.trim(),
      courseProgram: _courseProgramCtrl.text.trim().isEmpty
          ? null
          : _courseProgramCtrl.text.trim(),
      yearLevel: _yearLevel,
    );

    final appState = context.read<AppState>();
    final authError = await appState.registerWithEmail(user, _passwordCtrl.text);
    if (!mounted) return;

    if (authError != null) {
      setState(() {
        _isLoading = false;
        _error = authError;
      });
      return;
    }

    setState(() => _isLoading = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'Account created! We sent a verification link to your email — '
          'please verify it before logging in.',
        ),
        backgroundColor: AppTheme.emerald500,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 4),
      ),
    );

    // Send the user back to the login screen now that their account exists
    // but is still pending Gmail verification.
    widget.onBackToLogin();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _phoneCtrl.dispose();
    _studentIdCtrl.dispose();
    _courseProgramCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Create your account',
      subtitle: 'Register to apply as a student assistant',
      // Wider than login: the student details below pair up two per row.
      maxFormWidth: 560,
      onBack: widget.onBack,
      brandPoints: const [
        AuthBrandPoint(
          Icons.how_to_reg_outlined,
          'Apply once',
          'Submit your requirements online and follow where your application stands.',
        ),
        AuthBrandPoint(
          Icons.school_outlined,
          'Built around your duty',
          'Your schedule, tasks, and accomplishment reports in one place.',
        ),
        AuthBrandPoint(
          Icons.verified_user_outlined,
          'Verified accounts',
          'We email a verification link before your first login.',
        ),
      ],
      children: _buildFormFields(),
    );
  }

  List<Widget> _buildFormFields() {
    final state = context.watch<AppState>();

    return [
      if (_error != null) ...[
        AuthErrorBanner(message: _error!),
        const SizedBox(height: 22),
      ],

      // ── Your account ──────────────────────────────────────────────────
      const AuthSectionHeading(label: 'Your account'),
      const SizedBox(height: 18),

      AuthField(
        label: 'Full name',
        child: TextFormField(
          controller: _nameCtrl,
          onChanged: _clearError,
          decoration: const InputDecoration(
            hintText: 'Juan dela Cruz',
            prefixIcon: Icon(
              Icons.person_outline_rounded,
              color: AppTheme.maroon,
              size: 20,
            ),
          ),
        ),
      ),
      const SizedBox(height: 18),

      AuthField(
        label: 'Email address',
        child: TextFormField(
          controller: _emailCtrl,
          keyboardType: TextInputType.emailAddress,
          onChanged: _clearError,
          decoration: const InputDecoration(
            hintText: 'juan@gmail.com or juan@marsu.edu.ph',
            prefixIcon: Icon(
              Icons.mail_outline_rounded,
              color: AppTheme.maroon,
              size: 20,
            ),
          ),
        ),
      ),
      const SizedBox(height: 18),

      AuthField(
        label: 'Password',
        child: TextFormField(
          controller: _passwordCtrl,
          obscureText: _obscurePassword,
          onChanged: (value) {
            if (_error != null) setState(() => _error = null);
            setState(
              () => _passwordValidation = PasswordValidator.validate(value),
            );
          },
          decoration: InputDecoration(
            hintText: '••••••••',
            prefixIcon: const Icon(
              Icons.lock_outline_rounded,
              color: AppTheme.maroon,
              size: 20,
            ),
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                color: AppTheme.slate400,
                size: 20,
              ),
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
        ),
      ),
      if (_passwordValidation != null) ...[
        const SizedBox(height: 12),
        _buildPasswordRequirements(_passwordValidation!),
      ],
      const SizedBox(height: 32),

      // ── Student details ───────────────────────────────────────────────
      const AuthSectionHeading(label: 'Student details'),
      const SizedBox(height: 18),

      AuthFieldPair(
        left: AuthField(
          label: 'Phone number',
          child: TextFormField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            inputFormatters: [_PhilippineMobileNumberFormatter()],
            onChanged: _clearError,
            decoration: const InputDecoration(
              hintText: '09XX XXX XXXX',
              prefixIcon: Icon(
                Icons.phone_outlined,
                color: AppTheme.maroon,
                size: 20,
              ),
            ),
          ),
        ),
        right: AuthField(
          label: 'Student ID',
          child: TextFormField(
            controller: _studentIdCtrl,
            onChanged: _clearError,
            decoration: const InputDecoration(
              hintText: 'e.g. 23B0626',
              prefixIcon: Icon(
                Icons.badge_outlined,
                color: AppTheme.maroon,
                size: 20,
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 18),

      AuthFieldPair(
        left: AuthField(
          label: 'Course/Program',
          child: TextFormField(
            controller: _courseProgramCtrl,
            onChanged: _clearError,
            decoration: const InputDecoration(
              hintText: 'e.g. BSIT',
              prefixIcon: Icon(
                Icons.school_outlined,
                color: AppTheme.maroon,
                size: 20,
              ),
            ),
          ),
        ),
        right: AuthField(
          label: 'Year level',
          child: DropdownButtonFormField<String>(
            initialValue: _yearLevel,
            isExpanded: true,
            decoration: const InputDecoration(
              prefixIcon: Icon(
                Icons.timeline_outlined,
                color: AppTheme.maroon,
                size: 20,
              ),
            ),
            items: const [
              DropdownMenuItem(value: '1st Year', child: Text('1st Year')),
              DropdownMenuItem(value: '2nd Year', child: Text('2nd Year')),
              DropdownMenuItem(value: '3rd Year', child: Text('3rd Year')),
              DropdownMenuItem(value: '4th Year', child: Text('4th Year')),
            ],
            onChanged: (v) => setState(() => _yearLevel = v ?? _yearLevel),
          ),
        ),
      ),
      const SizedBox(height: 18),

      AuthFieldPair(
        left: AuthField(
          label: 'Department',
          child: DropdownButtonFormField<String>(
            initialValue: _department,
            isExpanded: true,
            decoration: const InputDecoration(
              prefixIcon: Icon(
                Icons.business_outlined,
                color: AppTheme.maroon,
                size: 20,
              ),
            ),
            items: state.departments
                .map(
                  (d) => DropdownMenuItem(
                    value: d,
                    child: Text(d, overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(),
            onChanged: (v) => setState(() => _department = v!),
          ),
        ),
        right: AuthField(
          label: 'Campus',
          child: DropdownButtonFormField<String>(
            initialValue: _campus,
            isExpanded: true,
            decoration: const InputDecoration(
              prefixIcon: Icon(
                Icons.location_city_outlined,
                color: AppTheme.maroon,
                size: 20,
              ),
            ),
            items: state.campuses
                .map(
                  (c) => DropdownMenuItem(
                    value: c,
                    child: Text(c, overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(),
            onChanged: (v) => setState(() => _campus = v!),
          ),
        ),
      ),
      const SizedBox(height: 32),

      AuthPrimaryButton(
        label: 'Create Account',
        icon: Icons.arrow_forward_rounded,
        isLoading: _isLoading,
        onPressed: _handleRegister,
      ),
      const SizedBox(height: 22),

      AuthFooterLink(
        prompt: 'Already have an account?',
        action: 'Log in',
        onTap: widget.onBackToLogin,
      ),
    ];
  }

  void _clearError(String _) {
    if (_error != null) setState(() => _error = null);
  }

  Widget _buildPasswordRequirements(PasswordValidationResult validation) {
    final rules = <_PasswordRequirement>[
      _PasswordRequirement(
        'At least 8 characters',
        !validation.errors.contains(
          'Password must be at least 8 characters long.',
        ),
      ),
      _PasswordRequirement(
        'Uppercase and lowercase letters',
        !validation.errors.contains(
          'Password must include both uppercase and lowercase letters.',
        ),
      ),
      _PasswordRequirement(
        'At least one number',
        !validation.errors.contains(
          'Password must include at least one number.',
        ),
      ),
      _PasswordRequirement(
        'At least one special character',
        !validation.errors.contains(
          'Password must include at least one special character.',
        ),
      ),
      _PasswordRequirement(
        'No whitespace',
        !validation.errors.contains('Password must not contain whitespace.'),
      ),
      _PasswordRequirement(
        'No common sequences',
        !(validation.errors.contains(
              'Password should not contain a common alphabetical sequence.',
            ) ||
            validation.errors.contains(
              'Password should not contain a common numerical sequence.',
            ) ||
            validation.errors.contains(
              'Password should not contain a common keyboard sequence.',
            )),
      ),
    ];

    final metCount = rules.where((r) => r.met).length;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.slate50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.slate200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Password requirements',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.slate700,
                  ),
                ),
              ),
              Text(
                '$metCount of ${rules.length}',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: metCount == rules.length
                      ? AppTheme.emerald500
                      : AppTheme.slate400,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Two per row where the panel is wide enough, so the checklist does
          // not push the rest of the form down a full six lines.
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 380 ? 2 : 1;
              const gap = 10.0;
              final itemWidth =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: 8,
                children: [
                  for (final rule in rules)
                    SizedBox(
                      width: itemWidth,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            rule.met
                                ? Icons.check_circle_rounded
                                : Icons.circle_outlined,
                            size: 15,
                            color: rule.met
                                ? AppTheme.emerald500
                                : AppTheme.slate300,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              rule.label,
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.35,
                                color: rule.met
                                    ? AppTheme.slate600
                                    : AppTheme.slate500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _PasswordRequirement {
  const _PasswordRequirement(this.label, this.met);

  final String label;
  final bool met;
}
