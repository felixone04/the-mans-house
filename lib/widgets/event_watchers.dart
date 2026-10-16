import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/slots.dart';
import '../models.dart';
import '../notifications.dart';
import '../state/app_state.dart';
import 'common.dart';
import 'notif_banner.dart';

Future<SharedPreferences?> _prefs() async {
  try {
    return await SharedPreferences.getInstance();
  } catch (_) {
    return null; // senza memoria locale niente avvisi «da ultima volta»
  }
}

Map<String, String>? _readSnap(SharedPreferences? p, String key) {
  final raw = p?.getString(key);
  if (raw == null) return null;
  try {
    return Map<String, String>.from(jsonDecode(raw) as Map);
  } catch (_) {
    return null;
  }
}

/// Avvisi per il cliente dentro l'app (stile essenziale): posto assegnato
/// dalla lista d'attesa, appuntamento spostato o annullato dal negozio,
/// chiusure del negozio nei prossimi giorni.
class ClientEventWatcher extends StatefulWidget {
  const ClientEventWatcher({super.key});

  @override
  State<ClientEventWatcher> createState() => _ClientEventWatcherState();
}

class _ClientEventWatcherState extends State<ClientEventWatcher> {
  String? _lastSig;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = AppScope.of(context);
    if (!state.isSignedIn || state.isAdmin || state.profile == null) return;
    final sig = '${state.profile!.id}:${apptSnapshot(state.myAppointments)}:${state.shopDays.length}';
    if (sig == _lastSig) return;
    _lastSig = sig;
    WidgetsBinding.instance.addPostFrameCallback((_) => _check(state));
  }

  Future<void> _check(AppState state) async {
    final p = await _prefs();
    if (!mounted) return;
    final n = NotifSettings.fromJson(state.settings.notifications);
    final key = 'snap_${state.profile!.id}';
    final now = DateTime.now();
    final events = clientEvents(_readSnap(p, key), state.myAppointments, state.ownChanges, now);
    await p?.setString(key, jsonEncode(apptSnapshot(state.myAppointments)));
    if (!mounted) return;
    for (final (k, a) in events.take(3)) {
      final c = n.build(k, notifValues(a, state.settings, clientName: state.profile?.fullName ?? ''));
      if (c != null) showNotifBanner(context, c);
    }

    // chiusure e orari speciali dei prossimi 7 giorni, una volta sola
    final seen = p?.getStringList('seen_notices') ?? const <String>[];
    final today = dayOnly(now);
    for (final d in state.shopDays) {
      final id = d.day.toIso8601String().substring(0, 10);
      if (d.day.isBefore(today) || d.day.isAfter(today.add(const Duration(days: 7))) || seen.contains(id)) continue;
      final msg = d.closed
          ? '${fmtDayLong(d.day)} siamo chiusi${d.note.isEmpty ? '' : ' · ${d.note}'}'
          : '${fmtDayLong(d.day)} orario speciale ${formatTime(d.open!)}–${formatTime(d.close!)}';
      final c = n.build(NotifKind.shopNotice, {
        'messaggio': msg,
        'nome': (state.profile?.fullName ?? '').split(' ').first,
        'negozio': state.settings.name,
      });
      await p?.setStringList('seen_notices', [...seen, id]);
      if (c != null && mounted) showNotifBanner(context, c);
      break; // uno per apertura
    }
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// Avvisi per il negozio all'apertura dell'area riservata: nuove prenotazioni
/// e annullamenti dei clienti, persone in lista d'attesa, prodotti da riordinare.
Future<void> checkShopEvents(BuildContext context) async {
  final state = AppScope.read(context);
  if (!state.isAdmin) return;
  final p = await _prefs();
  final n = NotifSettings.fromJson(state.settings.notifications);
  final now = DateTime.now();
  final shown = <NotifContent>[];
  try {
    // prenotazioni e annullamenti dei prossimi 30 giorni
    final list = await state.backend.appointmentsBetween(now, now.add(const Duration(days: 30)));
    final events = shopEvents(_readSnap(p, 'shop_snap'), list, state.ownChanges, now);
    await p?.setString('shop_snap', jsonEncode(apptSnapshot(list)));
    for (final (k, a) in events) {
      final c = n.build(k, notifValues(a, state.settings));
      if (c != null) shown.add(c);
    }

    // lista d'attesa: se e' cresciuta dall'ultima volta
    final waiting = await state.backend.fetchWaitlist(now, now.add(const Duration(days: 61)));
    final before = p?.getInt('shop_waiting');
    await p?.setInt('shop_waiting', waiting.length);
    if (before != null && waiting.length > before && waiting.isNotEmpty) {
      final last = waiting.reduce((x, y) => x.createdAt.isAfter(y.createdAt) ? x : y);
      final same = waiting.where((w) => w.start == last.start).length;
      final c = n.build(NotifKind.waitlistShop, {
        'persone': same == 1 ? '1 persona' : '$same persone',
        'giorno': fmtDayShort(last.start).toLowerCase(),
        'ora': fmtTime(last.start),
        'barbiere': last.barberName.isEmpty ? 'il primo disponibile' : last.barberName,
      });
      if (c != null) shown.add(c);
    }

    // prodotti scesi sotto la soglia
    final products = await state.backend.fetchProducts(includeInactive: true);
    final stock = await state.backend.fetchStock();
    final low = [for (final pr in products) if (pr.active && (stock[pr.id]?.low ?? false)) pr];
    final known = p?.getStringList('shop_low');
    await p?.setStringList('shop_low', [for (final pr in low) pr.id]);
    if (known != null) {
      for (final pr in low.where((pr) => !known.contains(pr.id))) {
        final s = stock[pr.id]!;
        final c = n.build(NotifKind.lowStock, {
          'prodotto': pr.name,
          'rimasti': '${s.stock}',
          'soglia': '${s.threshold}',
        });
        if (c != null) shown.add(c);
      }
    }
  } catch (_) {
    // gli avvisi sono un di piu': se qualcosa non si carica si riprova alla prossima apertura
  }
  if (!context.mounted) return;
  for (final c in shown.take(4)) {
    showNotifBanner(context, c);
  }
}
