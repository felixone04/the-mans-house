import 'dart:async';

import 'package:flutter/widgets.dart';

import '../data/backend.dart';
import '../data/phone_notifier.dart';
import '../models.dart';

/// Stato globale: profilo utente, impostazioni, servizi e barbieri.
class AppState extends ChangeNotifier {
  AppState(this.backend) {
    _sub = backend.authChanges.listen((_) => refreshProfile());
  }

  final Backend backend;
  late final StreamSubscription<void> _sub;

  Profile? profile;
  ShopSettings settings = ShopSettings();
  List<Service> services = [];
  List<Barber> barbers = [];
  List<Appointment> myAppointments = [];

  /// Appuntamenti spostati o annullati da chi usa l'app in questa sessione:
  /// per questi non si mostra l'avviso «spostato/annullato».
  final ownChanges = <String>{};

  bool get isSignedIn => backend.isSignedIn;
  bool get isAdmin => profile?.isAdmin ?? false;

  /// Collegato da ospite (prenotazione senza account).
  bool get isGuest => isSignedIn && backend.isGuest;
  bool get needsProfile => isSignedIn && !(profile?.isComplete ?? false);

  Appointment? get nextAppointment {
    final up = myAppointments.where((a) => a.isUpcoming).toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    return up.isEmpty ? null : up.first;
  }

  /// Chiusure e orari speciali del negozio (anche in [ShopCalendar]).
  List<ShopDay> shopDays = [];

  Future<void> load() async {
    final results = await Future.wait([
      backend.fetchSettings(),
      backend.fetchServices(),
      backend.fetchBarbers(),
      backend.fetchShopDays(),
    ]);
    settings = results[0] as ShopSettings;
    services = results[1] as List<Service>;
    barbers = results[2] as List<Barber>;
    _setShopDays(results[3] as List<ShopDay>);
    await refreshProfile();
  }

  Future<void> refreshCatalog() async {
    services = await backend.fetchServices();
    barbers = await backend.fetchBarbers();
    settings = await backend.fetchSettings();
    _setShopDays(await backend.fetchShopDays());
    notifyListeners();
  }

  Future<void> refreshShopDays() async {
    _setShopDays(await backend.fetchShopDays());
    notifyListeners();
  }

  void _setShopDays(List<ShopDay> days) {
    shopDays = days;
    ShopCalendar.set(days);
  }

  Future<void> refreshProfile() async {
    try {
      profile = backend.isSignedIn ? await backend.fetchProfile() : null;
      myAppointments = backend.isSignedIn ? await backend.myAppointments() : [];
    } catch (_) {
      // la rete puo' non essere disponibile: manteniamo lo stato precedente
    }
    notifyListeners();
    _syncPhone();
  }

  Future<void> refreshAppointments() async {
    myAppointments = backend.isSignedIn ? await backend.myAppointments() : [];
    notifyListeners();
    _syncPhone();
  }

  /// Promemoria, conferma presenza e voto programmati sul telefono del cliente.
  void _syncPhone() {
    if (!backend.isSignedIn || isAdmin) {
      PhoneNotifier.instance.cancelAll();
      return;
    }
    PhoneNotifier.instance.reschedule(myAppointments, settings, clientName: profile?.fullName ?? '');
  }

  Future<void> signOut() async {
    await backend.signOut();
    profile = null;
    myAppointments = [];
    ownChanges.clear();
    PhoneNotifier.instance.cancelAll();
    notifyListeners();
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

/// Rende [AppState] accessibile ai widget: `AppScope.of(context)`.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
      : super(notifier: state);

  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  /// Accesso senza registrare dipendenze (per callback).
  static AppState read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
