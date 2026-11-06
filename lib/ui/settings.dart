import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/date.dart';
import '../core/models.dart';
import '../core/money.dart';
import '../core/phone.dart';
import '../core/store.dart';
import 'custom_theme.dart';
import 'theme.dart';
import 'widgets.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  Future<void> _export(BuildContext context, Store store) async {
    try {
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/kese-yedek-${store.today}.json');
      await file.writeAsString(store.exportBackup(), flush: true);
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path, mimeType: 'application/json')],
        subject: 'Kese yedeği',
      ));
    } catch (_) {
      if (context.mounted) showMessage(context, 'Yedek oluşturulamadı.');
    }
  }

  Future<void> _import(BuildContext context, Store store) async {
    try {
      final picked = await FilePicker.pickFile();
      if (picked == null) return;
      final contents = utf8.decode(await picked.readAsBytes());
      if (context.mounted) showUndo(context, store.importBackup(contents));
    } on FormatException catch (error) {
      if (context.mounted) {
        showMessage(context, 'Yedek yüklenmedi, verilerin değişmedi. ${error.message}');
      }
    } catch (_) {
      if (context.mounted) showMessage(context, 'Dosya okunamadı, verilerin değişmedi.');
    }
  }

  Future<void> _confirmDelete(BuildContext context, Store store) async {
    final count = store.transactions.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Tüm veriler silinsin mi?'),
        content: Text(
          '$count işlem, tüm limitler ve hedefler silinecek. Bu işlem geri alınamaz; önce yedek almak isteyebilirsin.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: Text(
              'Evet, sil',
              style: TextStyle(color: dialog.keseColors.danger),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) store.startEmpty();
  }

  Future<void> _editLimit(BuildContext context, Store store, Category category) async {
    final current = store.data.limits[category];
    final result = await showDialog<_LimitResult>(
      context: context,
      builder: (_) => _LimitDialog(category: category, current: current),
    );
    if (result != null) store.setLimit(category, result.amount);
  }

  /// Turning a reminder on is the moment to ask for permission; without it the
  /// switch would promise something the phone will not do.
  Future<void> _toggleNotification(
    BuildContext context,
    bool enabled,
    void Function() apply,
  ) async {
    if (enabled && !await PhoneScope.of(context).requestNotifications()) {
      if (context.mounted) {
        showMessage(context, 'Bildirim izni verilmedi. Telefon ayarlarından açabilirsin.');
      }
      return;
    }
    apply();
  }

  /// Confirming first proves the lock can be opened before it is ever needed,
  /// and stops someone holding an open phone from switching it off.
  Future<void> _toggleLock(BuildContext context, Store store, bool enabled) async {
    final phone = PhoneScope.of(context);
    if (enabled && !await phone.canLock()) {
      if (context.mounted) {
        showMessage(context, 'Önce telefonuna ekran kilidi veya parmak izi tanımla.');
      }
      return;
    }
    final result = await phone.unlock();
    if (result == UnlockResult.success ||
        (!enabled && result == UnlockResult.unavailable)) {
      store.setLock(enabled);
    } else if (result == UnlockResult.lockedOut && context.mounted) {
      showMessage(context, 'Çok fazla deneme yapıldı. Biraz bekleyip tekrar dene.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final colors = Theme.of(context).colorScheme;
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 4, 16, pageBottomInset(context)),
      children: [
        const SectionTitle('Aylık limitler'),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (final category in Category.expenses)
                ListTile(
                  leading: CategoryBadge(category, size: 36),
                  title: Text(category.label),
                  trailing: Text(
                    store.data.limits[category] == null
                        ? 'Yok'
                        : formatMoney(store.data.limits[category]!),
                    style: TextStyle(color: colors.onSurfaceVariant, fontFeatures: tabular),
                  ),
                  onTap: () => _editLimit(context, store, category),
                ),
            ],
          ),
        ),
        const SectionTitle('Tema'),
        const _ThemeGallery(),
        const SectionTitle('Bildirimler'),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.event_outlined),
                title: const Text('Yaklaşan ödemeler'),
                subtitle: const Text('Ödemeden bir gün önce sabah haber verir'),
                value: store.data.notifyPayments,
                onChanged: (value) => _toggleNotification(
                  context,
                  value,
                  () => store.setNotifications(payments: value),
                ),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.speed_outlined),
                title: const Text('Limit uyarıları'),
                subtitle: const Text('Limitin %80 ve %100 dolunca haber verir'),
                value: store.data.notifyLimits,
                onChanged: (value) => _toggleNotification(
                  context,
                  value,
                  () => store.setNotifications(limits: value),
                ),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.nightlight_outlined),
                title: const Text('Akşam hatırlatması'),
                subtitle: const Text('O gün hiç işlem girmediysen akşam 9 gibi hatırlatır'),
                value: store.data.notifyEvening,
                onChanged: (value) => _toggleNotification(
                  context,
                  value,
                  () => store.setNotifications(evening: value),
                ),
              ),
            ],
          ),
        ),
        const SectionTitle('Güvenlik'),
        Card(
          clipBehavior: Clip.antiAlias,
          child: SwitchListTile(
            secondary: const Icon(Icons.fingerprint),
            title: const Text('Uygulama kilidi'),
            subtitle: const Text('Parmak izi, yüz veya ekran kilidi ister; widget\'ta tutar gizlenir'),
            value: store.data.lockEnabled,
            onChanged: (value) => _toggleLock(context, store, value),
          ),
        ),
        const SectionTitle('Verilerim'),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                child: Text(
                  '${store.transactions.length} işlem yalnızca bu telefonda duruyor. '
                  'Uygulamayı silersen veriler de silinir, bu yüzden ara sıra yedek al.',
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.ios_share),
                title: const Text('Yedeği dışa aktar'),
                onTap: () => _export(context, store),
              ),
              ListTile(
                leading: const Icon(Icons.file_open_outlined),
                title: const Text('Yedekten yükle'),
                onTap: () => _import(context, store),
              ),
              ListTile(
                leading: Icon(Icons.delete_outline, color: context.keseColors.danger),
                title: Text('Tümünü sil', style: TextStyle(color: context.keseColors.danger)),
                onTap: () => _confirmDelete(context, store),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 18),
          child: Text(
            'Kese · ${formatMonth(monthOf(store.today))}',
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
          ),
        ),
      ],
    );
  }
}

class _ThemeGallery extends StatelessWidget {
  const _ThemeGallery();

  static const _gap = 10.0;

  void _openEditor(BuildContext context) {
    final store = StoreScope.of(context);
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => StoreScope(store: store, child: const CustomThemePage()),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final selected = resolveTheme(store.data).id;
    final custom = store.data.customColors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - _gap) / 2;
        return Wrap(
          spacing: _gap,
          runSpacing: _gap,
          children: [
            for (final theme in themes)
              SizedBox(
                width: width,
                child: _ThemeCard(
                  theme: theme,
                  selected: selected == theme.id,
                  onTap: () => store.setTheme(theme.id),
                ),
              ),
            _CustomThemeCard(
              theme: custom == null ? null : deriveTheme(custom),
              selected: selected == customThemeId,
              onSelect: custom == null
                  ? () => _openEditor(context)
                  : () => store.setTheme(customThemeId),
              onEdit: () => _openEditor(context),
            ),
          ],
        );
      },
    );
  }
}

/// A miniature of the app in the theme's own colors.
class _ThemeCard extends StatelessWidget {
  const _ThemeCard({required this.theme, required this.selected, required this.onTap});

  final KeseTheme theme;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(18);
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: theme.background,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(
            color: selected ? theme.accent : theme.inkSoft.withValues(alpha: 0.25),
            width: selected ? 2.5 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ExcludeSemantics(child: _Miniature(theme)),
                const SizedBox(height: 9),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        theme.name,
                        style: TextStyle(color: theme.ink, fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (selected) Icon(Icons.check_circle, size: 18, color: theme.accent),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Miniature extends StatelessWidget {
  const _Miniature(this.theme);

  final KeseTheme theme;

  Widget _bar(double width, Color color) => Container(
        width: width,
        height: 6,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
      );

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: theme.surface,
          borderRadius: BorderRadius.circular(11),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _bar(32, theme.inkSoft),
                  const SizedBox(height: 7),
                  _bar(58, theme.ink),
                  const SizedBox(height: 7),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: 0.65,
                      minHeight: 6,
                      color: theme.accent,
                      backgroundColor: theme.surfaceHigh,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(color: theme.accent, shape: BoxShape.circle),
              child: Icon(Icons.add, size: 16, color: theme.onAccent),
            ),
          ],
        ),
      );
}

/// Full width, because it is the one card that opens something new.
class _CustomThemeCard extends StatelessWidget {
  const _CustomThemeCard({
    required this.theme,
    required this.selected,
    required this.onSelect,
    required this.onEdit,
  });

  final KeseTheme? theme;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onEdit;

  static const _spectrum = SweepGradient(colors: [
    Color(0xFFFF4D4D),
    Color(0xFFFFC53D),
    Color(0xFF36D399),
    Color(0xFF3B82F6),
    Color(0xFFD946EF),
    Color(0xFFFF4D4D),
  ]);

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final theme = this.theme;
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: selected
            ? BorderSide(color: colors.primary, width: 2.5)
            : BorderSide(color: colors.outlineVariant),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(14, 4, 6, 4),
        leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: theme?.accent,
            gradient: theme == null ? _spectrum : null,
            border: theme == null ? null : Border.all(color: theme.background, width: 5),
          ),
        ),
        title: const Text('Özel', style: TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(theme == null ? 'Kendi renklerini seç' : 'Senin renklerin'),
        trailing: theme == null
            ? const Icon(Icons.chevron_right)
            : IconButton(
                tooltip: 'Özel temayı düzenle',
                icon: const Icon(Icons.tune),
                onPressed: onEdit,
              ),
        onTap: onSelect,
      ),
    );
  }
}

/// Null [amount] means the limit was removed.
class _LimitResult {
  const _LimitResult(this.amount);
  final int? amount;
}

class _LimitDialog extends StatefulWidget {
  const _LimitDialog({required this.category, required this.current});

  final Category category;
  final int? current;

  @override
  State<_LimitDialog> createState() => _LimitDialogState();
}

class _LimitDialogState extends State<_LimitDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.current == null ? '' : amountForInput(widget.current!),
  );
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final amount = parseAmount(_controller.text);
    if (amount == null || amount == 0) {
      setState(() => _error = 'Geçerli bir tutar yaz. Örnek: 5.000');
      return;
    }
    Navigator.pop(context, _LimitResult(amount));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('${widget.category.label} limiti'),
        content: TextField(
          controller: _controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Aylık tutar',
            suffixText: '₺',
            errorText: _error,
          ),
          onSubmitted: (_) => _save(),
        ),
        actions: [
          if (widget.current != null)
            TextButton(
              onPressed: () => Navigator.pop(context, const _LimitResult(null)),
              child: const Text('Limiti kaldır'),
            ),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
          TextButton(onPressed: _save, child: const Text('Kaydet')),
        ],
      );
}
