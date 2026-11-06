import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/store.dart';
import 'analysis.dart';
import 'home.dart';
import 'quick_add.dart';
import 'settings.dart';
import 'theme.dart';
import 'transactions.dart';
import 'widgets.dart';

class KeseApp extends StatelessWidget {
  const KeseApp({super.key, required this.store});

  final Store store;

  @override
  Widget build(BuildContext context) => StoreScope(
        store: store,
        child: ListenableBuilder(
          listenable: store,
          builder: (context, _) => MaterialApp(
            title: 'Kese',
            debugShowCheckedModeBanner: false,
            theme: buildTheme(themeById(store.data.theme)),
            locale: const Locale('tr', 'TR'),
            supportedLocales: const [Locale('tr', 'TR')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: store.data.onboarded ? const Shell() : const Welcome(),
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
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(26),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Icon(Icons.savings_outlined, size: 62, color: colors.primary),
              const SizedBox(height: 18),
              Text(
                'Kese',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .displaySmall
                    ?.copyWith(fontWeight: FontWeight.w800),
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
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> with WidgetsBindingObserver {
  static const _titles = ['Bu ay', 'İşlemler', 'Analiz', 'Ayarlar'];

  int _page = 0;
  Store? _store;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final store = StoreScope.of(context);
    if (!identical(store, _store)) {
      _store?.saveError.removeListener(_showSaveError);
      _store = store..saveError.addListener(_showSaveError);
    }
  }

  @override
  void dispose() {
    _store?.saveError.removeListener(_showSaveError);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// "Today" may have moved on while the app sat in the background.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) setState(() {});
  }

  void _showSaveError() {
    final message = _store?.saveError.value;
    if (message != null && mounted) showMessage(context, message);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(
            _titles[_page],
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        body: SafeArea(
          bottom: false,
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
        floatingActionButton: FloatingActionButton(
          tooltip: 'Hızlı ekle',
          onPressed: () => showQuickAdd(context),
          child: const Icon(Icons.add),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _page,
          onDestinationSelected: (page) => setState(() => _page = page),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.today_outlined), label: 'Bu ay'),
            NavigationDestination(icon: Icon(Icons.receipt_long_outlined), label: 'İşlemler'),
            NavigationDestination(icon: Icon(Icons.pie_chart_outline), label: 'Analiz'),
            NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'Ayarlar'),
          ],
        ),
      );
}
