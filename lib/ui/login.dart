import 'package:flutter/material.dart';

import '../core/auth.dart';
import 'pouch.dart';
import 'widgets.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.auth});

  final Auth auth;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _creating = false;
  bool _busy = false;
  bool _showPassword = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  /// Success needs no handling here: the account change replaces this page.
  Future<void> _run(Future<void> Function() action, {String? done}) async {
    if (_busy) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    String? error;
    try {
      await action();
    } on AuthFailure catch (failure) {
      error = failure.message;
    } on AuthCancelled {
      // The user changed their mind.
    } catch (_) {
      error = 'Giriş yapılamadı. Tekrar dene.';
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
    });
    if (error == null && done != null) showMessage(context, done);
  }

  void _submit() {
    final email = _email.text.trim();
    final password = _password.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'E-posta ve şifreni yaz.');
      return;
    }
    _run(() => _creating
        ? widget.auth.signUp(email, password)
        : widget.auth.signIn(email, password));
  }

  void _reset() {
    final email = _email.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'Önce e-posta adresini yaz, sıfırlama bağlantısını oraya göndereceğiz.');
      return;
    }
    _run(
      () => widget.auth.sendPasswordReset(email),
      done: 'Bu adres kayıtlıysa şifre sıfırlama e-postası gönderildi.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(26),
            child: AutofillGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const LivePouch(
                    level: 0.72,
                    amount: 0,
                    height: 120,
                    child: SizedBox.shrink(),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Kese',
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .displaySmall
                        ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1.2),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _creating
                        ? 'Hesap oluştur, verilerin telefon değişse de seninle gelsin.'
                        : 'Verilerine ulaşmak için giriş yap.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: colors.onSurfaceVariant, fontSize: 16),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _email,
                    enabled: !_busy,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(labelText: 'E-posta'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    enabled: !_busy,
                    obscureText: !_showPassword,
                    textInputAction: TextInputAction.done,
                    autofillHints: [
                      _creating ? AutofillHints.newPassword : AutofillHints.password,
                    ],
                    decoration: InputDecoration(
                      labelText: 'Şifre',
                      helperText: _creating ? 'En az 6 karakter' : null,
                      suffixIcon: IconButton(
                        tooltip: _showPassword ? 'Şifreyi gizle' : 'Şifreyi göster',
                        icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => _showPassword = !_showPassword),
                      ),
                    ),
                    onSubmitted: (_) => _submit(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Semantics(
                      liveRegion: true,
                      child: Text(_error!, style: TextStyle(color: colors.error)),
                    ),
                  ],
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(_creating ? 'Hesap oluştur' : 'Giriş yap'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: _busy ? null : () => _run(widget.auth.signInWithGoogle),
                    child: const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('Google ile devam et'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                              _creating = !_creating;
                              _error = null;
                            }),
                    child: Text(_creating ? 'Zaten hesabım var' : 'Hesabım yok, oluştur'),
                  ),
                  if (!_creating)
                    TextButton(
                      onPressed: _busy ? null : _reset,
                      child: const Text('Şifremi unuttum'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
