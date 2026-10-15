import 'package:flutter/material.dart';

import '../data/slots.dart';
import '../models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'account_screen.dart';
import 'admin/admin_screen.dart';
import 'auth_screen.dart';
import 'booking_screen.dart';
import 'products_screen.dart';

/// Home: schermata unica, senza scorrimento. In alto lo stato del negozio e
/// l'account, al centro l'insegna, sotto Prenota ora, il prossimo
/// appuntamento, le scorciatoie e l'indirizzo.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<void> _openAccount(BuildContext context) async {
    final state = AppScope.read(context);
    if (state.isSignedIn) {
      await Navigator.of(context).push(fadeRoute(const AccountScreen()));
    } else {
      await openAuthFlow(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final s = state.settings;
    final next = state.nextAppointment;

    return AppScaffold(
      spotlight: true,
      // sfondo a tutto schermo; contenuti della stessa misura e al centro
      // su ogni dispositivo
      body: SafeArea(
        child: ResponsiveCenter(
          maxWidth: 560,
          child: Column(
            children: [
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Align(alignment: Alignment.centerLeft, child: _StatusPill(barbers: state.barbers)),
                  ),
                  if (state.isAdmin)
                    IconButton(
                      tooltip: 'Area riservata',
                      onPressed: () => Navigator.of(context).push(fadeRoute(const AdminScreen())),
                      icon: const Icon(Icons.dashboard_customize_outlined, size: 20, color: AppColors.white),
                    ),
                  _AccountButton(onTap: () => _openAccount(context)),
                ],
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, c) {
                    // la scritta occupa la colonna centrale (max 560 px): stessa
                    // misura su tablet, computer e TV, con lo sfondo a tutto schermo
                    final logoH = (c.maxWidth * 0.62).clamp(160.0, 560.0);
                    return Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: SizedBox(width: c.maxWidth, child: AppLogo(height: logoH)),
                      ),
                    );
                  },
                ),
              ),
              _BookButton(onTap: () => Navigator.of(context).push(fadeRoute(const BookingScreen()))),
              if (next != null) ...[const SizedBox(height: 12), _NextAppointmentCard(appointment: next)],
              const SizedBox(height: 12),
              _QuickActions(settings: s, barbers: state.barbers),
              const SizedBox(height: 12),
              InkWell(
                onTap: () => openUrl(context, s.mapsUrl),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.location_on_outlined, size: 15, color: AppColors.white),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          s.address.toUpperCase(),
                          overflow: TextOverflow.ellipsis,
                          style: exo(
                            color: AppColors.white,
                            fontSize: 11.5,
                            letterSpacing: 1.4,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Aperto · chiude alle 13:00" con il pallino verde, o chiuso con la prossima apertura.
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.barbers});
  final List<Barber> barbers;

  @override
  Widget build(BuildContext context) {
    if (barbers.isEmpty) return const SizedBox.shrink();
    final (open, label) = shopStatus(barbers, DateTime.now());
    return InkWell(
      onTap: () => showHoursSheet(context, barbers),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.white.withValues(alpha: 0.12)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: open ? const Color(0xFF1F9D55) : AppColors.danger,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.white, fontSize: 12.5, fontWeight: FontWeight.w700),
              ),
            ),
            // toccando si aprono gli orari della settimana
            const SizedBox(width: 2),
            const Icon(Icons.expand_more, size: 18, color: AppColors.white),
          ],
        ),
      ),
    );
  }
}

class _BookButton extends StatelessWidget {
  const _BookButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: 58,
    child: FilledButton(
      onPressed: onTap,
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.quiet,
        foregroundColor: AppColors.quietText,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: exo(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 0.4),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.calendar_month_outlined, size: 20),
          SizedBox(width: 10),
          Text('Prenota ora'),
          SizedBox(width: 6),
          Icon(Icons.arrow_forward, size: 18),
        ],
      ),
    ),
  );
}

class _AccountButton extends StatelessWidget {
  const _AccountButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final p = state.profile;
    final signedIn = state.isSignedIn;
    final initials = (p?.fullName.trim().isNotEmpty ?? false)
        ? p!.fullName.trim().split(RegExp(r'\s+')).take(2).map((w) => w[0].toUpperCase()).join()
        : null;
    return Tooltip(
      message: signedIn ? 'Il mio account' : 'Accedi o registrati',
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.quiet,
            border: Border.fromBorderSide(BorderSide(color: AppColors.quietBorder)),
          ),
          alignment: Alignment.center,
          child: signedIn && initials != null
              ? Text(
                  initials,
                  style: slab(size: 13.5, color: AppColors.quietText, weight: FontWeight.w700, spacing: 0.5),
                )
              : Icon(signedIn ? Icons.person : Icons.person_outline, color: AppColors.quietText, size: 20),
        ),
      ),
    );
  }
}

void showHoursSheet(BuildContext context, List<Barber> barbers) {
  final today = DateTime.now().weekday;
  // chiusure e orari speciali dei prossimi 60 giorni
  final now = dayOnly(DateTime.now());
  final special = AppScope.read(context).shopDays
      .where((d) => !d.day.isBefore(now) && d.day.isBefore(now.add(const Duration(days: 60))))
      .toList();
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: 520),
    builder: (c) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (special.isNotEmpty) ...[
              Text(
                'CHIUSURE E ORARI SPECIALI',
                style: slab(size: 14, weight: FontWeight.w600, color: AppColors.warning),
              ),
              const SizedBox(height: 10),
              for (final d in special)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(fmtDayShort(d.day), style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                      Text(
                        d.closed
                            ? 'Chiuso${d.note.isEmpty ? '' : ' · ${d.note}'}'
                            : '${formatTime(d.open!)} – ${formatTime(d.close!)}',
                        style: TextStyle(color: d.closed ? AppColors.warning : AppColors.white),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 18),
            ],
            Text('ORARI DI APERTURA', style: slab(size: 16, weight: FontWeight.w600)),
            const SizedBox(height: 16),
            for (var d = 1; d <= 7; d++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        weekdayNames[d - 1],
                        style: TextStyle(
                          fontWeight: d == today ? FontWeight.w800 : FontWeight.w500,
                          color: d == today ? AppColors.white : AppColors.silver,
                        ),
                      ),
                    ),
                    Text(
                      shopHoursFor(barbers, d).isEmpty
                          ? 'Chiuso'
                          : shopHoursFor(
                              barbers,
                              d,
                            ).map((r) => '${formatTime(r[0])} – ${formatTime(r[1])}').join('  ·  '),
                      style: TextStyle(
                        fontWeight: d == today ? FontWeight.w800 : FontWeight.w500,
                        color: shopHoursFor(barbers, d).isEmpty ? AppColors.muted : AppColors.white,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

/// Scorciatoie a riquadri chiari: Prodotti, Chiama, WhatsApp, Instagram.
/// (Gli orari si aprono toccando lo stato in alto; l'indirizzo in fondo porta alla mappa.)
class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.settings, required this.barbers});
  final ShopSettings settings;
  final List<Barber> barbers;

  @override
  Widget build(BuildContext context) {
    const icon = AppColors.white; // nero come le lettere dell'insegna
    final actions = <(Widget, String, VoidCallback)>[
      (
        const Icon(Icons.shopping_bag_outlined, size: 27, color: icon),
        'Prodotti',
        () => Navigator.of(context).push(fadeRoute(const ProductsScreen())),
      ),
      if (settings.phone.isNotEmpty)
        (const Icon(Icons.call_outlined, size: 27, color: icon), 'Chiama', () => callPhone(context, settings.phone)),
      if (settings.whatsapp.isNotEmpty)
        (
          const Icon(Icons.chat_outlined, size: 27, color: icon),
          'WhatsApp',
          () => openWhatsApp(context, settings.whatsapp),
        ),
      if (settings.instagram.isNotEmpty)
        (
          const InstagramIcon(size: 27, color: icon),
          'Instagram',
          () => openUrl(context, 'https://instagram.com/${settings.instagram.replaceAll('@', '')}'),
        ),
    ];

    return Row(
      children: [
        for (var i = 0; i < actions.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(
            child: Material(
              color: Colors.white.withValues(alpha: 0.55),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: AppColors.white.withValues(alpha: 0.12)),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: actions[i].$3,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: Column(
                    children: [
                      actions[i].$1,
                      const SizedBox(height: 8),
                      // su telefoni stretti l'etichetta si riduce invece di andare a capo
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            actions[i].$2,
                            maxLines: 1,
                            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: AppColors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// "Il tuo prossimo appuntamento": data in nero a sinistra, servizio e ora,
/// barbiere e stato.
class _NextAppointmentCard extends StatelessWidget {
  const _NextAppointmentCard({required this.appointment});
  final Appointment appointment;

  @override
  Widget build(BuildContext context) {
    final a = appointment;
    return Material(
      color: Colors.white.withValues(alpha: 0.7),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppColors.white.withValues(alpha: 0.14)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(fadeRoute(const AccountScreen())),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Container(
                width: 54,
                padding: const EdgeInsets.symmetric(vertical: 7),
                decoration: BoxDecoration(color: AppColors.quiet, borderRadius: BorderRadius.circular(12)),
                child: Column(
                  children: [
                    Text(
                      fmtDayShort(a.start).split(' ').first.toUpperCase(),
                      style: const TextStyle(
                        color: AppColors.quietText,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                      ),
                    ),
                    Text(
                      '${a.start.day}',
                      style: slab(size: 22, color: AppColors.quietText, weight: FontWeight.w700, spacing: 0),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'IL TUO PROSSIMO APPUNTAMENTO',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: AppColors.muted, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${a.serviceName} · ${fmtTime(a.start)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            a.barberName.isEmpty ? '' : 'con ${a.barberName}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: AppColors.silver, fontSize: 13),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFDDF1E3),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text(
                            'Confermato',
                            style: TextStyle(color: AppColors.success, fontSize: 11.5, fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ),
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
