import 'package:flutter/material.dart';
import '../data/controller.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.app});
  final AppController app;
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final form = GlobalKey<FormState>();
  final email = TextEditingController();
  final password = TextEditingController();
  final name = TextEditingController();
  final code = TextEditingController();
  String? accountStep, challengeSession, challengeUsername, notice;
  bool register = false, busy = false, obscure = true;
  bool get signingIn =>
      !register && (accountStep == null || accountStep == 'new-password');
  bool get creatingPassword =>
      (register && accountStep == null) ||
      accountStep == 'reset' ||
      accountStep == 'new-password';
  String? error;
  Future<void> submit() async {
    if (!form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await widget.app.authenticate(
        email: email.text,
        password: password.text,
        name: register && accountStep == null ? name.text : null,
        action: accountStep,
        code: code.text,
        newPassword: password.text,
        challengeSession: challengeSession,
        challengeUsername: challengeUsername,
      );
      if (mounted && result != null) {
        setState(() {
          if (result['confirmationRequired'] == true) {
            accountStep = 'confirm';
            notice = 'Enter the verification code sent to your email.';
          } else if (result['challenge'] is Map) {
            final challenge = result['challenge'] as Map;
            accountStep = 'new-password';
            challengeSession = challenge['session'] as String?;
            challengeUsername = challenge['username'] as String?;
            password.clear();
            notice = 'Choose a new password to finish signing in.';
          } else if (accountStep == 'forgot') {
            accountStep = 'reset';
            notice = 'If the account can be recovered, a reset code was sent.';
          } else {
            accountStep = null;
            register = false;
            password.clear();
            notice = 'You can now sign in.';
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Form(
            key: form,
            child: ListView(
              padding: const EdgeInsets.all(28),
              shrinkWrap: true,
              children: [
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Image(
                    image: AssetImage('assets/branding/app-icon.png'),
                    width: 64,
                    height: 64,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'A little care,\nevery day.',
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Your medicines, schedules and stock.\nTogether in one place.',
                  style: TextStyle(fontSize: 16, height: 1.5),
                ),
                const SizedBox(height: 32),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('Sign in')),
                    ButtonSegment(value: true, label: Text('Create account')),
                  ],
                  selected: {register},
                  onSelectionChanged: busy
                      ? null
                      : (v) => setState(() {
                          register = v.first;
                          accountStep = null;
                          notice = null;
                          challengeSession = null;
                          code.clear();
                        }),
                ),
                const SizedBox(height: 24),
                if (error != null || widget.app.error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      error ?? widget.app.error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (notice != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(notice!),
                  ),
                if (register && accountStep == null) ...[
                  TextFormField(
                    controller: name,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Your name'),
                    validator: (v) => register && (v ?? '').trim().isEmpty
                        ? 'Enter your name'
                        : null,
                  ),
                  const SizedBox(height: 16),
                ],
                TextFormField(
                  controller: email,
                  keyboardType: signingIn
                      ? TextInputType.text
                      : TextInputType.emailAddress,
                  autofillHints: [
                    signingIn ? AutofillHints.username : AutofillHints.email,
                  ],
                  decoration: InputDecoration(
                    labelText: signingIn
                        ? 'Username or email'
                        : 'Email address',
                  ),
                  validator: (v) => signingIn
                      ? ((v ?? '').trim().isEmpty
                            ? 'Enter your username or email'
                            : null)
                      : !RegExp(
                          r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                        ).hasMatch(v?.trim() ?? '')
                      ? 'Enter a valid email address'
                      : null,
                ),
                const SizedBox(height: 16),
                if (accountStep == 'confirm' || accountStep == 'reset') ...[
                  TextFormField(
                    controller: code,
                    decoration: const InputDecoration(
                      labelText: 'Email verification code',
                    ),
                    autofillHints: const [AutofillHints.oneTimeCode],
                    validator: (value) =>
                        (value ?? '').trim().isEmpty ? 'Enter the code' : null,
                  ),
                  const SizedBox(height: 16),
                ],
                if (accountStep != 'confirm' && accountStep != 'forgot')
                  TextFormField(
                    controller: password,
                    obscureText: obscure,
                    autofillHints: [
                      creatingPassword
                          ? AutofillHints.newPassword
                          : AutofillHints.password,
                    ],
                    decoration: InputDecoration(
                      labelText:
                          accountStep == 'reset' ||
                              accountStep == 'new-password'
                          ? 'New password'
                          : 'Password',
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => obscure = !obscure),
                        icon: Icon(
                          obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                    validator: (v) {
                      final value = v ?? '';
                      if (value.isEmpty) return 'Enter your password';
                      if (value.length > 128) {
                        return 'Use at most 128 characters';
                      }
                      if (creatingPassword && value.length < 10) {
                        return 'Use 10–128 characters';
                      }
                      return null;
                    },
                    onFieldSubmitted: (_) {
                      if (!busy) submit();
                    },
                  ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: busy ? null : submit,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(
                      busy
                          ? 'Connecting…'
                          : accountStep != null
                          ? (accountStep == 'confirm'
                                ? 'Verify email'
                                : accountStep == 'forgot'
                                ? 'Send reset code'
                                : 'Save new password')
                          : register
                          ? 'Create account'
                          : 'Sign in',
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: busy
                      ? null
                      : () => setState(() {
                          accountStep = 'forgot';
                          register = false;
                          error = null;
                          notice = null;
                        }),
                  child: const Text('Forgot password?'),
                ),
                if (accountStep == 'confirm')
                  TextButton(
                    onPressed: busy
                        ? null
                        : () async {
                            try {
                              await widget.app.api.post('mobile/auth/resend', {
                                'email': email.text,
                              });
                              if (mounted) {
                                setState(
                                  () => notice =
                                      'Another verification code was requested.',
                                );
                              }
                            } catch (e) {
                              if (mounted) setState(() => error = e.toString());
                            }
                          },
                    child: const Text('Resend verification code'),
                  ),
                const Text(
                  'Reminders are scheduled privately on your phone. No Firebase account is needed.',
                  style: TextStyle(fontSize: 12, height: 1.5),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  @override
  void dispose() {
    email.dispose();
    password.dispose();
    name.dispose();
    code.dispose();
    super.dispose();
  }
}
