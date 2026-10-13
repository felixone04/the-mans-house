import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../data/slots.dart';
import '../../models.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// Messaggio WhatsApp a tutti i clienti.
///  - Avviso (chiusure, orari): a tutti i clienti con cellulare.
///  - Promozione: solo a chi ha dato il consenso alle offerte.
/// WhatsApp non consente invii automatici gratuiti a molti numeri: ogni
/// tocco apre WhatsApp con il messaggio pronto e il cliente viene segnato.
class BroadcastScreen extends StatefulWidget {
  const BroadcastScreen({super.key});

  @override
  State<BroadcastScreen> createState() => _BroadcastScreenState();
}

class _BroadcastScreenState extends State<BroadcastScreen> {
  final _text = TextEditingController();
  List<CustomerSummary> _customers = [];
  bool _loading = true;
  bool _promo = false;
  final _sent = <String>{};
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final list = await AppScope.read(context).backend.customers();
      if (mounted) setState(() => _customers = list);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Clienti con cellulare valido (un solo messaggio per numero).
  List<CustomerSummary> get _withPhone {
    final seen = <String>{};
    return _customers.where((c) => isValidPhone(c.phone) && seen.add(normalizePhone(c.phone))).toList();
  }

  List<CustomerSummary> get _recipients => _promo ? _withPhone.where((c) => c.marketingOptIn).toList() : _withPhone;

  String _firstName(CustomerSummary c) => c.fullName.trim().split(RegExp(r'\s+')).first;

  String _messageFor(CustomerSummary c) => _text.text.replaceAll('{nome}', _firstName(c));

  void _template(String kind) {
    final state = AppScope.read(context);
    final shop = state.settings.name;
    final f = DateFormat('EEEE d MMMM', 'it_IT');
    final today = dayOnly(DateTime.now());
    final upcoming = state.shopDays.where((d) => !d.day.isBefore(today)).toList();
    String text;
    switch (kind) {
      case 'closure':
        final closed = upcoming.where((d) => d.closed).toList();
        if (closed.isEmpty) {
          text = 'Ciao {nome}, ti avvisiamo che $shop resterà chiuso dal ... al .... A presto!';
        } else {
          // primo periodo di chiusura consecutivo
          var last = closed.first.day;
          for (final d in closed.skip(1)) {
            if (d.day != last.add(const Duration(days: 1))) break;
            last = d.day;
          }
          final from = closed.first.day;
          final note = closed.first.note.isEmpty ? '' : ' per ${closed.first.note.toLowerCase()}';
          text = from == last
              ? 'Ciao {nome}, ti avvisiamo che $shop resterà chiuso ${f.format(from)}$note. '
                    'Puoi prenotare dall\'app per gli altri giorni. A presto!'
              : 'Ciao {nome}, ti avvisiamo che $shop resterà chiuso da ${f.format(from)} a ${f.format(last)}$note. '
                    'Puoi prenotare dall\'app per i giorni successivi. A presto!';
        }
        _promo = false;
      case 'hours':
        final special = upcoming.where((d) => !d.closed).firstOrNull;
        text = special == null
            ? 'Ciao {nome}, ti avvisiamo che $shop cambierà orario il giorno .... A presto!'
            : 'Ciao {nome}, ${f.format(special.day)} $shop sarà aperto dalle ${formatTime(special.open!)} '
                  'alle ${formatTime(special.close!)}. Prenota dall\'app! A presto!';
        _promo = false;
      default:
        text =
            'Ciao {nome}! Da $shop questo mese ti aspetta una sorpresa: ... '
            'Prenota dall\'app. Per non ricevere più offerte, rispondi STOP.';
        _promo = true;
    }
    setState(() {
      _text.text = text;
      _error = null;
    });
  }

  Future<void> _send(CustomerSummary c) async {
    if (_text.text.trim().isEmpty) {
      setState(() => _error = 'Scrivi prima il messaggio');
      return;
    }
    await openWhatsApp(context, c.phone, _messageFor(c));
    if (mounted) setState(() => _sent.add(c.id));
  }

  @override
  Widget build(BuildContext context) {
    final recipients = _recipients;
    final excluded = _promo ? _withPhone.length - recipients.length : 0;
    final done = recipients.where((c) => _sent.contains(c.id)).length;

    return AppScaffold(
      title: 'Messaggio a tutti',
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.only(top: 8, bottom: 32),
                children: [
                  ResponsiveCenter(
                    maxWidth: 640,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SegmentedButton<bool>(
                          segments: const [
                            ButtonSegment(value: false, icon: Icon(Icons.info_outline), label: Text('Avviso')),
                            ButtonSegment(
                              value: true,
                              icon: Icon(Icons.local_offer_outlined),
                              label: Text('Promozione'),
                            ),
                          ],
                          selected: {_promo},
                          showSelectedIcon: false,
                          onSelectionChanged: (v) => setState(() => _promo = v.first),
                          style: SegmentedButton.styleFrom(
                            selectedBackgroundColor: AppColors.white,
                            selectedForegroundColor: AppColors.black,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _promo
                              ? 'Solo ai clienti che hanno accettato di ricevere offerte.'
                              : 'Avvisi di servizio (chiusure, orari): a tutti i clienti con cellulare.',
                          style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
                        ),
                        const SectionTitle('Messaggio'),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ActionChip(label: const Text('Chiusura'), onPressed: () => _template('closure')),
                            ActionChip(label: const Text('Orario speciale'), onPressed: () => _template('hours')),
                            ActionChip(label: const Text('Promozione'), onPressed: () => _template('promo')),
                          ],
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _text,
                          minLines: 3,
                          maxLines: 8,
                          maxLength: 700,
                          onChanged: (_) => setState(() => _error = null),
                          decoration: InputDecoration(
                            hintText: 'Scrivi il messaggio. {nome} viene sostituito con il nome del cliente.',
                            errorText: _error,
                          ),
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${recipients.length} destinatari'
                                '${excluded > 0 ? ' · $excluded esclusi senza consenso' : ''}',
                                style: const TextStyle(color: AppColors.silver, fontWeight: FontWeight.w700),
                              ),
                            ),
                            TextButton.icon(
                              onPressed: _text.text.trim().isEmpty
                                  ? null
                                  : () {
                                      Clipboard.setData(
                                        ClipboardData(text: _text.text.replaceAll('{nome}', '').trim()),
                                      );
                                      showMessage(context, 'Messaggio copiato');
                                    },
                              icon: const Icon(Icons.copy, size: 16),
                              label: const Text('Copia'),
                            ),
                          ],
                        ),
                        if (recipients.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: done / recipients.length,
                              minHeight: 6,
                              color: AppColors.success,
                              backgroundColor: AppColors.graphite,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Inviati $done di ${recipients.length} · tocca "Invia": si apre WhatsApp con il messaggio pronto',
                            style: const TextStyle(color: AppColors.muted, fontSize: 12),
                          ),
                        ],
                        const SizedBox(height: 10),
                        if (recipients.isEmpty)
                          EmptyState(
                            icon: Icons.group_off_outlined,
                            text: _promo ? 'Nessun cliente ha accettato le offerte' : 'Nessun cliente con cellulare',
                          ),
                        for (final c in recipients)
                          GlassCard(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        c.fullName.isEmpty ? '(senza nome)' : c.fullName,
                                        style: const TextStyle(fontWeight: FontWeight.w700),
                                      ),
                                      Text(c.phone, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                                    ],
                                  ),
                                ),
                                _sent.contains(c.id)
                                    ? TextButton.icon(
                                        onPressed: () => _send(c),
                                        style: TextButton.styleFrom(foregroundColor: AppColors.success),
                                        icon: const Icon(Icons.check_circle, size: 18),
                                        label: const Text('Inviato'),
                                      )
                                    : FilledButton.icon(
                                        onPressed: () => _send(c),
                                        style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                                        icon: const Icon(Icons.send, size: 16),
                                        label: const Text('Invia'),
                                      ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
