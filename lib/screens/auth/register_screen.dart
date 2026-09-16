import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../models/app_state.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../utils/password_validator.dart';
import '../../widgets/shared_widgets.dart';

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
  const RegisterScreen({super.key, required this.onBackToLogin});

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
        () => _error =
            'Enter a valid phone number, e.g. 09XX XXX XXXX.',
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
      studentId: _studentIdCtrl.text.trim().isEmpty ? null : _studentIdCtrl.text.trim(),
      courseProgram: _courseProgramCtrl.text.trim().isEmpty ? null : _courseProgramCtrl.text.trim(),
      yearLevel: _yearLevel,
    );

    final appState = context.read<AppState>();
    final authError = await appState.registerWithEmail(
      user,
      _passwordCtrl.text,
    );
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
          'please verify it before signing in.',
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
    return Scaffold(
      backgroundColor: Colors.white,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isMobile = constraints.maxWidth < 900;
          return SizedBox(
            height: double.infinity,
            width: double.infinity,
            child: isMobile ? _buildMobileLayout() : _buildDesktopLayout(),
          );
        },
      ),
    );
  }

  // ─── Desktop / tablet layout (side-by-side) ───────────────────────────
  Widget _buildDesktopLayout() {
    return Row(
      children: [
        Expanded(flex: 5, child: _buildDesktopForm()),
        Expanded(flex: 5, child: _buildBrandingSection()),
      ],
    );
  }

  Widget _buildDesktopForm() {
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 36),
            physics: const BouncingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Column(
                    children: [
                      const AppLogo(size: 68),
                      const SizedBox(height: 22),
                      _buildHeaderText(),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                ..._buildFormFields(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Mobile layout (gradient hero + overlapping sheet) ────────────────
  Widget _buildMobileLayout() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        children: [
          _buildMobileHero(),
          Transform.translate(
            offset: const Offset(0, -28),
            child: Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
              ),
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 24),
                      decoration: BoxDecoration(
                        color: AppTheme.slate200,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  _buildHeaderText(mobile: true),
                  const SizedBox(height: 26),
                  ..._buildFormFields(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileHero() {
    return Container(
      width: double.infinity,
      clipBehavior: Clip.hardEdge,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.maroon, AppTheme.maroonDark],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -36,
            right: -36,
            child: _circle(130, AppTheme.gold300.withValues(alpha: 0.14)),
          ),
          Positioned(
            bottom: -40,
            left: -46,
            child: _circle(120, Colors.white.withValues(alpha: 0.06)),
          ),
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 48),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      onPressed: widget.onBackToLogin,
                      icon: const Icon(
                        Icons.arrow_back_rounded,
                        color: Colors.white,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const AppLogo(size: 56),
                  const SizedBox(height: 12),
                  const Text(
                    'Join SAIS',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.goldLight,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Create an account to get started',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Color(0xFFFFD88A),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Shared header ──────────────────────────────────────────────────
  Widget _buildHeaderText({bool mobile = false}) {
    if (mobile) {
      // Header is shown in the hero on mobile; keep the sheet uncluttered.
      return const SizedBox.shrink();
    }
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          'Create account',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: AppTheme.slate900,
            letterSpacing: -0.3,
          ),
        ),
        SizedBox(height: 6),
        Text(
          'Join SAIS — Student Assistant Information System',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            color: AppTheme.slate500,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }

  // ─── Shared form fields ─────────────────────────────────────────────
  List<Widget> _buildFormFields() {
    final state = context.watch<AppState>();

    return [
      if (_error != null) ...[
        _buildErrorBanner(_error!),
        const SizedBox(height: 16),
      ],

      _buildFieldLabel('Full name'),
      const SizedBox(height: 8),
      TextFormField(
        controller: _nameCtrl,
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
        decoration: const InputDecoration(
          hintText: 'Juan dela Cruz',
          prefixIcon: Icon(
            Icons.person_outline_rounded,
            color: AppTheme.maroon,
            size: 20,
          ),
        ),
      ),
      const SizedBox(height: 18),

      _buildFieldLabel('Email address'),
      const SizedBox(height: 8),
      TextFormField(
        controller: _emailCtrl,
        keyboardType: TextInputType.emailAddress,
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
        decoration: const InputDecoration(
          hintText: 'juan@gmail.com or juan@marsu.edu.ph',
          prefixIcon: Icon(
            Icons.mail_outline_rounded,
            color: AppTheme.maroon,
            size: 20,
          ),
        ),
      ),
      const SizedBox(height: 18),

      _buildFieldLabel('Password'),
      const SizedBox(height: 8),
      TextFormField(
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
      const SizedBox(height: 10),
      if (_passwordValidation != null) ...[
        _buildPasswordRequirements(_passwordValidation!),
        const SizedBox(height: 10),
      ],
      const SizedBox(height: 8),

      _buildFieldLabel('Phone number'),
      const SizedBox(height: 8),
      TextFormField(
        controller: _phoneCtrl,
        keyboardType: TextInputType.phone,
        inputFormatters: [_PhilippineMobileNumberFormatter()],
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
        decoration: const InputDecoration(
          hintText: '09XX XXX XXXX',
          prefixIcon: Icon(
            Icons.phone_outlined,
            color: AppTheme.maroon,
            size: 20,
          ),
        ),
      ),
      const SizedBox(height: 18),

      _buildFieldLabel('Student ID'),
      const SizedBox(height: 8),
      TextFormField(
        controller: _studentIdCtrl,
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
        decoration: const InputDecoration(
          hintText: 'e.g. 23B0626',
          prefixIcon: Icon(
            Icons.badge_outlined,
            color: AppTheme.maroon,
            size: 20,
          ),
        ),
      ),
      const SizedBox(height: 18),

      _buildFieldLabel('Course/Program'),
      const SizedBox(height: 8),
      TextFormField(
        controller: _courseProgramCtrl,
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
        decoration: const InputDecoration(
          hintText: 'e.g. BSIT',
          prefixIcon: Icon(
            Icons.school_outlined,
            color: AppTheme.maroon,
            size: 20,
          ),
        ),
      ),
      const SizedBox(height: 18),

      _buildFieldLabel('Year level'),
      const SizedBox(height: 8),
      DropdownButtonFormField<String>(
        value: _yearLevel,
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
      const SizedBox(height: 18),

      _buildFieldLabel('Department'),
      const SizedBox(height: 8),
      DropdownButtonFormField<String>(
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
      const SizedBox(height: 18),

      _buildFieldLabel('Campus'),
      const SizedBox(height: 8),
      DropdownButtonFormField<String>(
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
      const SizedBox(height: 28),

      _buildPrimaryButton(
        label: 'Create Account',
        icon: Icons.arrow_forward_rounded,
        isLoading: _isLoading,
        onPressed: _handleRegister,
      ),
      const SizedBox(height: 22),

      Center(
        child: GestureDetector(
          onTap: widget.onBackToLogin,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: RichText(
              text: const TextSpan(
                text: 'Already have an account? ',
                style: TextStyle(
                  color: AppTheme.slate500,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
                children: [
                  TextSpan(
                    text: 'Sign in',
                    style: TextStyle(
                      color: AppTheme.maroon,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ];
  }

  Widget _buildFieldLabel(String text) => Text(
    text,
    style: const TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: AppTheme.slate700,
    ),
  );

  Widget _buildErrorBanner(String message) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.red50,
        border: Border.all(color: AppTheme.red500.withValues(alpha: 0.25)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: AppTheme.red500,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: AppTheme.red500, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPasswordRequirements(PasswordValidationResult validation) {
    final rules = <_PasswordRequirement>[
      _PasswordRequirement(
        'At least 8 characters',
        validation.errors.contains(
              'Password must be at least 8 characters long.',
            )
            ? null
            : '✓',
      ),
      _PasswordRequirement(
        'Uppercase and lowercase letters',
        validation.errors.contains(
              'Password must include both uppercase and lowercase letters.',
            )
            ? null
            : '✓',
      ),
      _PasswordRequirement(
        'At least one number',
        validation.errors.contains('Password must include at least one number.')
            ? null
            : '✓',
      ),
      _PasswordRequirement(
        'At least one special character',
        validation.errors.contains(
              'Password must include at least one special character.',
            )
            ? null
            : '✓',
      ),
      _PasswordRequirement(
        'No whitespace',
        validation.errors.contains('Password must not contain whitespace.')
            ? null
            : '✓',
      ),
      _PasswordRequirement(
        'No common sequences',
        validation.errors.contains(
                  'Password should not contain a common alphabetical sequence.',
                ) ||
                validation.errors.contains(
                  'Password should not contain a common numerical sequence.',
                ) ||
                validation.errors.contains(
                  'Password should not contain a common keyboard sequence.',
                )
            ? null
            : '✓',
      ),
    ];

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
          const Text(
            'Password requirements',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: AppTheme.slate700,
            ),
          ),
          const SizedBox(height: 8),
          ...rules.map(
            (rule) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Text(
                    rule.icon ?? '•',
                    style: TextStyle(
                      color: rule.icon == null
                          ? AppTheme.red500
                          : AppTheme.emerald500,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      rule.label,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppTheme.slate600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrimaryButton({
    required String label,
    required IconData icon,
    required bool isLoading,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            colors: [AppTheme.maroon, AppTheme.maroonDark],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: AppTheme.maroon.withValues(alpha: 0.32),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ElevatedButton(
          onPressed: isLoading ? null : onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: isLoading
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2.5,
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Icon(icon, size: 18, color: Colors.white),
                  ],
                ),
        ),
      ),
    );
  }

  /// Build branding section (desktop only)
  Widget _buildBrandingSection() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.maroon, AppTheme.maroonDark],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -60,
            right: -60,
            child: _circle(180, AppTheme.gold300.withValues(alpha: 0.1)),
          ),
          Positioned(
            bottom: -50,
            left: -50,
            child: _circle(160, AppTheme.gold300.withValues(alpha: 0.08)),
          ),
          Positioned(
            top: 80,
            right: 60,
            child: _circle(60, Colors.white.withValues(alpha: 0.06)),
          ),
          Padding(
            padding: const EdgeInsets.all(40),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Text(
                  'Join Us',
                  style: TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.goldLight,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Become part of our community',
                  style: TextStyle(
                    fontSize: 16,
                    color: Color(0xFFFFD88A),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 48),
                ...[
                  (
                    Icons.person_add_outlined,
                    'Quick Setup',
                    'Get started in minutes',
                  ),
                  (
                    Icons.shield_outlined,
                    'Secure & Safe',
                    'Your data is protected',
                  ),
                  (
                    Icons.mail_outline,
                    'Support Ready',
                    'Help when you need it',
                  ),
                ].map(
                  (e) => _FeatureTile(icon: e.$1, title: e.$2, subtitle: e.$3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Helper method to create circle widget
  Widget _circle(double size, Color color) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(shape: BoxShape.circle, color: color),
  );
}

class _PasswordRequirement {
  const _PasswordRequirement(this.label, this.icon);

  final String label;
  final String? icon;
}

class _FeatureTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _FeatureTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.gold400.withValues(alpha: 0.15),
              border: Border.all(color: AppTheme.gold300, width: 1),
            ),
            child: Icon(icon, color: AppTheme.goldLight, size: 20),
          ),
          const SizedBox(width: 14),
          SizedBox(
            width: 150,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFFFFD88A),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}