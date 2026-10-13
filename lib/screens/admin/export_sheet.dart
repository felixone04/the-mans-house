import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/export.dart';
import '../../models.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// Esportazione per Excel / commercialista: clienti e incassi di un periodo.
/// Sul web il file si scarica, sul telefono si apre il menu "Condividi".
Future<void> showExportSheet(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  constraints: const BoxConstraints(maxWidth: 520),
  builder: (c) => const _ExportSheet(),
);

class _ExportSheet extends StatefulWidget {
  const _ExportSheet();

  @override
  State<_ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<_ExportSheet> {
  String? _busy; // voce in preparazione

  Future<void> _run(String key, Future<CsvFile> Function() build) async {
    setState(() => _busy = key);
    try {
      final file = await build();
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile.fromData(file.bytes, mimeType: 'text/csv', name: file.name)],
          fileNameOverrides: [file.name],
          subject: file.name,
        ),
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<CsvFile> _revenue(DateTime from, DateTime to, String label) async {
    final list = await AppScope.read(context).backend.appointmentsBetween(from, to);
    return revenueCsv('incassi_$label.csv', list);
  }

  Future<CsvFile> _customers() async {
    final backend = AppScope.read(context).backend;
    final now = DateTime.now();
    final results = await Future.wait([
      backend.customers(),
      // ultimi due anni: per calcolare quanto resta da incassare
      backend.appointmentsBetween(DateTime(now.year - 2, now.month, now.day), now.add(const Duration(days: 366))),
    ]);
    return customersCsv(
      'clienti_${DateFormat('yyyy-MM-dd').format(now)}.csv',
      results[0] as List<CustomerSummary>,
      results[1] as List<Appointment>,
    );
  }

  Future<void> _customRange() async {
    final now = DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: DateTimeRange(start: DateTime(now.year, now.month, 1), end: now),
    );
    if (r == null) return;
    final f = DateFormat('yyyy-MM-dd');
    await _run(
      'custom',
      () => _revenue(
        r.start,
        DateTime(r.end.year, r.end.month, r.end.day + 1),
        '${f.format(r.start)}_${f.format(r.end)}',
      ),
    );
  }

  Widget _item(String key, IconData icon, String title, String subtitle, VoidCallback onTap) => ListTile(
    leading: _busy == key
        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.2))
        : Icon(icon),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
    subtitle: Text(subtitle, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
    onTap: _busy == null ? onTap : null,
  );

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final thisMonth = DateTime(now.year, now.month, 1);
    final nextMonth = DateTime(now.year, now.month + 1, 1);
    final lastMonth = DateTime(now.year, now.month - 1, 1);
    final month = DateFormat('MMMM_yyyy', 'it_IT');
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text('Esporta dati', style: slab(size: 20, weight: FontWeight.w600, spacing: 0.4)),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'File per Excel (.csv): si apre con Excel, Numbers o Fogli Google.',
                style: TextStyle(color: AppColors.muted, fontSize: 13),
              ),
            ),
            _item(
              'customers',
              Icons.people_outline,
              'Clienti',
              'Contatti, prenotazioni, ultima visita e importi da incassare',
              () => _run('customers', _customers),
            ),
            const Divider(),
            _item(
              'this',
              Icons.receipt_long_outlined,
              'Incassi di ${capitalize(DateFormat('MMMM', 'it_IT').format(now))}',
              'Ogni appuntamento con pagamento, più i totali per barbiere',
              () => _run('this', () => _revenue(thisMonth, nextMonth, month.format(now))),
            ),
            _item(
              'last',
              Icons.receipt_long_outlined,
              'Incassi di ${capitalize(DateFormat('MMMM', 'it_IT').format(lastMonth))}',
              'Il mese scorso',
              () => _run('last', () => _revenue(lastMonth, thisMonth, month.format(lastMonth))),
            ),
            _item(
              'year',
              Icons.calendar_month_outlined,
              'Incassi del ${now.year}',
              'Dal 1° gennaio a oggi',
              () => _run('year', () => _revenue(DateTime(now.year), nextMonth, '${now.year}')),
            ),
            _item('custom', Icons.date_range_outlined, 'Scegli il periodo…', 'Da una data a un\'altra', _customRange),
          ],
        ),
      ),
    );
  }
}
