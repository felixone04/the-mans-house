import 'package:flutter/material.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'admin/admin_screen.dart';
import 'booking_screen.dart';
import 'complete_profile_screen.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  bool _showPast = false;

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
    await AppScope.read(context).signOut();
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
    final upcoming = state.myAppointments.where((a) => a.isUpcoming).toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    final past = state.myAppointments.where((a) => !a.isUpcoming).toList();
    final minCancel = state.settings.minCancelHours;

    return AppScaffold(
      title: 'Il mio account',
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: state.refreshAppointments,
          child: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              ResponsiveCenter(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const SizedBox(height: 8),
                  GlassCard(
                    child: Row(children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: AppColors.white,
                        child: Text(
                          (p?.fullName.isNotEmpty ?? false) ? p!.fullName[0].toUpperCase() : '?',
                          style: slab(size: 22, color: AppColors.black, weight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(p?.fullName.isNotEmpty == true ? p!.fullName : 'Cliente',
                              style: slab(size: 18, weight: FontWeight.w600, spacing: 0.4)),
                          const SizedBox(height: 2),
                          Text(p?.email ?? '', style: const TextStyle(color: AppColors.silver, fontSize: 13)),
                          if (p?.phone.isNotEmpty ?? false)
                            Text(p!.phone, style: const TextStyle(color: AppColors.silver, fontSize: 13)),
                        ]),
                      ),
                      IconButton(
                        tooltip: 'Modifica profilo',
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => Navigator.of(context)
                            .push(fadeRoute(const CompleteProfileScreen(editing: true))),
                      ),
                    ]),
                  ),
                  if (state.isAdmin) ...[
                    const SizedBox(height: 12),
                    GlassCard(
                      onTap: () => Navigator.of(context).push(fadeRoute(const AdminScreen())),
                      child: const Row(children: [
                        Icon(Icons.dashboard_customize_outlined),
                        SizedBox(width: 14),
                        Expanded(
                          child: Text('Area riservata', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                        ),
                        Icon(Icons.chevron_right, color: AppColors.muted),
                      ]),
                    ),
                  ],
                  SectionTitle('Prossimi appuntamenti'),
                  if (upcoming.isEmpty)
                    GlassCard(
                      child: Column(children: [
                        const EmptyState(icon: Icons.event_available, text: 'Nessun appuntamento in programma'),
                        OutlinedButton.icon(
                          onPressed: () => Navigator.of(context).pushReplacement(fadeRoute(const BookingScreen())),
                          icon: const Icon(Icons.content_cut, size: 18),
                          label: const Text('Prenota ora'),
                        ),
                        const SizedBox(height: 8),
                      ]),
                    ),
                  for (final a in upcoming)
                    _AppointmentTile(
                      appointment: a,
                      onCancel: a.start.isAfter(DateTime.now().add(Duration(hours: minCancel))) ? () => _cancel(a) : null,
                      cancelHint: 'Annullabile fino a $minCancel ore prima',
                    ),
                  if (past.isNotEmpty) ...[
                    SectionTitle(
                      'Storico',
                      trailing: TextButton(
                        onPressed: () => setState(() => _showPast = !_showPast),
                        child: Text(_showPast ? 'Nascondi' : 'Mostra (${past.length})'),
                      ),
                    ),
                    if (_showPast) for (final a in past) _AppointmentTile(appointment: a),
                  ],
                  const SizedBox(height: 28),
                  OutlinedButton.icon(
                    onPressed: _signOut,
                    icon: const Icon(Icons.logout),
                    label: const Text('Esci'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _deleteAccount,
                    style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                    child: const Text('Elimina account'),
                  ),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AppointmentTile extends StatelessWidget {
  const _AppointmentTile({required this.appointment, this.onCancel, this.cancelHint});
  final Appointment appointment;
  final VoidCallback? onCancel;
  final String? cancelHint;

  @override
  Widget build(BuildContext context) {
    final a = appointment;
    final upcoming = a.isUpcoming;
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(fmtDayLong(a.start),
                style: TextStyle(fontWeight: FontWeight.w700, color: upcoming ? AppColors.white : AppColors.silver)),
          ),
          StatusBadge(a.status),
        ]),
        const SizedBox(height: 6),
        Text('${fmtTime(a.start)} – ${fmtTime(a.end)}  ·  ${a.serviceName}',
            style: const TextStyle(color: AppColors.silver)),
        if (a.barberName.isNotEmpty)
          Text('con ${a.barberName}  ·  ${fmtPrice(a.price)}', style: const TextStyle(color: AppColors.muted, fontSize: 13)),
        if (upcoming) ...[
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: Text(onCancel == null ? 'Per annullare contatta il negozio' : (cancelHint ?? ''),
                  style: const TextStyle(color: AppColors.muted, fontSize: 11.5)),
            ),
            if (onCancel != null)
              TextButton.icon(
                onPressed: onCancel,
                style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                icon: const Icon(Icons.close, size: 18),
                label: const Text('Annulla'),
              ),
          ]),
        ],
      ]),
    );
  }
}
