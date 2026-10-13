import 'package:flutter/material.dart';

import '../../models.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'customer_screen.dart';

class CustomersTab extends StatefulWidget {
  const CustomersTab({super.key});

  @override
  State<CustomersTab> createState() => _CustomersTabState();
}

class _CustomersTabState extends State<CustomersTab> {
  List<CustomerSummary> _items = [];
  String _query = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _items = await AppScope.read(context).backend.customers();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.toLowerCase();
    final list = _items
        .where((c) =>
            q.isEmpty ||
            c.fullName.toLowerCase().contains(q) ||
            c.email.toLowerCase().contains(q) ||
            c.phone.replaceAll(' ', '').contains(q.replaceAll(' ', '')))
        .toList();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          ResponsiveCenter(
            maxWidth: 800,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const SizedBox(height: 12),
              TextField(
                onChanged: (v) => setState(() => _query = v),
                decoration: const InputDecoration(hintText: 'Cerca per nome, email o telefono', prefixIcon: Icon(Icons.search)),
              ),
              const SizedBox(height: 8),
              Text('${list.length} clienti', style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
              const SizedBox(height: 8),
              if (_loading)
                const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
              else if (list.isEmpty)
                const EmptyState(icon: Icons.people_outline, text: 'Nessun cliente')
              else
                for (final c in list)
                  GlassCard(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.fromLTRB(16, 10, 4, 10),
                    onTap: () => Navigator.of(context)
                        .push(fadeRoute(CustomerScreen(customer: c)))
                        .then((_) => _load()),
                    child: Row(children: [
                      CircleAvatar(
                        backgroundColor: AppColors.graphite,
                        child: Text(c.fullName.isEmpty ? '?' : c.fullName[0].toUpperCase(),
                            style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(c.fullName.isEmpty ? '(senza nome)' : c.fullName,
                              style: const TextStyle(fontWeight: FontWeight.w700)),
                          Text(
                            [c.phone, c.email].where((e) => e.isNotEmpty).join(' · '),
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: AppColors.silver, fontSize: 12.5),
                          ),
                          Text(
                            '${c.bookings} prenotazioni${c.lastVisit == null ? '' : ' · ultima visita ${fmtDayShort(c.lastVisit!)}'}',
                            style: const TextStyle(color: AppColors.muted, fontSize: 12),
                          ),
                        ]),
                      ),
                      if (c.phone.isNotEmpty) ...[
                        IconButton(
                          tooltip: 'WhatsApp',
                          onPressed: () => openWhatsApp(context, c.phone),
                          icon: const Icon(Icons.chat_outlined, size: 20),
                        ),
                        IconButton(
                          tooltip: 'Chiama',
                          onPressed: () => callPhone(context, c.phone),
                          icon: const Icon(Icons.call_outlined, size: 20),
                        ),
                      ],
                    ]),
                  ),
            ]),
          ),
        ],
      ),
    );
  }
}
