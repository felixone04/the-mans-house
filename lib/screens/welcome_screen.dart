import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/phone_notifier.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'home_screen.dart';

const _doneKey = 'welcome_done';

/// Il benvenuto va mostrato? (solo alla prima apertura)
Future<bool> shouldShowWelcome() async {
  try {
    final p = await SharedPreferences.getInstance();
    return !(p.getBool(_doneKey) ?? false);
  } catch (_) {
    return false;
  }
}

/// Benvenuto alla prima apertura: tre schermate semplici e, sull'app
/// installata, la richiesta del permesso per le notifiche.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final _pages = PageController();
  int _page = 0;

  static const _items = [
    (
      Icons.calendar_month_outlined,
      'Prenota in pochi tocchi',
      'Scegli il servizio, il barbiere e l\'orario: ti arriva la conferma e un promemoria prima.',
    ),
    (
      Icons.hourglass_bottom,
      'Orario pieno? Mettiti in lista',
      'Tocca un orario occupato: se si libera, il posto è tuo in automatico.',
    ),
    (
      Icons.notifications_active_outlined,
      'Ti avvisiamo noi',
      'Promemoria, conferma presenza il giorno prima e novità del negozio, direttamente sul telefono.',
    ),
  ];

  bool get _last => _page == _items.length - 1;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _finish({bool askNotifications = false}) async {
    if (askNotifications) await PhoneNotifier.instance.requestPermission();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_doneKey, true);
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).pushReplacement(fadeRoute(const HomeScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final phone = PhoneNotifier.instance.supported;
    return AppScaffold(
      spotlight: true,
      body: SafeArea(
        child: ResponsiveCenter(
          maxWidth: 520,
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(onPressed: () => _finish(), child: const Text('Salta')),
              ),
              Expanded(
                child: PageView(
                  controller: _pages,
                  onPageChanged: (i) => setState(() => _page = i),
                  children: [
                    for (final (icon, title, text) in _items)
                      LayoutBuilder(
                        builder: (context, c) => Center(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: SizedBox(
                              width: c.maxWidth,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 120,
                                    height: 120,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.6),
                                      shape: BoxShape.circle,
                                      border: Border.all(color: AppColors.white.withValues(alpha: 0.12)),
                                    ),
                                    child: Icon(icon, size: 54, color: AppColors.white),
                                  ),
                                  const SizedBox(height: 28),
                                  Text(
                                    title,
                                    textAlign: TextAlign.center,
                                    style: slab(size: 24, weight: FontWeight.w700, spacing: 0),
                                  ),
                                  const SizedBox(height: 12),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 12),
                                    child: Text(
                                      text,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(color: AppColors.silver, fontSize: 15.5, height: 1.45),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < _items.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: i == _page ? 22 : 8,
                      height: 8,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: i == _page ? AppColors.white : AppColors.white.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton(
                  onPressed: () => _last
                      ? _finish(askNotifications: phone)
                      : _pages.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.quiet,
                    foregroundColor: AppColors.quietText,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    textStyle: exo(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                  child: Text(_last ? (phone ? 'Attiva le notifiche' : 'Inizia') : 'Avanti'),
                ),
              ),
              SizedBox(
                height: 44,
                child: _last && phone
                    ? TextButton(onPressed: () => _finish(), child: const Text('Non ora'))
                    : null,
              ),
              const SizedBox(height: 6),
            ],
          ),
        ),
      ),
    );
  }
}
