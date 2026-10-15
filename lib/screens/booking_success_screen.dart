import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../data/calendar.dart';
import '../models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Prenotazione confermata: riepilogo, promemoria, aggiungi al calendario.
class BookingSuccessScreen extends StatefulWidget {
  const BookingSuccessScreen({super.key, required this.appointment});
  final Appointment appointment;

  @override
  State<BookingSuccessScreen> createState() => _BookingSuccessScreenState();
}

class _BookingSuccessScreenState extends State<BookingSuccessScreen> with SingleTickerProviderStateMixin {
  late final _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))..forward();

  static const _green = Color(0xFF1F9D55);

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  Future<void> _addToCalendar() async {
    final s = AppScope.read(context).settings;
    final event = CalendarEvent.fromAppointment(widget.appointment, shopName: "The Man's House", address: s.address);
    final choice = await showModalBottomSheet<String>(
      context: context,
      constraints: const BoxConstraints(maxWidth: 520),
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.event_outlined),
              title: const Text('Google Calendar'),
              onTap: () => Navigator.pop(c, 'google'),
            ),
            ListTile(
              leading: const Icon(Icons.calendar_month_outlined),
              title: const Text('Calendario Apple, Outlook o altro'),
              subtitle: const Text('File .ics con promemoria un\'ora prima'),
              onTap: () => Navigator.pop(c, 'ics'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == 'google') {
      await openUrl(context, event.googleUrl.toString());
      return;
    }
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(utf8.encode(event.toIcs()), mimeType: 'text/calendar', name: 'appuntamento.ics'),
          ],
          fileNameOverrides: ['appuntamento.ics'],
        ),
      );
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.appointment;
    final settings = AppScope.of(context).settings;
    Widget row(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Text(label, style: const TextStyle(color: AppColors.silver, fontSize: 14)),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
            ),
          ),
        ],
      ),
    );
    final divider = Divider(height: 1, color: AppColors.white.withValues(alpha: 0.1));

    return AppScaffold(
      body: SafeArea(
        child: FitBody(
          maxWidth: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: ScaleTransition(
                  scale: CurvedAnimation(parent: _anim, curve: Curves.elasticOut),
                  child: Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      color: const Color(0xFFDDF1E3),
                      shape: BoxShape.circle,
                      border: Border.all(color: _green, width: 2),
                    ),
                    child: const Icon(Icons.check, size: 46, color: _green),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Prenotazione confermata',
                textAlign: TextAlign.center,
                style: slab(size: 22, weight: FontWeight.w700, spacing: 0),
              ),
              const SizedBox(height: 4),
              const Text(
                "Ti aspettiamo da The Man's House",
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.silver, fontSize: 14.5),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.white.withValues(alpha: 0.12)),
                ),
                child: Column(
                  children: [
                    row('Servizio', a.serviceName),
                    if (a.barberName.isNotEmpty) ...[divider, row('Barbiere', a.barberName)],
                    divider,
                    row('Giorno', capitalize(fmtDayLong(a.start))),
                    divider,
                    row('Ora', '${fmtTime(a.start)} – ${fmtTime(a.end)}'),
                    divider,
                    row('Prezzo', fmtPrice(a.price)),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.chat_outlined, size: 18, color: _green),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Ti invieremo un promemoria su WhatsApp 24 ore e 1 ora prima.',
                      style: TextStyle(color: AppColors.white, fontSize: 13, height: 1.4),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF1DB),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE0A030)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 18, color: Color(0xFF8A4B00)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Puoi spostarlo o annullarlo dall\'app fino a ${settings.minCancelHours} '
                        '${settings.minCancelHours == 1 ? 'ora' : 'ore'} prima.',
                        style: const TextStyle(color: Color(0xFF6B3A00), fontSize: 13, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: _addToCalendar,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.white,
                    side: const BorderSide(color: AppColors.white, width: 1.4),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    textStyle: exo(fontSize: 15, fontWeight: FontWeight.w800),
                  ),
                  icon: const Icon(Icons.event_available_outlined),
                  label: const Text('Aggiungi al calendario'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 56,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.quiet,
                    foregroundColor: AppColors.quietText,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    textStyle: exo(fontSize: 15.5, fontWeight: FontWeight.w800),
                  ),
                  child: const Text('Torna alla home'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
