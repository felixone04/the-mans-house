import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models.dart';
import '../notifications.dart';

/// Notifiche sul telefono (app installata su Android e iPhone): promemoria,
/// conferma presenza con «Ci sono» / «Annulla» e voto dopo il taglio,
/// programmati sul telefono stesso. Sul sito non fa nulla: li' gli avvisi
/// compaiono dentro la pagina.
class PhoneNotifier {
  PhoneNotifier._();
  static final instance = PhoneNotifier._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const actionConfirm = 'ci_sono';
  static const actionCancel = 'annulla';
  static const _attendanceCategory = 'presenza';

  /// Tocco su una notifica o su un suo pulsante: (pulsante, id appuntamento).
  void Function(String? action, String? appointmentId)? onResponse;

  bool get supported =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  Future<void> init() async {
    if (!supported || _ready) return;
    try {
      tzdata.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('Europe/Rome'));
      await _plugin.initialize(
        settings: InitializationSettings(
          android: const AndroidInitializationSettings('@mipmap/launcher_icon'),
          // il permesso si chiede dal benvenuto, non all'avvio
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
            notificationCategories: [
              DarwinNotificationCategory(
                _attendanceCategory,
                actions: [
                  DarwinNotificationAction.plain(
                    actionConfirm,
                    'Ci sono',
                    options: {DarwinNotificationActionOption.foreground},
                  ),
                  DarwinNotificationAction.plain(
                    actionCancel,
                    'Annulla',
                    options: {DarwinNotificationActionOption.foreground},
                  ),
                ],
              ),
            ],
          ),
        ),
        onDidReceiveNotificationResponse: (r) => onResponse?.call(r.actionId, r.payload),
      );
      _ready = true;
      // app aperta toccando una notifica
      final launch = await _plugin.getNotificationAppLaunchDetails();
      final r = launch?.notificationResponse;
      if ((launch?.didNotificationLaunchApp ?? false) && r != null) {
        Future<void>.delayed(const Duration(seconds: 1), () => onResponse?.call(r.actionId, r.payload));
      }
    } catch (e) {
      debugPrint('Notifiche non disponibili: $e');
    }
  }

  /// Chiede il permesso di mostrare notifiche. Ritorna true se concesso.
  Future<bool> requestPermission() async {
    if (!supported) return false;
    await init();
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        return await _plugin
                .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
                ?.requestNotificationsPermission() ??
            false;
      }
      return await _plugin
              .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
              ?.requestPermissions(alert: true, badge: true, sound: true) ??
          false;
    } catch (_) {
      return false;
    }
  }

  NotificationDetails _details(NotifKind k) {
    final attendance = k == NotifKind.attendanceCheck;
    final t = notifType(k);
    return NotificationDetails(
      android: AndroidNotificationDetails(
        t.forShop ? 'negozio' : 'appuntamenti',
        t.forShop ? 'Area riservata' : 'Appuntamenti',
        channelDescription: t.forShop ? 'Prenotazioni, lista d\'attesa e magazzino' : 'Promemoria e avvisi',
        importance: Importance.high,
        priority: Priority.high,
        color: t.fg,
        actions: attendance
            ? const [
                AndroidNotificationAction(actionConfirm, 'Ci sono', showsUserInterface: true),
                AndroidNotificationAction(actionCancel, 'Annulla', showsUserInterface: true),
              ]
            : null,
      ),
      iOS: DarwinNotificationDetails(categoryIdentifier: attendance ? _attendanceCategory : null),
    );
  }

  /// Mostra subito una notifica (es. posto assegnato dalla lista d'attesa).
  Future<void> showNow(int id, NotifContent c, {String? appointmentId}) async {
    if (!supported) return;
    await init();
    if (!_ready) return;
    try {
      await _plugin.show(
        id: id,
        title: c.title,
        body: c.body,
        notificationDetails: _details(c.type.kind),
        payload: appointmentId,
      );
    } catch (e) {
      debugPrint('Notifica non mostrata: $e');
    }
  }

  /// Riprogramma tutte le notifiche degli appuntamenti del cliente.
  Future<void> reschedule(List<Appointment> mine, ShopSettings s, {String clientName = ''}) async {
    if (!supported) return;
    await init();
    if (!_ready) return;
    try {
      await _plugin.cancelAllPendingNotifications();
      // iOS ne tiene al massimo 64: bastano le prime
      for (final p in planNotifications(mine, s, DateTime.now(), clientName: clientName).take(60)) {
        await _plugin.zonedSchedule(
          id: p.id,
          scheduledDate: tz.TZDateTime.from(p.at, tz.local),
          notificationDetails: _details(p.kind),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          title: p.content.title,
          body: p.content.body,
          payload: p.appointmentId,
        );
      }
    } catch (e) {
      debugPrint('Promemoria non programmati: $e');
    }
  }

  Future<void> cancelAll() async {
    if (!supported || !_ready) return;
    try {
      await _plugin.cancelAllPendingNotifications();
    } catch (_) {}
  }
}
