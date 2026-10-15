import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'home_screen.dart';

/// Apertura: logo su sfondo nero sfumato, mentre si caricano i dati.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..forward();
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    setState(() => _failed = false);
    final state = AppScope.read(context);
    try {
      await Future.wait([
        state.load(),
        Future<void>.delayed(const Duration(milliseconds: 2000)),
      ]);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(fadeRoute(const HomeScreen()));
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    // stessa misura della scritta in home: il passaggio alla home e' continuo
    final logoHeight = ((size.width - 40).clamp(0.0, 520.0) * 0.6).clamp(160.0, 560.0);
    final fade = CurvedAnimation(parent: _anim, curve: const Interval(0, 0.7, curve: Curves.easeOut));
    final scale = Tween(
      begin: 0.96,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _anim, curve: const Interval(0, 0.9, curve: Curves.easeOutCubic)));

    return Scaffold(
      body: AppBackground(
        spotlight: true,
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            FadeTransition(
              opacity: fade,
              child: ScaleTransition(
                scale: scale,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: AppLogo(height: logoHeight, subtitle: 'Barber Shop · Andria'),
                ),
              ),
            ),
            if (_failed) ...[
              const SizedBox(height: 32),
              const Text('Connessione non disponibile', style: TextStyle(color: AppColors.muted)),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _start,
                icon: const Icon(Icons.refresh),
                label: const Text('Riprova'),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}
