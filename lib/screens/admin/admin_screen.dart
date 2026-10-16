import 'package:flutter/material.dart';

import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'agenda_tab.dart';
import 'barbers_tab.dart';
import 'customers_tab.dart';
import 'products_tab.dart';
import 'search_screen.dart';
import 'waitlist_screen.dart';
import 'services_tab.dart';
import 'settings_tab.dart';

/// Area riservata: accessibile solo agli account amministratore.
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  int _index = 0;

  /// Prodotti da riordinare: numero sul pulsante Magazzino.
  int _lowStock = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadLowStock();
      _loadWaiting();
    });
  }

  /// Persone in lista d'attesa nei prossimi giorni: numero sulla clessidra.
  int _waiting = 0;

  Future<void> _loadWaiting() async {
    final state = AppScope.read(context);
    if (!state.isAdmin) return;
    try {
      final now = DateTime.now();
      final list = await state.backend.fetchWaitlist(now, now.add(const Duration(days: 61)));
      final n = list.where((w) => w.start.isAfter(now)).length;
      if (mounted && n != _waiting) setState(() => _waiting = n);
    } catch (_) {
      // solo un promemoria
    }
  }

  Future<void> _loadLowStock() async {
    final state = AppScope.read(context);
    if (!state.isAdmin) return;
    try {
      final products = await state.backend.fetchProducts(includeInactive: true);
      final stock = await state.backend.fetchStock();
      final low = products.where((p) => p.active && (stock[p.id]?.low ?? true)).length;
      if (mounted && low != _lowStock) setState(() => _lowStock = low);
    } catch (_) {
      // il numero e' solo un promemoria: se non si carica non blocca nulla
    }
  }

  Widget _icon(IconData icon, int i) {
    final i0 = Icon(icon);
    if (_destinations[i].$3 != 'Magazzino' || _lowStock == 0) return i0;
    return Badge(label: Text('$_lowStock'), backgroundColor: AppColors.danger, child: i0);
  }

  static const _destinations = [
    (Icons.calendar_month_outlined, Icons.calendar_month, 'Agenda'),
    (Icons.content_cut_outlined, Icons.content_cut, 'Servizi'),
    (Icons.badge_outlined, Icons.badge, 'Barbieri'),
    (Icons.people_outline, Icons.people, 'Clienti'),
    (Icons.inventory_2_outlined, Icons.inventory_2, 'Magazzino'),
    (Icons.tune_outlined, Icons.tune, 'Impostazioni'),
  ];

  Widget _tab() => switch (_index) {
        0 => const AgendaTab(),
        1 => const ServicesTab(),
        2 => const BarbersTab(),
        3 => const CustomersTab(),
        4 => ProductsTab(onStockChanged: _loadLowStock),
        _ => const SettingsTab(),
      };

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    if (!state.isAdmin) {
      return const AppScaffold(
        title: 'Area riservata',
        body: Center(child: EmptyState(icon: Icons.lock_outline, text: 'Accesso consentito solo all\'amministratore')),
      );
    }

    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 900;
    // ricerca veloce clienti, sempre a portata da ogni sezione
    final actions = [
      IconButton(
        tooltip: 'Lista d\'attesa',
        icon: Badge(
          isLabelVisible: _waiting > 0,
          label: Text('$_waiting'),
          backgroundColor: AppColors.warning,
          child: const Icon(Icons.hourglass_bottom),
        ),
        onPressed: () async {
          await Navigator.of(context).push(fadeRoute(const WaitlistScreen()));
          _loadWaiting();
        },
      ),
      IconButton(
        tooltip: 'Cerca cliente',
        icon: const Icon(Icons.search),
        onPressed: () => Navigator.of(context).push(fadeRoute(const SearchScreen())),
      ),
    ];

    if (wide) {
      return AppScaffold(
        title: 'Area riservata',
        actions: actions,
        body: SafeArea(
          child: Row(children: [
            NavigationRail(
              extended: width >= 1200,
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              leading: const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: AppLogo(height: 56, markOnly: true),
              ),
              destinations: [
                for (final (i, d) in _destinations.indexed)
                  NavigationRailDestination(icon: _icon(d.$1, i), selectedIcon: _icon(d.$2, i), label: Text(d.$3)),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: _tab()),
          ]),
        ),
      );
    }

    return AppScaffold(
      title: _destinations[_index].$3,
      actions: actions,
      body: SafeArea(bottom: false, child: _tab()),
      bottom: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        height: 66,
        destinations: [
          for (final (i, d) in _destinations.indexed)
            NavigationDestination(
              icon: _icon(d.$1, i),
              selectedIcon: _icon(d.$2, i),
              // etichette corte: sei voci devono stare anche sul telefono
              label: switch (d.$3) {
                'Impostazioni' => 'Opzioni',
                'Magazzino' => 'Prodotti',
                _ => d.$3,
              },
            ),
        ],
      ),
    );
  }
}
