import 'package:flutter/material.dart';

import '../../models.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../booking_screen.dart';

/// Scheda cliente: contatti, statistiche (visite, non presentato, speso,
/// preferenze) e storico completo degli appuntamenti.
class CustomerScreen extends StatefulWidget {
  const CustomerScreen({super.key, required this.customer});
  final CustomerSummary customer;

  @override
  State<CustomerScreen> createState() => _CustomerScreenState();
}

class _CustomerScreenState extends State<CustomerScreen> {
  List<Appointment> _items = [];
  bool _loading = true;

  /// Dati aggiornati del cliente (consensi): aperta dall'agenda la scheda
  /// riceve solo nome e telefono.
  CustomerSummary? _fresh;

  CustomerSummary get c => _fresh ?? widget.customer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final backend = AppScope.read(context).backend;
    try {
      final results = await Future.wait([backend.customerAppointments(widget.customer), backend.customers()]);
      if (mounted) {
        setState(() {
          _items = results[0] as List<Appointment>;
          _fresh = (results[1] as List<CustomerSummary>).where((x) => x.id == widget.customer.id).firstOrNull;
        });
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setMarketing(bool value) async {
    try {
      await AppScope.read(context).backend.setWalkInConsent(c.fullName, marketing: value);
      await _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  String get _phone =>
      c.phone.isNotEmpty ? c.phone : _items.map((a) => a.customerPhone).firstWhere((p) => p.isNotEmpty, orElse: () => '');

  Future<void> _book() async {
    final created = await Navigator.of(context).push<bool>(
      fadeRoute(BookingScreen(adminMode: true, initialCustomerName: c.fullName, initialCustomerPhone: _phone)),
    );
    if (created == true) _load();
  }

  Future<void> _move(Appointment a) async {
    final moved = await Navigator.of(context).push<bool>(fadeRoute(BookingScreen(adminMode: true, reschedule: a)));
    if (moved == true) _load();
  }

  /// Valore piu' frequente (es. servizio o barbiere preferito).
  static String? _favourite(Iterable<String> values) {
    final counts = <String, int>{};
    for (final v in values.where((v) => v.isNotEmpty)) {
      counts[v] = (counts[v] ?? 0) + 1;
    }
    if (counts.isEmpty) return null;
    return counts.entries.reduce((a, b) => b.value > a.value ? b : a).key;
  }

  @override
  Widget build(BuildContext context) {
    final done = _items.where((a) => a.status == AppointmentStatus.completed).toList();
    final noShow = _items.where((a) => a.status == AppointmentStatus.noShow).length;
    final cancelled = _items.where((a) => a.status == AppointmentStatus.cancelled).length;
    final spent = done.fold<double>(0, (s, a) => s + a.price);
    // resti di acconti e pagamenti rimandati
    final owed = _items.where((a) => a.status != AppointmentStatus.cancelled).fold<double>(0, (s, a) => s + a.outstanding);
    final upcoming = _items.where((a) => a.isUpcoming).toList()..sort((a, b) => a.start.compareTo(b.start));
    final history = _items.where((a) => !a.isUpcoming).toList();
    final kept = _items.where((a) => a.status != AppointmentStatus.cancelled && a.status != AppointmentStatus.noShow);
    final favService = _favourite(kept.map((a) => a.serviceName));
    final favBarber = _favourite(kept.map((a) => a.barberName));
    final lastVisit = done.isEmpty ? null : done.map((a) => a.start).reduce((a, b) => a.isAfter(b) ? a : b);
    final first = _items.isEmpty ? null : _items.map((a) => a.start).reduce((a, b) => a.isBefore(b) ? a : b);
    final phone = _phone;
    final name = c.fullName.isEmpty ? '(senza nome)' : c.fullName;

    return AppScaffold(
      title: 'Scheda cliente',
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 32),
                  children: [
                    ResponsiveCenter(
                      maxWidth: 640,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 8),
                          GlassCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 26,
                                      backgroundColor: AppColors.graphite,
                                      child: Text(
                                        name[0].toUpperCase(),
                                        style: slab(size: 21, weight: FontWeight.w700),
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(name, style: slab(size: 19, weight: FontWeight.w600, spacing: 0.4)),
                                          if (phone.isNotEmpty)
                                            Text(phone, style: const TextStyle(color: AppColors.silver, fontSize: 13)),
                                          if (c.email.isNotEmpty)
                                            Text(c.email, style: const TextStyle(color: AppColors.silver, fontSize: 13)),
                                          Text(
                                            c.isWalkIn ? 'Cliente dal banco (senza app)' : 'Cliente con app',
                                            style: const TextStyle(color: AppColors.muted, fontSize: 12),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                for (final warning in [
                                  if (owed > 0) 'Deve ancora ${fmtPrice(owed)}',
                                  if (noShow >= 2) 'Non si è presentato $noShow volte',
                                ]) ...[
                                  const SizedBox(height: 10),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                                    decoration: BoxDecoration(
                                      color: AppColors.warning.withValues(alpha: 0.10),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.warning_amber_rounded, size: 18, color: AppColors.warning),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            warning,
                                            style: const TextStyle(color: AppColors.warning, fontWeight: FontWeight.w700),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 14),
                                Row(
                                  children: [
                                    if (phone.isNotEmpty) ...[
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          onPressed: () => callPhone(context, phone),
                                          icon: const Icon(Icons.call_outlined, size: 18),
                                          label: const Text('Chiama'),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          onPressed: () => openWhatsApp(context, phone),
                                          icon: const Icon(Icons.chat_outlined, size: 18),
                                          label: const Text('WhatsApp'),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                    ],
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: _book,
                                        icon: const Icon(Icons.add, size: 18),
                                        label: const Text('Prenota'),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              _Stat(label: 'Visite', value: '${done.length}'),
                              _Stat(
                                label: 'Non presentato',
                                value: '$noShow',
                                color: noShow > 0 ? AppColors.warning : null,
                              ),
                              _Stat(label: 'Annullati', value: '$cancelled'),
                              _Stat(label: 'Speso', value: fmtPrice(spent)),
                            ],
                          ),
                          const SizedBox(height: 10),
                          GlassCard(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            child: Column(
                              children: [
                                _InfoRow(Icons.content_cut, 'Servizio preferito', favService ?? '–'),
                                _InfoRow(Icons.person_outline, 'Barbiere preferito', favBarber ?? '–'),
                                _InfoRow(
                                  Icons.event_available,
                                  'Ultima visita',
                                  lastVisit == null ? '–' : fmtDayShort(lastVisit),
                                ),
                                _InfoRow(Icons.history, 'Primo appuntamento', first == null ? '–' : fmtDayShort(first)),
                              ],
                            ),
                          ),
                          const SectionTitle('Consensi'),
                          GlassCard(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                            child: c.isWalkIn
                                // cliente dal banco: il consenso lo da' a voce in negozio
                                ? SwitchListTile(
                                    contentPadding: EdgeInsets.zero,
                                    value: c.marketingOptIn,
                                    onChanged: _setMarketing,
                                    title: const Text('Accetta offerte e novità'),
                                    subtitle: Text(
                                      c.privacyAcceptedAt == null
                                          ? 'Attivalo se il cliente ti ha dato il consenso in negozio'
                                          : 'Consenso registrato il ${fmtDayShort(c.privacyAcceptedAt!)}',
                                      style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
                                    ),
                                  )
                                : Column(
                                    children: [
                                      _InfoRow(
                                        Icons.privacy_tip_outlined,
                                        'Informativa privacy',
                                        c.privacyAcceptedAt == null
                                            ? 'non ancora accettata'
                                            : 'accettata il ${fmtDayShort(c.privacyAcceptedAt!)}',
                                      ),
                                      _InfoRow(
                                        Icons.campaign_outlined,
                                        'Offerte e novità',
                                        c.marketingOptIn ? 'sì' : 'no (lo sceglie dal suo profilo)',
                                      ),
                                    ],
                                  ),
                          ),
                          if (upcoming.isNotEmpty) ...[
                            const SectionTitle('Prossimi appuntamenti'),
                            for (final a in upcoming) _AppointmentLine(appointment: a, onMove: () => _move(a)),
                          ],
                          SectionTitle('Storico (${history.length})'),
                          if (history.isEmpty)
                            const EmptyState(icon: Icons.history, text: 'Nessun appuntamento passato')
                          else
                            for (final a in history) _AppointmentLine(appointment: a),
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

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.color});
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      margin: const EdgeInsets.symmetric(horizontal: 3),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value, style: slab(size: 18, weight: FontWeight.w700, color: color, spacing: 0)),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
          ),
        ],
      ),
    ),
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.icon, this.label, this.value);
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Icon(icon, size: 18, color: AppColors.muted),
        const SizedBox(width: 10),
        Text(label, style: const TextStyle(color: AppColors.silver, fontSize: 13.5)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
          ),
        ),
      ],
    ),
  );
}

class _AppointmentLine extends StatelessWidget {
  const _AppointmentLine({required this.appointment, this.onMove});
  final Appointment appointment;
  final VoidCallback? onMove;

  @override
  Widget build(BuildContext context) {
    final a = appointment;
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.fromLTRB(14, 10, onMove == null ? 14 : 4, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${fmtDayShort(a.start)} · ${fmtTime(a.start)}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  [a.serviceName, if (a.barberName.isNotEmpty) a.barberName, fmtPrice(a.price)].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.silver, fontSize: 12.5),
                ),
              ],
            ),
          ),
          StatusBadge(a.status),
          if (onMove != null)
            IconButton(
              tooltip: 'Sposta',
              onPressed: onMove,
              icon: const Icon(Icons.edit_calendar_outlined, size: 20),
            ),
        ],
      ),
    );
  }
}
