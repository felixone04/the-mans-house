import 'package:flutter/material.dart';

import '../../data/slots.dart';
import '../../models.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'customer_screen.dart';

/// Ricerca veloce: scrivi nome o numero e trovi il cliente con il suo
/// prossimo appuntamento; toccandolo si apre la scheda cliente (con gli arretrati).
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _query = TextEditingController();
  List<CustomerSummary> _customers = [];
  Map<String, Appointment> _next = {}; // prossimo appuntamento per cliente
  bool _loading = true;

  static String _keyOf(Appointment a) => a.userId ?? '${CustomerSummary.walkInPrefix}${a.customerName}';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final backend = AppScope.read(context).backend;
    final today = dayOnly(DateTime.now());
    try {
      final results = await Future.wait([
        backend.customers(),
        backend.appointmentsBetween(today, today.add(const Duration(days: 180))),
      ]);
      final upcoming = (results[1] as List<Appointment>).where((a) => a.isUpcoming).toList()
        ..sort((x, y) => x.start.compareTo(y.start));
      final next = <String, Appointment>{};
      for (final a in upcoming) {
        next.putIfAbsent(_keyOf(a), () => a);
      }
      if (mounted) {
        setState(() {
          _customers = results[0] as List<CustomerSummary>;
          _next = next;
        });
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<CustomerSummary> get _results {
    final q = _query.text.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final digits = q.replaceAll(RegExp(r'\D'), '');
    return _customers
        .where(
          (c) =>
              c.fullName.toLowerCase().contains(q) ||
              c.email.toLowerCase().contains(q) ||
              (digits.length >= 3 && c.phone.replaceAll(RegExp(r'\D'), '').contains(digits)),
        )
        .take(50)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    return AppScaffold(
      title: 'Cerca',
      body: SafeArea(
        child: ResponsiveCenter(
          maxWidth: 640,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              TextField(
                controller: _query,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Nome o numero di telefono',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _query.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Cancella',
                          icon: const Icon(Icons.close),
                          onPressed: () => setState(_query.clear),
                        ),
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _query.text.trim().isEmpty
                    ? const EmptyState(icon: Icons.person_search_outlined, text: 'Scrivi un nome o un numero')
                    : results.isEmpty
                    ? const EmptyState(icon: Icons.search_off, text: 'Nessun cliente trovato')
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 24),
                        itemCount: results.length,
                        itemBuilder: (context, i) => _ResultTile(customer: results[i], next: _next[results[i].id]),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({required this.customer, this.next});
  final CustomerSummary customer;
  final Appointment? next;

  @override
  Widget build(BuildContext context) {
    final c = customer;
    final n = next;
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      onTap: () => Navigator.of(context).push(fadeRoute(CustomerScreen(customer: c))),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: AppColors.graphite,
            child: Text(
              c.fullName.isEmpty ? '?' : c.fullName[0].toUpperCase(),
              style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.fullName.isEmpty ? '(senza nome)' : c.fullName,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
                if (c.phone.isNotEmpty) Text(c.phone, style: const TextStyle(color: AppColors.silver, fontSize: 12.5)),
                Text(
                  n != null
                      ? 'Prossimo: ${fmtDayShort(n.start)} alle ${fmtTime(n.start)} · ${n.barberName} · ${n.serviceName}'
                      : c.lastVisit == null
                      ? 'Nessun appuntamento in programma'
                      : 'Ultima visita ${fmtDayShort(c.lastVisit!)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: n != null ? AppColors.success : AppColors.muted,
                    fontSize: 12.5,
                    fontWeight: n != null ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: AppColors.muted),
        ],
      ),
    );
  }
}
