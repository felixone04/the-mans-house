import 'package:flutter/material.dart';

import '../../models.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'barber_editor_screen.dart';

class BarbersTab extends StatefulWidget {
  const BarbersTab({super.key});

  @override
  State<BarbersTab> createState() => _BarbersTabState();
}

class _BarbersTabState extends State<BarbersTab> {
  List<Barber> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _items = await AppScope.read(context).backend.fetchBarbers(includeInactive: true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open([Barber? b]) async {
    final nextOrder = _items.isEmpty ? 1 : _items.map((e) => e.sortOrder).reduce((a, b) => a > b ? a : b) + 1;
    final changed = await Navigator.of(context).push<bool>(
      fadeRoute(BarberEditorScreen(barber: b?.copy() ?? Barber(name: '', sortOrder: nextOrder))),
    );
    if (changed == true && mounted) {
      await AppScope.read(context).refreshCatalog();
      await _load();
    }
  }

  String _summary(Barber b) {
    const short = ['Lun', 'Mar', 'Mer', 'Gio', 'Ven', 'Sab', 'Dom'];
    final days = [for (var d = 1; d <= 7; d++) if (b.hoursFor(d).isNotEmpty) short[d - 1]];
    return days.isEmpty ? 'Nessun orario impostato' : days.join(' · ');
  }

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          ResponsiveCenter(
            maxWidth: 800,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const SizedBox(height: 12),
              FilledButton.icon(onPressed: () => _open(), icon: const Icon(Icons.add), label: const Text('NUOVO BARBIERE')),
              const SizedBox(height: 16),
              if (_loading)
                const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
              else
                for (final b in _items)
                  Opacity(
                    opacity: b.active ? 1 : 0.5,
                    child: GlassCard(
                      margin: const EdgeInsets.only(bottom: 10),
                      onTap: () => _open(b),
                      child: Row(children: [
                        BarberAvatar(barber: b),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(b.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5)),
                            Text(b.active ? b.title : '${b.title} · non attivo',
                                style: const TextStyle(color: AppColors.silver, fontSize: 13)),
                            const SizedBox(height: 2),
                            Text(_summary(b), style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                          ]),
                        ),
                        const Icon(Icons.chevron_right, color: AppColors.muted),
                      ]),
                    ),
                  ),
            ]),
          ),
        ],
      );
}
