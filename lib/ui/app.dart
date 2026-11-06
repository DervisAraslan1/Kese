import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/phone.dart';
import '../core/store.dart';
import 'ambient.dart';
import 'analysis.dart';
import 'home.dart';
import 'lock.dart';
import 'phone_sync.dart';
import 'pouch.dart';
import 'quick_add.dart';
import 'settings.dart';
import 'theme.dart';
import 'transactions.dart';
import 'widgets.dart';

class KeseApp extends StatelessWidget {
  const KeseApp({
    super.key,
    required this.store,
    this.phone = const NoPhone(),
    this.sync,
    this.ambient = false,
  });

  final Store store;
  final Phone phone;
  final PhoneSync? sync;

  /// Runs the endless background motion. The app passes true.
  final bool ambient;

  @override
  Widget build(BuildContext context) => StoreScope(
        store: store,
        child: ListenableBuilder(
          listenable: store,
          builder: (context, _) => MaterialApp(
            title: 'Kese',
            debugShowCheckedModeBanner: false,
            theme: buildTheme(resolveTheme(store.data)),
            locale: const Locale('tr', 'TR'),
            supportedLocales: const [Locale('tr', 'TR')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            builder: (context, child) {
              final theme = resolveTheme(store.data);
              return Ambient(
                enabled: ambient,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Aurora(background: theme.background, color: theme.accent),
                    PhoneScope(phone: phone, child: LockGate(child: child!)),
                  ],
                ),
              );
            },
            home: store.data.onboarded ? Shell(sync: sync) : const Welcome(),
          ),
        ),
      );
}

class Welcome extends StatelessWidget {
  const Welcome({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(26),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              const LivePouch(
                level: 0.72,
                amount: 0,
                height: 230,
                child: SizedBox.shrink(),
              ),
              const SizedBox(height: 26),
              Text(
                'Kese',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .displayMedium
                    ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1.5),
              ),
              const SizedBox(height: 10),
              Text(
                'Harcamanı tek satırda yaz, paranın nereye gittiğini gör. '
                'Veriler yalnızca bu telefonda kalır.',
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.onSurfaceVariant, fontSize: 16),
              ),
              const Spacer(),
              FilledButton(
                onPressed: store.startEmpty,
                child: const Padding(padding: EdgeInsets.all(12), child: Text('Başla')),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: store.startWithDemo,
                child: const Text('Örnek verilerle dene'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class Shell extends StatefulWidget {
  const Shell({super.key, this.sync});

  final PhoneSync? sync;

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  static const _titles = ['Bu ay', 'İşlemler', 'Analiz', 'Ayarlar'];

  int _page = 0;
  late final AnimationController _pageFade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    value: 1,
  );
  Store? _store;
  StreamSubscription<void>? _quickAdds;
  bool _quickAddOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  Future<void> _listenForQuickAdd() async {
    final phone = PhoneScope.of(context);
    _quickAdds = phone.quickAddRequests.listen((_) => _openQuickAdd());
    if (await phone.openedForQuickAdd()) _openQuickAdd();
  }

  /// Pressing the widget's button twice must not stack two sheets.
  Future<void> _openQuickAdd() async {
    if (_quickAddOpen || !mounted) return;
    _quickAddOpen = true;
    await showQuickAdd(context);
    _quickAddOpen = false;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final store = StoreScope.of(context);
    if (!identical(store, _store)) {
      _store?.saveError.removeListener(_showSaveError);
      _store = store..saveError.addListener(_showSaveError);
    }
    if (_quickAdds == null) unawaited(_listenForQuickAdd());
  }

  @override
  void dispose() {
    _store?.saveError.removeListener(_showSaveError);
    _quickAdds?.cancel();
    _pageFade.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// "Today" may have moved on while the app sat in the background.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      setState(() {});
      unawaited(widget.sync?.run());
    }
  }

  void _showSaveError() {
    final message = _store?.saveError.value;
    if (message != null && mounted) showMessage(context, message);
  }

  void _goTo(int page) {
    if (page == _page) return;
    setState(() => _page = page);
    _pageFade.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.transparent,
      // Pages scroll under the floating bar; see [pageBottomInset].
      extendBody: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
        title: Text(
          _titles[_page],
          style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.5),
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: FadeTransition(
          opacity: CurvedAnimation(parent: _pageFade, curve: Curves.easeOut),
          child: IndexedStack(
            index: _page,
            children: const [
              HomePage(),
              TransactionsPage(),
              AnalysisPage(),
              SettingsPage(),
            ],
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(40),
          boxShadow: [
            BoxShadow(color: colors.primary.withValues(alpha: 0.42), blurRadius: 26, spreadRadius: -4),
          ],
        ),
        child: FloatingActionButton.extended(
          tooltip: 'Hızlı ekle',
          onPressed: _openQuickAdd,
          icon: const Icon(Icons.add),
          label: const Text('Ne harcadın?'),
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(14, 0, 14, 10),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: colors.onSurface.withValues(alpha: 0.1)),
          ),
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            removeBottom: true,
            child: NavigationBar(
              selectedIndex: _page,
              onDestinationSelected: _goTo,
              destinations: const [
                NavigationDestination(icon: Icon(Icons.today_outlined), label: 'Bu ay'),
                NavigationDestination(icon: Icon(Icons.receipt_long_outlined), label: 'İşlemler'),
                NavigationDestination(icon: Icon(Icons.pie_chart_outline), label: 'Analiz'),
                NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'Ayarlar'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
