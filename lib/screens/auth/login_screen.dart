import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/shared_widgets.dart';

class LoginScreen extends StatefulWidget {
  final VoidCallback onShowRegister;

  /// When provided, a back control returns the visitor to the landing page.
  final VoidCallback? onBack;

  const LoginScreen({
    super.key,
    required this.onShowRegister,
    this.onBack,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _rememberMe = false;
  String? _error;

  void _handleLogin() async {
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Please enter both email and password.');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });
    await Future.delayed(const Duration(milliseconds: 800));

    final appState = context.read<AppState>();

    final authError = await appState.signInWithEmailAndPassword(
      email,
      password,
    );
    if (!mounted) return;

    if (authError == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Login successful! Welcome back.'),
          backgroundColor: AppTheme.emerald500,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 2),
        ),
      );
    } else {
      setState(() {
        _isLoading = false;
        _error = authError;
      });
    }
  }

  void _handleForgotPassword() {
    final resetEmailCtrl = TextEditingController(text: _emailCtrl.text.trim());
    String? dialogError;
    bool isSending = false;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: const Text(
                'Reset your password',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Enter the email you used to register. We\'ll send you a link to reset your password.',
                    style: TextStyle(fontSize: 13, color: AppTheme.slate600),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: resetEmailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'juan@gmail.com or juan@marsu.edu.ph',
                      prefixIcon: const Icon(
                        Icons.mail_outline_rounded,
                        color: AppTheme.maroon,
                        size: 20,
                      ),
                      errorText: dialogError,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isSending
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.maroon,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: isSending
                      ? null
                      : () async {
                          final email = resetEmailCtrl.text.trim();
                          if (email.isEmpty) {
                            setDialogState(
                              () => dialogError = 'Please enter your email.',
                            );
                            return;
                          }

                          setDialogState(() {
                            isSending = true;
                            dialogError = null;
                          });

                          final appState = context.read<AppState>();
                          final error = await appState.sendPasswordResetEmail(
                            email,
                          );

                          if (error != null) {
                            setDialogState(() {
                              isSending = false;
                              dialogError = error;
                            });
                            return;
                          }

                          if (!dialogContext.mounted) return;
                          Navigator.of(dialogContext).pop();

                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'If an account exists for $email, a password reset link has been sent.',
                              ),
                              backgroundColor: AppTheme.emerald500,
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              margin: const EdgeInsets.all(16),
                              duration: const Duration(seconds: 4),
                            ),
                          );
                        },
                  child: isSending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.2,
                          ),
                        )
                      : const Text('Send reset link'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _handleGoogleSignIn() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final appState = context.read<AppState>();
    final authError = await appState.signInWithGoogle();
    if (!mounted) return;

    if (authError != null) {
      setState(() {
        _isLoading = false;
        _error = authError;
      });
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
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
            child: Stack(
              children: [
                Positioned.fill(
                  child: isMobile
                      ? _buildMobileLayout()
                      : _buildDesktopLayout(),
                ),
                if (widget.onBack != null)
                  Positioned(
                    top: 0,
                    left: 0,
                    child: SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: IconButton(
                          onPressed: widget.onBack,
                          tooltip: 'Back to home',
                          icon: Icon(
                            Icons.arrow_back_rounded,
                            // The mobile layout opens on the maroon hero, the
                            // desktop one on the white form column.
                            color: isMobile
                                ? Colors.white
                                : AppTheme.slate600,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
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
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
            physics: const BouncingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Column(
                    children: [
                      const AppLogo(size: 76),
                      const SizedBox(height: 24),
                      _buildHeaderText(),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
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
                  const SizedBox(height: 28),
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
        // FIX: without this, the non-positioned SafeArea/Column child
        // (which shrink-wraps due to mainAxisSize.min) gets pinned to
        // the Stack's default topStart alignment instead of centered,
        // pushing the whole logo/title block to the left edge.
        alignment: Alignment.topCenter,
        children: [
          Positioned(
            top: -40,
            right: -40,
            child: _circle(150, AppTheme.gold300.withValues(alpha: 0.14)),
          ),
          Positioned(
            bottom: -46,
            left: -50,
            child: _circle(130, Colors.white.withValues(alpha: 0.06)),
          ),
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 60),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 16),
                  const AppLogo(size: 64),
                  const SizedBox(height: 14),
                  const Text(
                    'SAIS',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.goldLight,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Student Assistant Information System',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Color(0xFFFFD88A),
                      height: 1.3,
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
    return Column(
      crossAxisAlignment: mobile
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: [
        Text(
          'Welcome back',
          textAlign: mobile ? TextAlign.left : TextAlign.center,
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: AppTheme.slate900,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Log in to continue to your account',
          textAlign: mobile ? TextAlign.left : TextAlign.center,
          style: const TextStyle(
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
    return [
      if (_error != null) ...[
        _buildErrorBanner(_error!),
        const SizedBox(height: 16),
      ],

      _buildFieldLabel('Email address'),
      const SizedBox(height: 8),
      TextField(
        controller: _emailCtrl,
        keyboardType: TextInputType.emailAddress,
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
        decoration: const InputDecoration(
          hintText: 'name@univ.edu',
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
      TextField(
        controller: _passwordCtrl,
        obscureText: _obscurePassword,
        onSubmitted: (_) => _handleLogin(),
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
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
      const SizedBox(height: 16),

      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          GestureDetector(
            onTap: () => setState(() => _rememberMe = !_rememberMe),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: Checkbox(
                    value: _rememberMe,
                    onChanged: (value) =>
                        setState(() => _rememberMe = value ?? false),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(5),
                    ),
                    activeColor: AppTheme.maroon,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Remember me',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppTheme.slate600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: _handleForgotPassword,
            child: const Text(
              'Forgot password?',
              style: TextStyle(
                fontSize: 13,
                color: AppTheme.maroon,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 28),

      _buildPrimaryButton(
        label: 'Log In',
        icon: Icons.arrow_forward_rounded,
        isLoading: _isLoading,
        onPressed: _handleLogin,
      ),
      const SizedBox(height: 16),
      _buildGoogleButton(),
      const SizedBox(height: 24),

      Center(
        child: GestureDetector(
          onTap: widget.onShowRegister,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: RichText(
              text: const TextSpan(
                text: "Don't have an account? ",
                style: TextStyle(
                  color: AppTheme.slate500,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
                children: [
                  TextSpan(
                    text: 'Register here',
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

  Widget _buildGoogleButton() {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: OutlinedButton(
        onPressed: _handleGoogleSignIn,
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: AppTheme.slate300),
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/images/google_logo.png', width: 20, height: 20),
            const SizedBox(width: 12),
            const Text(
              'Log in with Google',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppTheme.slate700,
              ),
            ),
          ],
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
            child: _circle(180, AppTheme.gold300.withValues(alpha: 0.10)),
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
                  'SAIS',
                  style: TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.goldLight,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Student Assistant\nInformation System',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: Color(0xFFFFD88A),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 48),

                ...[
                  (
                    Icons.shield_outlined,
                    'Secure & Reliable',
                    'Enterprise-grade security for your data',
                  ),
                  (
                    Icons.people_outline,
                    'Easy Management',
                    'Streamlined interface for all roles',
                  ),
                  (
                    Icons.access_time,
                    'Real-time Tracking',
                    'Monitor attendance and tasks live',
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
            width: 220,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFFFFD88A),
                    fontSize: 12,
                    height: 1.3,
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