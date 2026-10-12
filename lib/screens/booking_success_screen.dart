import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'account_screen.dart';

class BookingSuccessScreen extends StatefulWidget {
  const BookingSuccessScreen({super.key, required this.appointment});
  final Appointment appointment;

  @override
  State<BookingSuccessScreen> createState() => _BookingSuccessScreenState();
}

class _BookingSuccessScreenState extends State<BookingSuccessScreen> with SingleTickerProviderStateMixin {
  late final _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))..forward();

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.appointment;
    return AppScaffold(
      body: SafeArea(
        child: FitBody(
          maxWidth: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ScaleTransition(
                scale: CurvedAnimation(parent: _anim, curve: Curves.elasticOut),
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: const BoxDecoration(color: AppColors.white, shape: BoxShape.circle),
                  child: const Icon(Icons.check, size: 56, color: AppColors.black),
                ),
              ),
              const SizedBox(height: 28),
              Text(
                'PRENOTAZIONE CONFERMATA',
                textAlign: TextAlign.center,
                style: slab(size: 20, weight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              const Ornament(width: 180),
              const SizedBox(height: 10),
              const Text('Ti aspettiamo!', style: TextStyle(color: AppColors.silver, fontSize: 15)),
              const SizedBox(height: 28),
              GlassCard(
                child: SizedBox(
                  width: double.infinity,
                  child: Column(
                    children: [
                      Text(a.serviceName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      Text(fmtDayLong(a.start), style: const TextStyle(color: AppColors.silver)),
                      Text('ore ${fmtTime(a.start)}', style: slab(size: 28, weight: FontWeight.w700)),
                      if (a.barberName.isNotEmpty)
                        Text('con ${a.barberName}', style: const TextStyle(color: AppColors.silver)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.chat_outlined, size: 18, color: AppColors.muted),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Ti invieremo un promemoria su WhatsApp 24 ore e 1 ora prima dell\'appuntamento.',
                      style: TextStyle(color: AppColors.muted, fontSize: 13, height: 1.4),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              PrimaryButton(label: 'Torna alla home', onPressed: () => Navigator.of(context).pop()),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => Navigator.of(context).pushReplacement(fadeRoute(const AccountScreen())),
                child: const Text('I miei appuntamenti'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
