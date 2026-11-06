import 'package:flutter/material.dart';

import '../core/phone.dart';
import 'widgets.dart';

/// How long the app may stay in the background before it locks again. Long
/// enough that sharing a backup or picking a file does not trigger it.
const lockGrace = Duration(seconds: 30);

/// Covers the whole app, dialogs and sheets included, so a locked screen shows
/// nothing and everything underneath is still there after unlocking.
class LockGate extends StatefulWidget {
  const LockGate({super.key, required this.child});

  final Widget child;

  @override
  State<LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<LockGate> with WidgetsBindingObserver {
  late bool _locked = StoreScope.of(context).data.lockEnabled;
  bool _started = false;
  bool _unlocking = false;
  DateTime? _leftAt;
  String? _message;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (_locked) WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The fingerprint prompt itself sends the app through these states.
    if (_unlocking) return;
    if (state == AppLifecycleState.hidden || state == AppLifecycleState.paused) {
      _leftAt ??= StoreScope.of(context).now;
    } else if (state == AppLifecycleState.resumed) {
      final store = StoreScope.of(context);
      final leftAt = _leftAt;
      _leftAt = null;
      final expired = leftAt != null && store.now.difference(leftAt) >= lockGrace;
      if (expired && !_locked && store.data.lockEnabled) {
        FocusManager.instance.primaryFocus?.unfocus();
        setState(() => _locked = true);
        _unlock();
      }
    }
  }

  Future<void> _unlock() async {
    if (_unlocking) return;
    _unlocking = true;
    setState(() => _message = null);
    final result = await PhoneScope.of(context).unlock();
    _unlocking = false;
    if (!mounted) return;
    setState(() {
      switch (result) {
        // Refusing here would lock people out of their own data for good if
        // they ever removed their screen lock.
        case UnlockResult.success || UnlockResult.unavailable:
          _locked = false;
        case UnlockResult.lockedOut:
          _message = 'Çok fazla deneme yapıldı. Biraz bekleyip tekrar dene.';
        case UnlockResult.failed:
          _message = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final locked = _locked && StoreScope.of(context).data.lockEnabled;
    return Stack(
      fit: StackFit.expand,
      children: [
        ExcludeSemantics(excluding: locked, child: widget.child),
        if (locked) _LockScreen(message: _message, onUnlock: _unlock),
      ],
    );
  }
}

class _LockScreen extends StatelessWidget {
  const _LockScreen({required this.message, required this.onUnlock});

  final String? message;
  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(26),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Icon(Icons.lock_outline, size: 54, color: colors.primary),
              const SizedBox(height: 16),
              Text(
                'Kese kilitli',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              if (message != null) ...[
                const SizedBox(height: 10),
                Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
              ],
              const Spacer(),
              FilledButton.icon(
                onPressed: onUnlock,
                icon: const Icon(Icons.fingerprint),
                label: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('Kilidi aç'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
