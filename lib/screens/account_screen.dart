import 'package:flutter/material.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'admin/admin_screen.dart';
import 'booking_screen.dart';
import 'complete_profile_screen.dart';
import 'guest_screen.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => AppScope.read(context).refreshAppointments());
  }

  Future<void> _cancel(Appointment a) async {
    final ok = await confirmDialog(
      context,
      title: 'Annullare l\'appuntamento?',
      message: '${a.serviceName}\n${fmtDayLong(a.start)} alle ${fmtTime(a.start)}',
      confirm: 'Annulla appuntamento',
      destructive: true,
    );
    if (!ok || !mounted) return;
    final state = AppScope.read(context);
    try {
      await state.backend.cancelAppointment(a.id);
      await state.refreshAppointments();
      if (mounted) showMessage(context, 'Appuntamento annullato');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _signOut() async {
    final state = AppScope.read(context);
    // l'ospite che esce non puo' piu' rientrare: meglio creare prima l'account
    if (state.isGuest) {
      final ok = await confirmDialog(
        context,
        title: 'Uscire senza account?',
        message:
            'Sei collegato come ospite: uscendo non vedrai più i tuoi appuntamenti nell\'app '
            '(restano validi, e ricevi comunque i promemoria). Crea l\'account per non perderli.',
        confirm: 'Esci comunque',
        destructive: true,
      );
      if (!ok || !mounted) return;
    }
    await state.signOut();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _deleteAccount() async {
    final ok = await confirmDialog(
      context,
      title: 'Eliminare l\'account?',
      message: 'Il tuo profilo verrà eliminato definitivamente e gli appuntamenti futuri annullati.',
      confirm: 'Elimina',
      destructive: true,
    );
    if (!ok || !mounted) return;
    final state = AppScope.read(context);
    try {
      await state.backend.deleteAccount();
      await state.refreshProfile();
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final p = state.profile;
    final upcoming = _upcoming(state);
    final past = _past(state);
    final shown = upcoming.take(2).toList();
    Widget tile(Appointment a) => _tile(state, a);

    return AppScaffold(
      title: 'Il mio account',
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: FitBody(
                alignment: Alignment.topCenter,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 8),
                    GlassCard(
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 26,
                            backgroundColor: AppColors.white,
                            child: Text(
                              (p?.fullName.isNotEmpty ?? false) ? p!.fullName[0].toUpperCase() : '?',
                              style: slab(size: 21, color: AppColors.black, weight: FontWeight.w700),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  p?.fullName.isNotEmpty == true ? p!.fullName : 'Cliente',
                                  style: slab(size: 18, weight: FontWeight.w600, spacing: 0.4),
                                ),
                                const SizedBox(height: 2),
                                Text(p?.email ?? '', style: const TextStyle(color: AppColors.silver, fontSize: 13)),
                                if (p?.phone.isNotEmpty ?? false)
                                  Text(p!.phone, style: const TextStyle(color: AppColors.silver, fontSize: 13)),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Modifica profilo',
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () =>
                                Navigator.of(context).push(fadeRoute(const CompleteProfileScreen(editing: true))),
                          ),
                        ],
                      ),
                    ),
                    if (state.isGuest) ...[
                      const SizedBox(height: 10),
                      GlassCard(
                        padding: const EdgeInsets.fromLTRB(16, 13, 10, 13),
                        onTap: () => Navigator.of(context).push(fadeRoute(const GuestUpgradeScreen())),
                        child: const Row(
                          children: [
                            Icon(Icons.verified_user_outlined),
                            SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Crea il tuo account', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                                  Text(
                                    'Sei ospite: con l\'account prenoti più in fretta e non perdi i tuoi appuntamenti',
                                    style: TextStyle(color: AppColors.muted, fontSize: 12.5),
                                  ),
                                ],
                              ),
                            ),
                            Icon(Icons.chevron_right),
                          ],
                        ),
                      ),
                    ],
                    if (state.isAdmin) ...[
                      const SizedBox(height: 10),
                      GlassCard(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                        onTap: () => Navigator.of(context).push(fadeRoute(const AdminScreen())),
                        child: const Row(
                          children: [
                            Icon(Icons.dashboard_customize_outlined),
                            SizedBox(width: 14),
                            Expanded(
                              child: Text(
                                'Area riservata',
                                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                              ),
                            ),
                            Icon(Icons.chevron_right, color: AppColors.muted),
                          ],
                        ),
                      ),
                    ],
                    SectionTitle(
                      'Prossimi appuntamenti',
                      trailing: upcoming.length > shown.length
                          ? TextButton(
                              onPressed: () => _showList(
                                'Prossimi appuntamenti',
                                (s) => _upcoming(s).map((a) => _tile(s, a)).toList(),
                              ),
                              child: Text('Vedi tutti (${upcoming.length})'),
                            )
                          : null,
                    ),
                    if (upcoming.isEmpty)
                      GlassCard(
                        child: Column(
                          children: [
                            const EmptyState(icon: Icons.event_available, text: 'Nessun appuntamento in programma'),
                            OutlinedButton.icon(
                              onPressed: () => Navigator.of(context).pushReplacement(fadeRoute(const BookingScreen())),
                              icon: const Icon(Icons.content_cut, size: 18),
                              label: const Text('Prenota ora'),
                            ),
                            const SizedBox(height: 8),
                          ],
                        ),
                      ),
                    for (final a in shown) tile(a),
                  ],
                ),
              ),
            ),
            ResponsiveCenter(
              child: Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 12),
                child: Row(
                  children: [
                    if (past.isNotEmpty) ...[
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _showList(
                            'Storico',
                            (s) => _past(s).map((a) => _AppointmentTile(appointment: a)).toList(),
                          ),
                          icon: const Icon(Icons.history, size: 18),
                          label: Text('Storico (${past.length})'),
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _signOut,
                        icon: const Icon(Icons.logout, size: 18),
                        label: const Text('Esci'),
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      tooltip: 'Elimina account',
                      onPressed: _deleteAccount,
                      icon: const Icon(Icons.person_remove_outlined, color: AppColors.danger),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Appointment> _upcoming(AppState state) =>
      state.myAppointments.where((a) => a.isUpcoming).toList()..sort((a, b) => a.start.compareTo(b.start));

  List<Appointment> _past(AppState state) => state.myAppointments.where((a) => !a.isUpcoming).toList();

  Widget _tile(AppState state, Appointment a) {
    final minCancel = state.settings.minCancelHours;
    final editable = a.start.isAfter(DateTime.now().add(Duration(hours: minCancel)));
    return _AppointmentTile(
      appointment: a,
      onCancel: editable ? () => _cancel(a) : null,
      onMove: editable ? () => _move(a) : null,
      cancelHint: 'Modificabile fino a $minCancel ore prima',
    );
  }

  Future<void> _move(Appointment a) async {
    // dal pannello "Vedi tutti" si chiude prima il pannello
    final nav = Navigator.of(context);
    if (nav.canPop() && ModalRoute.of(context)?.isCurrent == false) nav.pop();
    await nav.push<bool>(fadeRoute(BookingScreen(reschedule: a)));
  }

  /// Elenco completo in un pannello dal basso (la pagina resta fissa).
  /// Le righe si ricostruiscono dallo stato: annullando un appuntamento dal
  /// pannello l'elenco si aggiorna (prima restava "Confermato").
  void _showList(String title, List<Widget> Function(AppState) tiles) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (c) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (c, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Center(
              child: Text(title.toUpperCase(), style: slab(size: 16, weight: FontWeight.w600, spacing: 2)),
            ),
            const SizedBox(height: 16),
            ...tiles(AppScope.of(c)),
          ],
        ),
      ),
    );
  }
}

class _AppointmentTile extends StatelessWidget {
  const _AppointmentTile({required this.appointment, this.onCancel, this.onMove, this.cancelHint});
  final Appointment appointment;
  final VoidCallback? onCancel;
  final VoidCallback? onMove;
  final String? cancelHint;

  @override
  Widget build(BuildContext context) {
    final a = appointment;
    final upcoming = a.isUpcoming;
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  fmtDayLong(a.start),
                  style: TextStyle(fontWeight: FontWeight.w700, color: upcoming ? AppColors.white : AppColors.silver),
                ),
              ),
              StatusBadge(a.status),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${fmtTime(a.start)} – ${fmtTime(a.end)}  ·  ${a.serviceName}',
            style: const TextStyle(color: AppColors.silver),
          ),
          if (a.barberName.isNotEmpty)
            Text(
              'con ${a.barberName}  ·  ${fmtPrice(a.price)}',
              style: const TextStyle(color: AppColors.muted, fontSize: 13),
            ),
          if (upcoming) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    onCancel == null ? 'Per modifiche contatta il negozio' : (cancelHint ?? ''),
                    style: const TextStyle(color: AppColors.muted, fontSize: 11.5),
                  ),
                ),
                if (onMove != null)
                  TextButton.icon(
                    onPressed: onMove,
                    style: TextButton.styleFrom(foregroundColor: AppColors.white),
                    icon: const Icon(Icons.edit_calendar_outlined, size: 18),
                    label: const Text('Sposta'),
                  ),
                if (onCancel != null)
                  TextButton.icon(
                    onPressed: onCancel,
                    style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                    icon: const Icon(Icons.close, size: 18),
                    label: const Text('Annulla'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
