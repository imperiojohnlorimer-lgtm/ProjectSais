import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/app_state.dart';
import '../../theme/app_theme.dart';
import 'auth_scaffold.dart';

class LoginScreen extends StatefulWidget {
  final VoidCallback onShowRegister;

  /// When provided, a back control returns the visitor to the landing page.
  final VoidCallback? onBack;

  const LoginScreen({super.key, required this.onShowRegister, this.onBack});

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
    return AuthScaffold(
      title: 'Welcome back',
      subtitle: 'Log in to continue to your account',
      onBack: widget.onBack,
      brandPoints: const [
        AuthBrandPoint(
          Icons.access_time_filled,
          'Duty hours that add up',
          'Time in and out, and your monthly DTR fills itself.',
        ),
        AuthBrandPoint(
          Icons.calendar_today_outlined,
          'Know where you are posted',
          'Duty schedules per office, set by academic year.',
        ),
        AuthBrandPoint(
          Icons.description_outlined,
          'Paperwork, generated',
          'Contracts, endorsements, and evaluations from official templates.',
        ),
      ],
      children: _buildFormFields(),
    );
  }

  List<Widget> _buildFormFields() {
    return [
      if (_error != null) ...[
        AuthErrorBanner(message: _error!),
        const SizedBox(height: 18),
      ],

      AuthField(
        label: 'Email address',
        child: TextField(
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
      ),
      const SizedBox(height: 18),

      AuthField(
        label: 'Password',
        child: TextField(
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
      ),
      const SizedBox(height: 16),

      // Wrapped so the two controls stack instead of overflowing on the
      // narrowest phones.
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 8,
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

      AuthPrimaryButton(
        label: 'Log In',
        icon: Icons.arrow_forward_rounded,
        isLoading: _isLoading,
        onPressed: _handleLogin,
      ),
      const SizedBox(height: 20),

      _buildDivider(),
      const SizedBox(height: 20),

      _buildGoogleButton(),
      const SizedBox(height: 24),

      AuthFooterLink(
        prompt: "Don't have an account?",
        action: 'Register here',
        onTap: widget.onShowRegister,
      ),
    ];
  }

  Widget _buildDivider() {
    return const Row(
      children: [
        Expanded(child: Divider(color: AppTheme.slate200, height: 1)),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 14),
          child: Text(
            'or',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.slate400,
              letterSpacing: 0.5,
            ),
          ),
        ),
        Expanded(child: Divider(color: AppTheme.slate200, height: 1)),
      ],
    );
  }

  Widget _buildGoogleButton() {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: OutlinedButton(
        onPressed: _isLoading ? null : _handleGoogleSignIn,
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
            const Flexible(
              child: Text(
                'Log in with Google',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.slate700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
