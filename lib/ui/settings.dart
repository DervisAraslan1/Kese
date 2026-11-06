import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/date.dart';
import '../core/models.dart';
import '../core/money.dart';
import '../core/store.dart';
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
          '$count işlem ve tüm limitler silinecek. Bu işlem geri alınamaz; önce yedek almak isteyebilirsin.',
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

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final colors = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
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
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final theme in themes)
              ChoiceChip(
                avatar: CircleAvatar(backgroundColor: theme.accent, radius: 8),
                showCheckmark: false,
                label: Text(theme.name),
                selected: themeById(store.data.theme).id == theme.id,
                onSelected: (_) => store.setTheme(theme.id),
              ),
          ],
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
