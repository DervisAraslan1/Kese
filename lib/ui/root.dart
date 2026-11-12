import 'dart:async';

import 'package:flutter/material.dart';

import '../core/auth.dart';
import '../core/phone.dart';
import '../core/store.dart';
import 'app.dart';
import 'login.dart';
import 'phone_sync.dart';
import 'theme.dart';
import 'widgets.dart';

/// One account's data while it is signed in.
class Session {
  Session({required this.store, this.sync, this.onClose});

  final Store store;
  final PhoneSync? sync;
  final Future<void> Function()? onClose;

  /// Stops syncing. The store stays usable until [dispose], because the
  /// screens showing it may still be on their way out.
  Future<void> stop() async {
    sync?.dispose();
    await onClose?.call();
  }

  void dispose() => store.dispose();

  Future<void> close() async {
    await stop();
    dispose();
  }
}

/// Shows the sign-in screen until someone is signed in, then their data.
class KeseRoot extends StatefulWidget {
  const KeseRoot({
    super.key,
    required this.auth,
    required this.open,
    this.phone = const NoPhone(),
    this.ambient = false,
  });

  final Auth auth;
  final Phone phone;
  final bool ambient;

  /// Loads an account's data. On a new phone this waits for the server.
  final Future<Session> Function(Account account) open;

  @override
  State<KeseRoot> createState() => _KeseRootState();
}

class _KeseRootState extends State<KeseRoot> {
  StreamSubscription<Account?>? _accounts;
  Account? _account;
  Session? _session;
  bool _failed = false;
  int _attempt = 0;

  @override
  void initState() {
    super.initState();
    _account = widget.auth.current;
    if (_account != null) unawaited(_open());
    _accounts = widget.auth.changes.listen(_onAccount);
  }

  @override
  void dispose() {
    _accounts?.cancel();
    unawaited(_session?.close());
    super.dispose();
  }

  void _onAccount(Account? account) {
    // The current account is announced again at startup.
    if (account?.uid == _account?.uid) return;
    final old = _session;
    if (old != null) {
      _hideFromPhone(old.store);
      unawaited(old.stop());
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    }
    _attempt++;
    setState(() {
      _account = account;
      _session = null;
      _failed = false;
    });
    if (account != null) unawaited(_open());
  }

  /// The widget and reminders outlive the app's screens, so signing out has
  /// to clear them itself.
  void _hideFromPhone(Store store) {
    final snapshot = buildWidgetSnapshot(store.data, store.today, signedOut: true);
    unawaited(Future.wait([
      widget.phone.updateWidget(snapshot),
      widget.phone.schedule(const []),
    ]).then<void>((_) {}, onError: (Object _) {}));
  }

  Future<void> _open() async {
    final attempt = ++_attempt;
    if (_failed) setState(() => _failed = false);
    Session? session;
    try {
      session = await widget.open(_account!);
    } catch (error) {
      debugPrint('Hesap verileri açılamadı: $error');
    }
    if (!mounted || attempt != _attempt) {
      unawaited(session?.close());
      return;
    }
    setState(() {
      _session = session;
      _failed = session == null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    return AuthScope(
      auth: widget.auth,
      child: session != null
          ? KeseApp(
              key: ObjectKey(session),
              store: session.store,
              phone: widget.phone,
              sync: session.sync,
              ambient: widget.ambient,
            )
          : KeseFrame(
              theme: themes.first,
              ambient: widget.ambient,
              home: _account == null
                  ? LoginPage(auth: widget.auth)
                  : _Opening(
                      failed: _failed,
                      onRetry: _open,
                      onSignOut: widget.auth.signOut,
                    ),
            ),
    );
  }
}

/// Usually gone within a moment, so the explanation only appears if it is not.
class _Opening extends StatefulWidget {
  const _Opening({required this.failed, required this.onRetry, required this.onSignOut});

  final bool failed;
  final VoidCallback onRetry;
  final VoidCallback onSignOut;

  @override
  State<_Opening> createState() => _OpeningState();
}

class _OpeningState extends State<_Opening> {
  late final Timer _timer;
  bool _slow = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(seconds: 3), () => setState(() => _slow = true));
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final explain = widget.failed || _slow;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(26),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!widget.failed) const CircularProgressIndicator(),
                if (explain) ...[
                  const SizedBox(height: 22),
                  Text(
                    widget.failed
                        ? 'Verilerin açılamadı.'
                        : 'Verilerin getiriliyor. Bu telefonda ilk girişte internet gerekir.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: colors.onSurfaceVariant, fontSize: 16),
                  ),
                  const SizedBox(height: 14),
                  if (widget.failed)
                    FilledButton(onPressed: widget.onRetry, child: const Text('Tekrar dene')),
                  TextButton(onPressed: widget.onSignOut, child: const Text('Çıkış yap')),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
