import 'package:flutter/material.dart';

import '../../data/slots.dart';
import '../../models.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// Lista d'attesa (solo area riservata): chi aspetta un posto, in ordine di
/// arrivo per ogni orario. Se un orario si libera il posto va da solo al primo;
/// da qui il barbiere puo' anche accettare comunque qualcuno quando si e'
/// pieni: l'appuntamento entra come extra.
class WaitlistScreen extends StatefulWidget {
  const WaitlistScreen({super.key, this.day});

  /// Solo questo giorno (dalla giornata del barbiere); null = prossimi 60 giorni.
  final DateTime? day;

  @override
  State<WaitlistScreen> createState() => _WaitlistScreenState();
}

class _WaitlistScreenState extends State<WaitlistScreen> {
  List<WaitlistEntry> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final from = widget.day ?? DateTime.now();
    final to = widget.day == null
        ? dayOnly(from).add(const Duration(days: 61))
        : dayOnly(from).add(const Duration(days: 1));
    try {
      final list = await AppScope.read(context).backend.fetchWaitlist(dayOnly(from), to);
      if (mounted) setState(() => _items = list.where((w) => w.start.isAfter(DateTime.now())).toList());
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Posizione in lista per lo stesso orario (in ordine di arrivo).
  int _position(WaitlistEntry w) =>
      _items.where((o) => o.start == w.start && o.createdAt.isBefore(w.createdAt) && o.fits(w.barberId)).length + 1;

  Future<void> _accept(WaitlistEntry w) async {
    final ok = await confirmDialog(
      context,
      title: 'Accettare comunque?',
      message:
          '${w.customerName.isEmpty ? 'Il cliente' : w.customerName} entra alle ${fmtTime(w.start)} '
          'di ${fmtDayLong(w.start)} come appuntamento extra, '
          '${w.barberName.isEmpty ? 'con un barbiere a caso tra chi lavora a quell\'ora' : 'con ${w.barberName}'}. '
          'L\'orario è già pieno: gli altri appuntamenti restano dove sono.',
      confirm: 'Accetta',
    );
    if (!ok || !mounted) return;
    try {
      final a = await AppScope.read(context).backend.acceptWaitlist(w.id);
      await _load();
      if (mounted) showMessage(context, 'Accettato: ${fmtTime(a.start)} con ${a.barberName}');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _remove(WaitlistEntry w) async {
    final ok = await confirmDialog(
      context,
      title: 'Togliere dalla lista?',
      message: '${w.customerName} · ${fmtTime(w.start)} di ${fmtDayLong(w.start)}',
      confirm: 'Togli',
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      await AppScope.read(context).backend.leaveWaitlist(w.id);
      await _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final byDay = <DateTime, List<WaitlistEntry>>{};
    for (final w in _items) {
      byDay.putIfAbsent(dayOnly(w.start), () => []).add(w);
    }
    return AppScaffold(
      title: widget.day == null ? 'Lista d\'attesa' : 'Lista d\'attesa · ${fmtDayShort(widget.day!)}',
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 32),
                  children: [
                    ResponsiveCenter(
                      maxWidth: 720,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 8),
                          const Text(
                            'Se un orario si libera, il posto va in automatico al primo in lista. '
                            'Puoi anche accettare qualcuno quando sei pieno: entra come extra.',
                            style: TextStyle(color: AppColors.silver, fontSize: 13, height: 1.4),
                          ),
                          if (_items.isEmpty)
                            const Padding(
                              padding: EdgeInsets.only(top: 40),
                              child: EmptyState(icon: Icons.hourglass_empty, text: 'Nessuno in lista d\'attesa'),
                            ),
                          for (final e in byDay.entries) ...[
                            SectionTitle('${capitalize(fmtDayLong(e.key))} · ${e.value.length} in lista'),
                            for (final w in e.value)
                              _WaitCard(
                                entry: w,
                                position: _position(w),
                                onAccept: () => _accept(w),
                                onRemove: () => _remove(w),
                              ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _WaitCard extends StatelessWidget {
  const _WaitCard({required this.entry, required this.position, required this.onAccept, required this.onRemove});
  final WaitlistEntry entry;
  final int position;
  final VoidCallback onAccept;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final w = entry;
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(fmtTime(w.start), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${w.serviceName} · ${w.durationMin} min',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.silver, fontSize: 13.5),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(color: const Color(0xFFFFF1DB), borderRadius: BorderRadius.circular(10)),
                child: Text(
                  '$position° in lista',
                  style: const TextStyle(color: Color(0xFF8A4B00), fontSize: 12, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      w.customerName.isEmpty ? 'Cliente' : w.customerName,
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                    ),
                    Text(
                      '${w.barberName.isEmpty ? 'Primo barbiere disponibile' : 'Con ${w.barberName}'}'
                      ' · in lista dal ${fmtDayShort(w.createdAt)} alle ${fmtTime(w.createdAt)}',
                      style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              if (w.customerPhone.isNotEmpty) ...[
                IconButton(
                  tooltip: 'Chiama',
                  onPressed: () => callPhone(context, w.customerPhone),
                  icon: const Icon(Icons.call_outlined),
                ),
                IconButton(
                  tooltip: 'WhatsApp',
                  onPressed: () => openWhatsApp(context, w.customerPhone),
                  icon: const Icon(Icons.chat_outlined),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onRemove,
                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
                  child: const Text('Togli'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: onAccept,
                  icon: const Icon(Icons.check, size: 18),
                  label: const FittedBox(fit: BoxFit.scaleDown, child: Text('Accetta comunque')),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
