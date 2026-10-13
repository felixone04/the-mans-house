import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../data/slots.dart';
import '../models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'account_screen.dart';
import 'admin/admin_screen.dart';
import 'auth_screen.dart';
import 'booking_screen.dart';

/// Home: schermata unica, senza scorrimento.
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
      body: SafeArea(
        child: ResponsiveCenter(
          maxWidth: 560,
          child: Column(children: [
            const SizedBox(height: 8),
            Row(children: [
              // grigio e compatto: visibile ma senza rubare la scena al logo
              FilledButton.icon(
                onPressed: () => Navigator.of(context).push(fadeRoute(const BookingScreen())),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.quiet,
                  foregroundColor: AppColors.quietText,
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  side: const BorderSide(color: AppColors.quietBorder),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  textStyle: GoogleFonts.exo2(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.1),
                ),
                icon: const Icon(Icons.content_cut, size: 15),
                label: const Text('PRENOTA ORA'),
              ),
              const Spacer(),
              if (state.isAdmin)
                IconButton(
                  tooltip: 'Area riservata',
                  onPressed: () => Navigator.of(context).push(fadeRoute(const AdminScreen())),
                  icon: const Icon(Icons.dashboard_customize_outlined, size: 20, color: AppColors.quietText),
                ),
              _AccountButton(onTap: () => _openAccount(context)),
            ]),
            Expanded(
              child: LayoutBuilder(builder: (context, c) {
                final logoH = (c.maxHeight * 0.55).clamp(140.0, 340.0);
                return Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: SizedBox(
                      width: c.maxWidth,
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        AppLogo(height: logoH),
                        const SizedBox(height: 18),
                        const Ornament(width: 200),
                        const SizedBox(height: 12),
                        Text(s.tagline.toUpperCase(),
                            textAlign: TextAlign.center,
                            style: slab(size: 12, color: AppColors.silver, spacing: 4)),
                        if (next != null) ...[
                          const SizedBox(height: 28),
                          _NextAppointmentCard(appointment: next),
                        ],
                      ]),
                    ),
                  ),
                );
              }),
            ),
            _QuickActions(settings: s, barbers: state.barbers),
            const SizedBox(height: 16),
            Text(
              s.address.toUpperCase(),
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.muted, fontSize: 11.5, letterSpacing: 2.2, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 14),
          ]),
        ),
      ),
    );
  }
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
          width: 36,
          height: 36,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.quiet,
            border: Border.fromBorderSide(BorderSide(color: AppColors.quietBorder)),
          ),
          alignment: Alignment.center,
          child: signedIn && initials != null
              ? Text(initials, style: slab(size: 12.5, color: AppColors.quietText, weight: FontWeight.w700, spacing: 0.5))
              : Icon(signedIn ? Icons.person : Icons.person_outline, color: AppColors.quietText, size: 18),
        ),
      ),
    );
  }
}

void showHoursSheet(BuildContext context, List<Barber> barbers) {
  final today = DateTime.now().weekday;
  showModalBottomSheet<void>(
    context: context,
    constraints: const BoxConstraints(maxWidth: 520),
    builder: (c) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('ORARI DI APERTURA', style: slab(size: 16, weight: FontWeight.w600)),
          const SizedBox(height: 16),
          for (var d = 1; d <= 7; d++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(children: [
                Expanded(
                  child: Text(weekdayNames[d - 1],
                      style: TextStyle(
                          fontWeight: d == today ? FontWeight.w800 : FontWeight.w500,
                          color: d == today ? AppColors.white : AppColors.silver)),
                ),
                Text(
                  shopHoursFor(barbers, d).isEmpty
                      ? 'Chiuso'
                      : shopHoursFor(barbers, d).map((r) => '${formatTime(r[0])} – ${formatTime(r[1])}').join('  ·  '),
                  style: TextStyle(
                      fontWeight: d == today ? FontWeight.w800 : FontWeight.w500,
                      color: shopHoursFor(barbers, d).isEmpty ? AppColors.muted : AppColors.white),
                ),
              ]),
            ),
        ]),
      ),
    ),
  );
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.settings, required this.barbers});
  final ShopSettings settings;
  final List<Barber> barbers;

  @override
  Widget build(BuildContext context) {
    final actions = <(IconData, String, VoidCallback)>[
      (Icons.near_me_outlined, 'Indicazioni', () => openUrl(context, settings.mapsUrl)),
      (Icons.schedule, 'Orari', () => showHoursSheet(context, barbers)),
      if (settings.phone.isNotEmpty) (Icons.call_outlined, 'Chiama', () => callPhone(context, settings.phone)),
      if (settings.whatsapp.isNotEmpty)
        (Icons.chat_outlined, 'WhatsApp', () => openWhatsApp(context, settings.whatsapp)),
      if (settings.instagram.isNotEmpty)
        (
          Icons.camera_alt_outlined,
          'Instagram',
          () => openUrl(context, 'https://instagram.com/${settings.instagram.replaceAll('@', '')}')
        ),
    ].take(4).toList();

    // Unica barra incorniciata con separatori sottili: piu' pulita di 4 riquadri
    return Container(
      decoration: BoxDecoration(
        border: Border.symmetric(horizontal: BorderSide(color: AppColors.white.withValues(alpha: 0.18))),
      ),
      child: IntrinsicHeight(
        child: Row(children: [
          for (var i = 0; i < actions.length; i++) ...[
            if (i > 0) VerticalDivider(width: 1, indent: 14, endIndent: 14, color: AppColors.white.withValues(alpha: 0.14)),
            Expanded(
              child: InkWell(
                onTap: actions[i].$3,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Column(children: [
                    Icon(actions[i].$1, size: 21, color: AppColors.white),
                    const SizedBox(height: 7),
                    Text(actions[i].$2.toUpperCase(),
                        style: const TextStyle(
                            fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: AppColors.silver)),
                  ]),
                ),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}

class _NextAppointmentCard extends StatelessWidget {
  const _NextAppointmentCard({required this.appointment});
  final Appointment appointment;

  @override
  Widget build(BuildContext context) {
    final a = appointment;
    return GlassCard(
      selected: true,
      onTap: () => Navigator.of(context).push(fadeRoute(const AccountScreen())),
      child: Row(children: [
        Container(
          width: 52,
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(10)),
          child: Column(children: [
            Text(fmtDayShort(a.start).split(' ').first.toUpperCase(),
                style: const TextStyle(color: AppColors.black, fontSize: 10, fontWeight: FontWeight.w800)),
            Text('${a.start.day}', style: slab(size: 20, color: AppColors.black, weight: FontWeight.w700)),
          ]),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('IL TUO PROSSIMO APPUNTAMENTO',
                style: TextStyle(color: AppColors.muted, fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
            const SizedBox(height: 3),
            Text('${a.serviceName} · ${fmtTime(a.start)}',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            if (a.barberName.isNotEmpty)
              Text('con ${a.barberName}', style: const TextStyle(color: AppColors.silver, fontSize: 13)),
          ]),
        ),
        const Icon(Icons.chevron_right, color: AppColors.muted),
      ]),
    );
  }
}
