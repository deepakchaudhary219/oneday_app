import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_controller.dart';
import '../../design_system/design_system.dart';
import 'about_you_screen.dart';
import 'auth_widgets.dart';

/// Email sign-in, and the first step of email sign-up (the rest is the same About You screen as phone).
class EmailScreen extends ConsumerStatefulWidget {
  const EmailScreen({super.key});

  static const minPassword = 12;

  @override
  ConsumerState<EmailScreen> createState() => _EmailScreenState();
}

class _EmailScreenState extends ConsumerState<EmailScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _creating = false;
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  bool get _valid =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(_email.text.trim()) &&
      _password.text.length >= (_creating ? EmailScreen.minPassword : 1);

  Future<void> _submit() async {
    if (_creating) {
      context.push(
        '/auth/about',
        extra: AboutYouArgs.email(
          email: _email.text.trim(),
          password: _password.text,
        ),
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(authControllerProvider.notifier)
          .signInWithEmail(_email.text, _password.text);
    } catch (e) {
      if (mounted) setState(() => _error = authMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AuthStepScaffold(
      title: _creating ? 'Create your account' : 'Welcome back',
      subtitle: _creating
          ? 'Use a password of at least ${EmailScreen.minPassword} characters. A short sentence works well.'
          : 'Sign in with your email and password.',
      action: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          OdButton(
            label: _creating ? 'Continue' : 'Sign in',
            expand: true,
            loading: _busy,
            onPressed: _valid && !_busy ? _submit : null,
          ),
          const SizedBox(height: OdSpace.x0_5),
          OdButton(
            label: _creating
                ? 'I already have an account'
                : 'New here? Create an account',
            variant: OdButtonVariant.ghost,
            expand: true,
            onPressed: () => setState(() {
              _creating = !_creating;
              _error = null;
            }),
          ),
        ],
      ),
      children: [
        AutofillGroup(
          child: Column(
            children: [
              TextField(
                key: const Key('email-field'),
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                autocorrect: false,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Email'),
                onChanged: (_) => setState(() => _error = null),
              ),
              const SizedBox(height: OdSpace.x2),
              TextField(
                key: const Key('password-field'),
                controller: _password,
                obscureText: _obscure,
                autofillHints: [
                  _creating
                      ? AutofillHints.newPassword
                      : AutofillHints.password,
                ],
                decoration: InputDecoration(
                  labelText: 'Password',
                  suffixIcon: IconButton(
                    tooltip: _obscure ? 'Show password' : 'Hide password',
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_rounded
                          : Icons.visibility_off_rounded,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                onChanged: (_) => setState(() => _error = null),
                onSubmitted: (_) => _valid && !_busy ? _submit() : null,
              ),
            ],
          ),
        ),
        AuthErrorText(_error),
      ],
    );
  }
}
