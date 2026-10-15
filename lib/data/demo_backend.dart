import 'dart:async';
import 'dart:math';

import '../models.dart';
import 'backend.dart';
import 'slots.dart';

/// Backend locale in memoria per provare l'app senza server.
///   - Cliente: registrati con qualsiasi email
///   - Amministratore: admin@demo.it / admin123
class DemoBackend implements Backend {
  static const adminEmail = 'admin@demo.it';
  static const adminPassword = 'admin123';

  final _auth = StreamController<void>.broadcast();
  final _rand = Random(7);
  int _seq = 0;
  String _id() => 'demo-${_seq++}';

  late ShopSettings _settings;
  final _services = <Service>[];
  final _barbers = <Barber>[];
  final _timeOff = <TimeOff>[];
  final _appointments = <Appointment>[];
  final _passwords = <String, String>{};
  final _profiles = <String, Profile>{}; // per email
  final _admins = <String>{adminEmail};
  final _shopDays = <DateTime, ShopDay>{};
  final _walkInMarketing = <String>{}; // clienti dal banco con consenso offerte
  Profile? _current;

  @override
  bool get isDemo => true;

  @override
  Stream<void> get authChanges => _auth.stream;

  @override
  bool get isSignedIn => _current != null;

  Future<T> _delay<T>(T Function() fn) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    return fn();
  }

  @override
  Future<void> init() async {
    _settings = ShopSettings(
      about:
          'Tagli classici e moderni, rasatura tradizionale con panno caldo '
          'e cura della barba. Prenota il tuo barbiere di fiducia in pochi secondi.',
      phone: '+39 0883 000000',
      whatsapp: '+39 333 0000000',
      instagram: 'themanshouse',
    );
    _services.addAll([
      Service(
        id: _id(),
        name: 'Taglio',
        description: 'Taglio su misura con rifinitura',
        durationMin: 30,
        price: 15,
        sortOrder: 1,
      ),
      Service(
        id: _id(),
        name: 'Taglio + Shampoo',
        description: 'Taglio con lavaggio e styling',
        durationMin: 40,
        price: 18,
        sortOrder: 2,
      ),
      Service(
        id: _id(),
        name: 'Barba',
        description: 'Regolazione e modellatura della barba',
        durationMin: 20,
        price: 10,
        sortOrder: 3,
      ),
      Service(
        id: _id(),
        name: 'Taglio + Barba',
        description: 'Il pacchetto completo',
        durationMin: 50,
        price: 23,
        sortOrder: 4,
      ),
      Service(
        id: _id(),
        name: 'Rasatura tradizionale',
        description: 'Rasoio a mano libera e panno caldo',
        durationMin: 30,
        price: 15,
        sortOrder: 5,
      ),
      Service(
        id: _id(),
        name: 'Taglio bambino',
        description: 'Fino a 12 anni',
        durationMin: 20,
        price: 10,
        sortOrder: 6,
      ),
    ]);

    List<WorkingHours> std() => [
      for (var d = 2; d <= 6; d++) ...[
        WorkingHours(weekday: d, start: 9 * 60, end: 13 * 60),
        WorkingHours(weekday: d, start: 15 * 60 + 30, end: 20 * 60),
      ],
    ];
    _barbers.addAll([
      Barber(id: _id(), name: 'Antonio', title: 'Master Barber', sortOrder: 1, hours: std()),
      Barber(id: _id(), name: 'Giuseppe', title: 'Barber', sortOrder: 2, hours: std()),
      Barber(
        id: _id(),
        name: 'Michele',
        title: 'Barber',
        sortOrder: 3,
        hours: [
          ...std().where((h) => h.weekday != 6),
          WorkingHours(weekday: 1, start: 15 * 60 + 30, end: 20 * 60),
          WorkingHours(weekday: 6, start: 9 * 60, end: 18 * 60),
        ],
      ),
    ]);

    _passwords[adminEmail] = adminPassword;
    _profiles[adminEmail] = Profile(
      id: _id(),
      email: adminEmail,
      fullName: 'Titolare',
      phone: '+393330000000',
      isAdmin: true,
      privacyAcceptedAt: DateTime.now(),
    );

    _seedAppointments();
    // demo: due clienti dal banco hanno dato il consenso alle offerte
    _walkInMarketing.addAll(['Marco Rossi', 'Luca Bianchi']);
  }

  void _seedAppointments() {
    const names = [
      'Marco Rossi',
      'Luca Bianchi',
      'Francesco Lops',
      'Nicola Di Bari',
      'Savino Leonetti',
      'Riccardo Sgaramella',
      'Vincenzo Zingaro',
    ];
    final today = dayOnly(DateTime.now());
    for (var i = -3; i < 10; i++) {
      final day = DateTime(today.year, today.month, today.day + i);
      for (final b in _barbers) {
        for (final h in b.hoursFor(day.weekday)) {
          for (var m = h.start; m + 30 <= h.end; m += 30) {
            if (_rand.nextDouble() > 0.4) continue;
            final s = _services[_rand.nextInt(4)];
            final start = DateTime(day.year, day.month, day.day, 0, m);
            final end = start.add(Duration(minutes: s.durationMin));
            if (end.isAfter(DateTime(day.year, day.month, day.day, 0, h.end))) continue;
            if (_appointments.any((a) => a.barberId == b.id && a.start.isBefore(end) && a.end.isAfter(start))) continue;
            _appointments.add(
              Appointment(
                id: _id(),
                barberId: b.id,
                barberName: b.name,
                serviceId: s.id,
                serviceName: s.name,
                price: s.price,
                start: start,
                end: end,
                status: start.isBefore(DateTime.now()) ? AppointmentStatus.completed : AppointmentStatus.confirmed,
                arrivedAt: start.isBefore(DateTime.now()) ? start : null,
                payment: start.isBefore(DateTime.now()) ? PaymentStatus.paid : PaymentStatus.unpaid,
                customerName: names[_rand.nextInt(names.length)],
                customerPhone: '+39 333 ${1000000 + _rand.nextInt(8999999)}',
              ),
            );
            m += s.durationMin - 30 > 0 ? 30 : 0;
          }
        }
      }
    }
  }

  // --- Autenticazione ---

  void _signIn(Profile p) {
    _current = p;
    _auth.add(null);
  }

  @override
  Future<void> signInWithEmail(String email, String password) => _delay(() {
    final e = email.trim().toLowerCase();
    if (_passwords[e] == null || _passwords[e] != password) {
      throw AppException('Email o password non corretti');
    }
    _signIn(_profiles[e]!);
  });

  @override
  Future<bool> signUpWithEmail({
    required String email,
    required String password,
    required String fullName,
    required String phone,
    bool marketingOptIn = false,
  }) => _delay(() {
    final e = email.trim().toLowerCase();
    if (_passwords.containsKey(e)) throw AppException('Esiste gia\' un account con questa email');
    if (password.length < 6) throw AppException('La password deve avere almeno 6 caratteri');
    _passwords[e] = password;
    final p = Profile(
      id: _id(),
      email: e,
      fullName: fullName.trim(),
      phone: normalizePhone(phone),
      isAdmin: _admins.contains(e),
      // come il trigger handle_new_user: la registrazione accetta l'informativa
      privacyAcceptedAt: DateTime.now(),
      marketingOptIn: marketingOptIn,
    );
    _profiles[e] = p;
    _signIn(p);
    return true;
  });

  final _guests = <String>{}; // id dei profili ospite (accesso senza account)

  @override
  bool get isGuest => _current != null && _guests.contains(_current!.id);

  @override
  Future<void> signInAsGuest({
    required String fullName,
    required String phone,
    String email = '',
    bool marketingOptIn = false,
  }) => _delay(() {
    final p = Profile(
      id: _id(),
      email: email.trim().toLowerCase(),
      fullName: fullName.trim(),
      phone: normalizePhone(phone),
      privacyAcceptedAt: DateTime.now(),
      marketingOptIn: marketingOptIn,
    );
    _guests.add(p.id);
    _profiles['ospite:${p.id}'] = p;
    _signIn(p);
  });

  @override
  Future<bool> upgradeGuest({required String email, required String password}) => _delay(() {
    final p = _current;
    if (p == null || !_guests.contains(p.id)) throw AppException('Operazione non consentita');
    final e = email.trim().toLowerCase();
    if (_passwords.containsKey(e)) throw AppException('Esiste gia\' un account con questa email');
    if (password.length < 6) throw AppException('La password deve avere almeno 6 caratteri');
    // stesso profilo (stesso id): gli appuntamenti fatti da ospite restano suoi
    _profiles.remove('ospite:${p.id}');
    p.email = e;
    _profiles[e] = p;
    _passwords[e] = password;
    _guests.remove(p.id);
    _auth.add(null);
    return true;
  });

  Future<void> _social(String email, String name) => _delay(() {
    final p = _profiles.putIfAbsent(email, () => Profile(id: _id(), email: email, fullName: name));
    _passwords.putIfAbsent(email, () => '');
    _signIn(p);
  });

  @override
  Future<void> signInWithGoogle() => _social('cliente.google@demo.it', 'Cliente Google');

  @override
  Future<void> signInWithApple() => _social('cliente.apple@demo.it', '');

  @override
  Future<void> resetPassword(String email) => _delay(() {});

  @override
  Future<void> signOut() => _delay(() {
    _current = null;
    _auth.add(null);
  });

  @override
  Future<void> deleteAccount() => _delay(() {
    final p = _current;
    if (p == null) return;
    for (final a in _appointments.where((a) => a.userId == p.id && a.isUpcoming)) {
      a.status = AppointmentStatus.cancelled;
    }
    _profiles.remove(p.email);
    _passwords.remove(p.email);
    _current = null;
    _auth.add(null);
  });

  @override
  Future<Profile?> fetchProfile() => _delay(() => _current);

  @override
  Future<void> updateProfile(Profile p) => _delay(() {
    // per id: gli ospiti non sono indicizzati per email
    final cur = _profiles.values.where((x) => x.id == p.id).firstOrNull;
    if (cur == null) return;
    cur
      ..fullName = p.fullName.trim()
      ..phone = normalizePhone(p.phone)
      ..whatsappOptIn = p.whatsappOptIn
      ..privacyAcceptedAt = p.privacyAcceptedAt
      ..marketingOptIn = p.marketingOptIn;
  });

  // --- Negozio ---

  @override
  Future<ShopSettings> fetchSettings() => _delay(() => _settings.copy());

  @override
  Future<void> saveSettings(ShopSettings s) => _delay(() => _settings = s.copy());

  @override
  Future<List<Service>> fetchServices({bool includeInactive = false}) => _delay(() {
    final list = _services.where((s) => includeInactive || s.active).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return list.map((s) => Service.fromJson({...s.toJson(), 'id': s.id})).toList();
  });

  @override
  Future<void> saveService(Service s) => _delay(() {
    if (s.id.isEmpty) {
      s.id = _id();
      _services.add(s);
    } else {
      final i = _services.indexWhere((x) => x.id == s.id);
      _services[i] = s;
    }
  });

  @override
  Future<void> deleteService(String id) => _delay(() => _services.removeWhere((s) => s.id == id));

  @override
  Future<List<Barber>> fetchBarbers({bool includeInactive = false}) => _delay(() {
    final list = _barbers.where((b) => includeInactive || b.active).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return list.map((b) => b.copy()).toList();
  });

  @override
  Future<void> saveBarber(Barber b) => _delay(() {
    if (b.id.isEmpty) {
      b.id = _id();
      _barbers.add(b.copy());
    } else {
      final i = _barbers.indexWhere((x) => x.id == b.id);
      _barbers[i] = b.copy();
    }
  });

  @override
  Future<void> deleteBarber(String id) => _delay(() {
    if (_appointments.any((a) => a.barberId == id)) {
      _barbers.firstWhere((b) => b.id == id).active = false;
      throw AppException('Il barbiere ha appuntamenti in archivio: e\' stato disattivato.');
    }
    _barbers.removeWhere((b) => b.id == id);
  });

  @override
  Future<List<ShopDay>> fetchShopDays() => _delay(() => _shopDays.values.toList()..sort((a, b) => a.day.compareTo(b.day)));

  @override
  Future<void> saveShopDays(List<ShopDay> days) => _delay(() {
    if (!(_current?.isAdmin ?? false)) throw AppException('Operazione non consentita');
    for (final d in days) {
      _shopDays[d.day] = d;
    }
    ShopCalendar.set(_shopDays.values); // come il server, vale subito per le prenotazioni
  });

  @override
  Future<void> deleteShopDay(DateTime day) => _delay(() {
    _shopDays.remove(DateTime(day.year, day.month, day.day));
    ShopCalendar.set(_shopDays.values);
  });

  @override
  Future<List<TimeOff>> fetchTimeOff(String barberId) => _delay(
    () =>
        _timeOff.where((t) => t.barberId == barberId && t.end.isAfter(DateTime.now())).toList()
          ..sort((a, b) => a.start.compareTo(b.start)),
  );

  @override
  Future<void> addTimeOff(TimeOff t) => _delay(() {
    t.id = _id();
    _timeOff.add(t);
  });

  @override
  Future<void> deleteTimeOff(String id) => _delay(() => _timeOff.removeWhere((t) => t.id == id));

  // --- Prenotazioni ---

  @override
  Future<List<BusyInterval>> fetchBusy(DateTime from, DateTime to) => _delay(
    () => [
      for (final a in _appointments)
        if (a.status == AppointmentStatus.confirmed && a.start.isBefore(to) && a.end.isAfter(from))
          BusyInterval(a.barberId, a.start, a.end),
      for (final t in _timeOff)
        if (t.start.isBefore(to) && t.end.isAfter(from)) BusyInterval(t.barberId, t.start, t.end, timeOff: true),
    ],
  );

  @override
  Future<Appointment> book({
    required String barberId,
    required String serviceId,
    required DateTime start,
    String notes = '',
    String? customerName,
    String? customerPhone,
    String? customerEmail,
    String? customerUserId,
  }) async {
    final me = _current;
    if (me == null) throw AppException('Devi accedere per prenotare');
    final service = _services.firstWhere((s) => s.id == serviceId);
    final barber = _barbers.firstWhere((b) => b.id == barberId);
    if (!me.isAdmin && start.isAfter(DateTime.now().add(Duration(days: _settings.bookingDaysAhead + 1)))) {
      throw AppException('Data troppo lontana');
    }
    final busy = await fetchBusy(dayOnly(start), dayOnly(start).add(const Duration(days: 1)));
    // passo di 1 minuto: come il server, si accetta qualsiasi orario libero dentro
    // le fasce (con il passo da 5 gli intervalli non multipli di 5 venivano rifiutati)
    final ok = availableSlots(
      barber: barber,
      durationMin: service.durationMin,
      day: start,
      busy: busy,
      stepMin: 1,
    ).contains(start);
    if (!ok) throw AppException('Orario non piu\' disponibile');
    // come book_appointment sul server: l'admin puo' prenotare per un cliente
    // con account (compare nella sua app) o per un cliente dal banco
    final forUser = me.isAdmin && customerUserId != null
        ? _profiles.values.where((p) => p.id == customerUserId).firstOrNull
        : null;
    final byAdmin = me.isAdmin && (customerName != null || forUser != null);
    final owner = forUser ?? (byAdmin ? null : me);
    final a = Appointment(
      id: _id(),
      userId: owner?.id,
      barberId: barber.id,
      barberName: barber.name,
      serviceId: service.id,
      serviceName: service.name,
      price: service.price,
      start: start,
      end: start.add(Duration(minutes: service.durationMin)),
      customerName: owner?.fullName ?? customerName!,
      customerPhone: owner?.phone ?? normalizePhone(customerPhone ?? ''),
      customerEmail: owner?.email ?? (customerEmail ?? '').trim(),
      notes: notes,
      createdByAdmin: byAdmin,
    );
    _appointments.add(a);
    return a;
  }

  @override
  Future<void> cancelAppointment(String id) => _delay(() {
    final a = _appointments.firstWhere((a) => a.id == id);
    final me = _current;
    if (me == null || (!me.isAdmin && a.userId != me.id)) {
      throw AppException('Operazione non consentita');
    }
    if (!me.isAdmin && a.start.isBefore(DateTime.now().add(Duration(hours: _settings.minCancelHours)))) {
      throw AppException('Non e\' piu\' possibile annullare: contatta il negozio');
    }
    // come cancel_appointment sul server
    if (a.status != AppointmentStatus.confirmed) {
      throw AppException('Appuntamento gia\' chiuso o annullato');
    }
    a.status = AppointmentStatus.cancelled;
  });

  @override
  Future<void> rescheduleAppointment(String id, {required String barberId, required DateTime start}) async {
    final a = _appointments.firstWhere((a) => a.id == id);
    final me = _current;
    // stesse regole di reschedule_appointment sul server
    if (me == null || (!me.isAdmin && a.userId != me.id)) {
      throw AppException('Operazione non consentita');
    }
    if (a.status != AppointmentStatus.confirmed) {
      throw AppException('Appuntamento gia\' chiuso o annullato');
    }
    if (!me.isAdmin && a.start.isBefore(DateTime.now().add(Duration(hours: _settings.minCancelHours)))) {
      throw AppException('Non e\' piu\' possibile spostarlo: contatta il negozio');
    }
    if (!me.isAdmin && start.isAfter(DateTime.now().add(Duration(days: _settings.bookingDaysAhead + 1)))) {
      throw AppException('Data troppo lontana');
    }
    final barber = _barbers.firstWhere(
      (b) => b.id == barberId && b.active,
      orElse: () => throw AppException('Barbiere non disponibile'),
    );
    final duration = a.end.difference(a.start);
    // l'appuntamento stesso non occupa l'orario in cui viene spostato
    final busy = (await fetchBusy(
      dayOnly(start),
      dayOnly(start).add(const Duration(days: 1)),
    )).where((b) => b.timeOff || b.barberId != a.barberId || b.start != a.start || b.end != a.end).toList();
    final ok = availableSlots(
      barber: barber,
      durationMin: duration.inMinutes,
      day: start,
      busy: busy,
      stepMin: 1,
    ).contains(start);
    if (!ok) throw AppException('Orario non piu\' disponibile');
    a
      ..barberId = barber.id
      ..barberName = barber.name
      ..start = start
      ..end = start.add(duration);
  }

  @override
  Future<List<Appointment>> myAppointments() => _delay(
    () =>
        _appointments.where((a) => a.userId != null && a.userId == _current?.id).toList()
          ..sort((a, b) => b.start.compareTo(a.start)),
  );

  // --- Area riservata ---

  @override
  Future<List<Appointment>> appointmentsBetween(DateTime from, DateTime to) => _delay(
    () =>
        _appointments.where((a) => !a.start.isBefore(from) && a.start.isBefore(to)).toList()
          ..sort((a, b) => a.start.compareTo(b.start)),
  );

  @override
  Future<void> setAppointmentStatus(String id, AppointmentStatus status) =>
      _delay(() => _appointments.firstWhere((a) => a.id == id).status = status);

  @override
  Future<void> updateVisit(
    String id, {
    required DateTime? arrivedAt,
    required PaymentStatus payment,
    required double amountPaid,
  }) => _delay(() {
    if (!(_current?.isAdmin ?? false)) throw AppException('Operazione non consentita');
    _appointments.firstWhere((a) => a.id == id)
      ..arrivedAt = arrivedAt
      ..payment = payment
      ..amountPaid = amountPaid;
  });

  @override
  Future<List<CustomerSummary>> customers() => _delay(() {
    final list = <CustomerSummary>[];
    for (final p in _profiles.values) {
      final mine = _appointments.where((a) => a.userId == p.id);
      final past = mine.where((a) => a.start.isBefore(DateTime.now())).map((a) => a.start).toList()..sort();
      list.add(
        CustomerSummary(
          id: p.id,
          email: p.email,
          fullName: p.fullName,
          phone: p.phone,
          bookings: mine.length,
          lastVisit: past.isEmpty ? null : past.last, // come admin_customers sul server
          marketingOptIn: p.marketingOptIn,
          privacyAcceptedAt: p.privacyAcceptedAt,
        ),
      );
    }
    // Clienti registrati al banco (senza account)
    final walkIns = <String, List<Appointment>>{};
    for (final a in _appointments.where((a) => a.userId == null)) {
      walkIns.putIfAbsent(a.customerName, () => []).add(a);
    }
    walkIns.forEach((name, list2) {
      final past = list2.where((a) => a.start.isBefore(DateTime.now())).map((a) => a.start).toList()..sort();
      list.add(
        CustomerSummary(
          id: '${CustomerSummary.walkInPrefix}$name', // come admin_customers sul server
          email: '',
          fullName: name,
          phone: list2.first.customerPhone,
          bookings: list2.length,
          lastVisit: past.isEmpty ? null : past.last,
          marketingOptIn: _walkInMarketing.contains(name),
        ),
      );
    });
    list.sort((a, b) => a.fullName.compareTo(b.fullName));
    return list;
  });

  @override
  Future<void> setWalkInConsent(String customerName, {required bool marketing}) => _delay(() {
    if (!(_current?.isAdmin ?? false)) throw AppException('Operazione non consentita');
    marketing ? _walkInMarketing.add(customerName) : _walkInMarketing.remove(customerName);
  });

  @override
  Future<List<Appointment>> customerAppointments(CustomerSummary c) => _delay(
    () =>
        _appointments
            .where((a) => c.isWalkIn ? a.userId == null && a.customerName == c.fullName : a.userId == c.id)
            .toList()
          ..sort((a, b) => b.start.compareTo(a.start)),
  );

  @override
  Future<List<String>> adminEmails() => _delay(() => _admins.toList()..sort());

  @override
  Future<void> addAdminEmail(String email) => _delay(() {
    final e = email.trim().toLowerCase();
    _admins.add(e);
    _profiles[e]?.isAdmin = true;
  });

  @override
  Future<void> removeAdminEmail(String email) => _delay(() {
    final e = email.trim().toLowerCase();
    _admins.remove(e);
    _profiles[e]?.isAdmin = false;
  });
}
