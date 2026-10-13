import 'package:flutter/material.dart';

import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'agenda_tab.dart';
import 'barbers_tab.dart';
import 'customers_tab.dart';
import 'search_screen.dart';
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

  static const _destinations = [
    (Icons.calendar_month_outlined, Icons.calendar_month, 'Agenda'),
    (Icons.content_cut_outlined, Icons.content_cut, 'Servizi'),
    (Icons.badge_outlined, Icons.badge, 'Barbieri'),
    (Icons.people_outline, Icons.people, 'Clienti'),
    (Icons.tune_outlined, Icons.tune, 'Impostazioni'),
  ];

  Widget _tab() => switch (_index) {
        0 => const AgendaTab(),
        1 => const ServicesTab(),
        2 => const BarbersTab(),
        3 => const CustomersTab(),
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
                for (final d in _destinations)
                  NavigationRailDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: Text(d.$3)),
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
          for (final d in _destinations)
            NavigationDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2, color: AppColors.white),
                label: d.$3 == 'Impostazioni' ? 'Opzioni' : d.$3),
        ],
      ),
    );
  }
}
