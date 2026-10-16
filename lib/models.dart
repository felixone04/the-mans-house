// Modelli dati dell'app.

DateTime _dt(dynamic v) => DateTime.parse(v as String).toLocal();
double _num(dynamic v) => v == null ? 0 : (v as num).toDouble();

/// Minuti dalla mezzanotte <-> "HH:mm:ss"
int parseTime(String s) {
  final p = s.split(':');
  return int.parse(p[0]) * 60 + int.parse(p[1]);
}

String formatTime(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

class ShopSettings {
  String name;
  String tagline;
  String about;
  String address;
  String mapsUrl;
  String phone;
  String whatsapp;
  String instagram;
  int slotStepMin;
  int bookingDaysAhead;
  int minCancelHours;
  bool remindersEnabled;

  ShopSettings({
    this.name = "The Man's House",
    this.tagline = 'Barber Shop · Andria',
    this.about = '',
    this.address = 'Via Garibaldi 91, Andria',
    this.mapsUrl = 'https://maps.google.com/?q=Via+Garibaldi+91+Andria',
    this.phone = '',
    this.whatsapp = '',
    this.instagram = '',
    this.slotStepMin = 15,
    this.bookingDaysAhead = 30,
    this.minCancelHours = 2,
    this.remindersEnabled = true,
  });

  factory ShopSettings.fromJson(Map<String, dynamic> j) => ShopSettings(
    name: j['name'] ?? '',
    tagline: j['tagline'] ?? '',
    about: j['about'] ?? '',
    address: j['address'] ?? '',
    mapsUrl: j['maps_url'] ?? '',
    phone: j['phone'] ?? '',
    whatsapp: j['whatsapp'] ?? '',
    instagram: j['instagram'] ?? '',
    slotStepMin: j['slot_step_min'] ?? 15,
    bookingDaysAhead: j['booking_days_ahead'] ?? 30,
    minCancelHours: j['min_cancel_hours'] ?? 2,
    remindersEnabled: j['reminders_enabled'] ?? true,
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'tagline': tagline,
    'about': about,
    'address': address,
    'maps_url': mapsUrl,
    'phone': phone,
    'whatsapp': whatsapp,
    'instagram': instagram,
    'slot_step_min': slotStepMin,
    'booking_days_ahead': bookingDaysAhead,
    'min_cancel_hours': minCancelHours,
    'reminders_enabled': remindersEnabled,
  };

  ShopSettings copy() => ShopSettings.fromJson(toJson());
}

class Service {
  String id;
  String name;
  String description;
  int durationMin;
  double price;
  bool active;
  int sortOrder;

  Service({
    this.id = '',
    required this.name,
    this.description = '',
    required this.durationMin,
    required this.price,
    this.active = true,
    this.sortOrder = 0,
  });

  factory Service.fromJson(Map<String, dynamic> j) => Service(
    id: j['id'],
    name: j['name'],
    description: j['description'] ?? '',
    durationMin: j['duration_min'],
    price: _num(j['price']),
    active: j['active'] ?? true,
    sortOrder: j['sort_order'] ?? 0,
  );

  Map<String, dynamic> toJson() => {
    if (id.isNotEmpty) 'id': id,
    'name': name,
    'description': description,
    'duration_min': durationMin,
    'price': price,
    'active': active,
    'sort_order': sortOrder,
  };
}

class WorkingHours {
  int weekday; // 1 = lunedi' ... 7 = domenica
  int start; // minuti dalla mezzanotte
  int end;

  WorkingHours({required this.weekday, required this.start, required this.end});

  factory WorkingHours.fromJson(Map<String, dynamic> j) =>
      WorkingHours(weekday: j['weekday'], start: parseTime(j['start_time']), end: parseTime(j['end_time']));

  Map<String, dynamic> toJson(String barberId) => {
    'barber_id': barberId,
    'weekday': weekday,
    'start_time': formatTime(start),
    'end_time': formatTime(end),
  };

  WorkingHours copy() => WorkingHours(weekday: weekday, start: start, end: end);
}

class Barber {
  String id;
  String name;
  String title;
  String? photoUrl;
  bool active;
  int sortOrder;
  List<WorkingHours> hours;

  Barber({
    this.id = '',
    required this.name,
    this.title = 'Barbiere',
    this.photoUrl,
    this.active = true,
    this.sortOrder = 0,
    List<WorkingHours>? hours,
  }) : hours = hours ?? [];

  factory Barber.fromJson(Map<String, dynamic> j) => Barber(
    id: j['id'],
    name: j['name'],
    title: j['title'] ?? '',
    photoUrl: j['photo_url'],
    active: j['active'] ?? true,
    sortOrder: j['sort_order'] ?? 0,
    hours: ((j['barber_hours'] as List?) ?? []).map((h) => WorkingHours.fromJson(h)).toList(),
  );

  Map<String, dynamic> toJson() => {
    if (id.isNotEmpty) 'id': id,
    'name': name,
    'title': title,
    'photo_url': photoUrl,
    'active': active,
    'sort_order': sortOrder,
  };

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  List<WorkingHours> hoursFor(int weekday) =>
      hours.where((h) => h.weekday == weekday).toList()..sort((a, b) => a.start.compareTo(b.start));

  /// Orari effettivi di un giorno preciso: quelli settimanali, salvo chiusure
  /// e orari speciali del negozio ([ShopCalendar]).
  List<WorkingHours> hoursOn(DateTime day) {
    final s = ShopCalendar.forDay(day);
    if (s == null) return hoursFor(day.weekday);
    if (s.closed || !s.appliesTo(id)) return const [];
    return [WorkingHours(weekday: day.weekday, start: s.open!, end: s.close!)];
  }

  Barber copy() => Barber(
    id: id,
    name: name,
    title: title,
    photoUrl: photoUrl,
    active: active,
    sortOrder: sortOrder,
    hours: hours.map((h) => h.copy()).toList(),
  );
}

/// Giorno speciale per tutto il negozio: chiusura (orari nulli) oppure
/// orario diverso dal solito, eventualmente solo per alcuni barbieri.
class ShopDay {
  DateTime day;
  int? open; // minuti dalla mezzanotte; null = chiuso
  int? close;
  String note;

  /// Barbieri al lavoro nell'orario speciale; vuoto = tutti.
  List<String> barberIds;

  ShopDay({required DateTime day, this.open, this.close, this.note = '', List<String>? barberIds})
    : day = DateTime(day.year, day.month, day.day),
      barberIds = barberIds ?? [];

  bool get closed => open == null || close == null;

  bool appliesTo(String barberId) => barberIds.isEmpty || barberIds.contains(barberId);

  factory ShopDay.fromJson(Map<String, dynamic> j) => ShopDay(
    day: DateTime.parse(j['day'] as String),
    open: j['open_time'] == null ? null : parseTime(j['open_time']),
    close: j['close_time'] == null ? null : parseTime(j['close_time']),
    note: j['note'] ?? '',
    barberIds: ((j['barber_ids'] as List?) ?? []).cast<String>(),
  );

  Map<String, dynamic> toJson() => {
    'day':
        '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}',
    'open_time': open == null ? null : formatTime(open!),
    'close_time': close == null ? null : formatTime(close!),
    'note': note,
    'barber_ids': barberIds.isEmpty ? null : barberIds,
  };
}

/// Calendario dei giorni speciali in uso (caricato da AppState e dal backend
/// demo): lo leggono il calcolo degli orari liberi e l'agenda.
class ShopCalendar {
  static final _days = <DateTime, ShopDay>{};

  static void set(Iterable<ShopDay> days) {
    _days
      ..clear()
      ..addEntries(days.map((d) => MapEntry(d.day, d)));
  }

  static ShopDay? forDay(DateTime d) => _days[DateTime(d.year, d.month, d.day)];

  static List<ShopDay> get all => _days.values.toList()..sort((a, b) => a.day.compareTo(b.day));
}

class TimeOff {
  String id;
  String barberId;
  DateTime start;
  DateTime end;
  String reason;

  TimeOff({this.id = '', required this.barberId, required this.start, required this.end, this.reason = ''});

  factory TimeOff.fromJson(Map<String, dynamic> j) => TimeOff(
    id: j['id'],
    barberId: j['barber_id'],
    start: _dt(j['start_at']),
    end: _dt(j['end_at']),
    reason: j['reason'] ?? '',
  );

  Map<String, dynamic> toJson() => {
    'barber_id': barberId,
    'start_at': start.toUtc().toIso8601String(),
    'end_at': end.toUtc().toIso8601String(),
    'reason': reason,
  };
}

class BusyInterval {
  final String barberId;
  final DateTime start;
  final DateTime end;

  /// Ferie/permesso (non e' lavoro: non conta nel carico del "primo disponibile").
  final bool timeOff;
  BusyInterval(this.barberId, this.start, this.end, {this.timeOff = false});

  factory BusyInterval.fromJson(Map<String, dynamic> j) =>
      BusyInterval(j['barber_id'], _dt(j['start_at']), _dt(j['end_at']), timeOff: j['is_time_off'] == true);
}

enum AppointmentStatus { confirmed, cancelled, completed, noShow }

AppointmentStatus statusFromString(String s) => switch (s) {
  'cancelled' => AppointmentStatus.cancelled,
  'completed' => AppointmentStatus.completed,
  'no_show' => AppointmentStatus.noShow,
  _ => AppointmentStatus.confirmed,
};

String statusToString(AppointmentStatus s) => switch (s) {
  AppointmentStatus.cancelled => 'cancelled',
  AppointmentStatus.completed => 'completed',
  AppointmentStatus.noShow => 'no_show',
  AppointmentStatus.confirmed => 'confirmed',
};

String statusLabel(AppointmentStatus s) => switch (s) {
  AppointmentStatus.cancelled => 'Annullato',
  AppointmentStatus.completed => 'Completato',
  AppointmentStatus.noShow => 'Non presentato',
  AppointmentStatus.confirmed => 'Confermato',
};

/// Prodotto in vendita nel negozio (visibile ai clienti, senza giacenza).
class Product {
  String id;
  String name;
  String brand;
  String category; // es. Styling, Barba, Cura
  String format; // es. "100 ml"
  double price;
  String description;
  String howToUse;
  String hairType; // per quali capelli / barba
  int hold; // fissaggio 0-5 (0 = non indicato)
  int shine; // lucentezza 0-5
  List<String> photos; // indirizzi delle foto (risultati sui capelli)
  bool active;
  int sortOrder;

  Product({
    this.id = '',
    required this.name,
    this.brand = '',
    this.category = '',
    this.format = '',
    required this.price,
    this.description = '',
    this.howToUse = '',
    this.hairType = '',
    this.hold = 0,
    this.shine = 0,
    List<String>? photos,
    this.active = true,
    this.sortOrder = 0,
  }) : photos = photos ?? [];

  factory Product.fromJson(Map<String, dynamic> j) => Product(
    id: j['id'],
    name: j['name'] ?? '',
    brand: j['brand'] ?? '',
    category: j['category'] ?? '',
    format: j['format'] ?? '',
    price: _num(j['price']),
    description: j['description'] ?? '',
    howToUse: j['how_to_use'] ?? '',
    hairType: j['hair_type'] ?? '',
    hold: (j['hold'] as num?)?.toInt() ?? 0,
    shine: (j['shine'] as num?)?.toInt() ?? 0,
    photos: ((j['photos'] as List?) ?? []).cast<String>(),
    active: j['active'] ?? true,
    sortOrder: (j['sort_order'] as num?)?.toInt() ?? 0,
  );

  Map<String, dynamic> toJson() => {
    if (id.isNotEmpty) 'id': id,
    'name': name,
    'brand': brand,
    'category': category,
    'format': format,
    'price': price,
    'description': description,
    'how_to_use': howToUse,
    'hair_type': hairType,
    'hold': hold,
    'shine': shine,
    'photos': photos,
    'active': active,
    'sort_order': sortOrder,
  };

  Product copy() => Product.fromJson({...toJson(), 'id': id});
}

/// Giacenza di un prodotto (solo area riservata) con soglia di sottoscorta.
class ProductStock {
  ProductStock({required this.productId, this.stock = 0, this.threshold = 0});
  final String productId;
  int stock;
  int threshold;

  /// Da riordinare: giacenza pari o sotto la soglia (o esaurito).
  bool get low => stock <= 0 || stock <= threshold;

  factory ProductStock.fromJson(Map<String, dynamic> j) => ProductStock(
    productId: j['product_id'],
    stock: (j['stock'] as num?)?.toInt() ?? 0,
    threshold: (j['threshold'] as num?)?.toInt() ?? 0,
  );
}

/// Prodotto venduto (anche insieme a un appuntamento).
class ProductSale {
  ProductSale({
    required this.id,
    required this.productId,
    required this.productName,
    required this.qty,
    required this.unitPrice,
    this.appointmentId,
    required this.at,
  });
  final String id;
  final String productId;
  final String productName;
  final int qty;
  final double unitPrice;
  final String? appointmentId;
  final DateTime at;

  double get total => unitPrice * qty;

  factory ProductSale.fromJson(Map<String, dynamic> j) => ProductSale(
    id: j['id'],
    productId: j['product_id'],
    productName: (j['products'] as Map?)?['name'] ?? '',
    qty: -((j['qty'] as num?)?.toInt() ?? 0), // nei movimenti la vendita e' negativa
    unitPrice: _num(j['unit_price']),
    appointmentId: j['appointment_id'],
    at: _dt(j['created_at']),
  );
}

/// Pagamento di un appuntamento (segnato dal negozio).
enum PaymentStatus { unpaid, paid, later, deposit }

PaymentStatus paymentFromString(String? s) => switch (s) {
  'paid' => PaymentStatus.paid,
  'later' => PaymentStatus.later,
  'deposit' => PaymentStatus.deposit,
  _ => PaymentStatus.unpaid,
};

String paymentToString(PaymentStatus p) => switch (p) {
  PaymentStatus.paid => 'paid',
  PaymentStatus.later => 'later',
  PaymentStatus.deposit => 'deposit',
  PaymentStatus.unpaid => 'unpaid',
};

class Appointment {
  String id;
  String? userId;
  String barberId;
  String barberName;
  String? serviceId;
  String serviceName;
  double price;
  DateTime start;
  DateTime end;
  AppointmentStatus status;
  String customerName;
  String customerPhone;

  /// Email facoltativa (ospiti e clienti inseriti dal titolare).
  String customerEmail;
  String notes;
  bool createdByAdmin;

  /// Ora di arrivo del cliente in negozio (null = non ancora arrivato).
  DateTime? arrivedAt;
  PaymentStatus payment;

  /// Importo gia' pagato (acconto); per [PaymentStatus.paid] vale il totale.
  double amountPaid;

  /// Prodotti venduti insieme all'appuntamento (si sommano al totale da pagare).
  double productsTotal;

  /// Extra: accettato dalla lista d'attesa anche se l'orario era pieno.
  bool extra;

  Appointment({
    required this.id,
    this.userId,
    required this.barberId,
    this.barberName = '',
    this.serviceId,
    required this.serviceName,
    required this.price,
    required this.start,
    required this.end,
    this.status = AppointmentStatus.confirmed,
    this.customerName = '',
    this.customerPhone = '',
    this.customerEmail = '',
    this.notes = '',
    this.createdByAdmin = false,
    this.arrivedAt,
    this.payment = PaymentStatus.unpaid,
    this.amountPaid = 0,
    this.productsTotal = 0,
    this.extra = false,
  });

  factory Appointment.fromJson(Map<String, dynamic> j) => Appointment(
    id: j['id'],
    userId: j['user_id'],
    barberId: j['barber_id'],
    barberName: (j['barbers'] as Map?)?['name'] ?? '',
    serviceId: j['service_id'],
    serviceName: j['service_name'] ?? '',
    price: _num(j['price']),
    start: _dt(j['start_at']),
    end: _dt(j['end_at']),
    status: statusFromString(j['status'] ?? 'confirmed'),
    customerName: j['customer_name'] ?? '',
    customerPhone: j['customer_phone'] ?? '',
    customerEmail: j['customer_email'] ?? '',
    notes: j['notes'] ?? '',
    createdByAdmin: j['created_by_admin'] ?? false,
    arrivedAt: j['arrived_at'] == null ? null : _dt(j['arrived_at']),
    payment: paymentFromString(j['payment_status']),
    amountPaid: _num(j['amount_paid']),
    productsTotal: _num(j['products_total']),
    extra: j['overbooked'] ?? false,
  );

  bool get isUpcoming => status == AppointmentStatus.confirmed && start.isAfter(DateTime.now());

  /// Totale da pagare: servizio + prodotti venduti con l'appuntamento.
  double get total => price + productsTotal;

  /// Incassato finora.
  double get collected => switch (payment) {
    PaymentStatus.paid => total,
    PaymentStatus.deposit => amountPaid.clamp(0, total).toDouble(),
    _ => 0,
  };

  /// Ancora da incassare per un servizio svolto (o con pagamento rimandato).
  double get outstanding =>
      status == AppointmentStatus.completed || payment == PaymentStatus.later || payment == PaymentStatus.deposit
      ? total - collected
      : 0;
}

enum WaitlistStatus { waiting, assigned, accepted, cancelled }

/// Richiesta in lista d'attesa per un orario occupato. Se l'orario si libera
/// il posto va in automatico al primo in lista ([WaitlistStatus.assigned]);
/// l'admin puo' anche accettarla comunque ([WaitlistStatus.accepted]).
class WaitlistEntry {
  WaitlistEntry({
    required this.id,
    this.userId = '',
    this.customerName = '',
    this.customerPhone = '',
    this.serviceId,
    required this.serviceName,
    required this.durationMin,
    this.price = 0,
    this.barberId,
    this.barberName = '',
    required this.start,
    this.status = WaitlistStatus.waiting,
    this.appointmentId,
    required this.createdAt,
    this.position,
  });

  final String id;
  final String userId;
  final String customerName;
  final String customerPhone;
  final String? serviceId;
  final String serviceName;
  final int durationMin;
  final double price;

  /// null = primo barbiere disponibile.
  final String? barberId;
  final String barberName;
  final DateTime start;
  WaitlistStatus status;
  String? appointmentId;
  final DateTime createdAt;

  /// Posizione in lista (1 = il prossimo), solo per le richieste in attesa.
  final int? position;

  DateTime get end => start.add(Duration(minutes: durationMin));

  /// Vale per un posto di [barberId] (null: per qualunque barbiere)?
  bool fits(String? barberId) => this.barberId == null || barberId == null || this.barberId == barberId;

  static WaitlistStatus statusFrom(String? s) => switch (s) {
    'assigned' => WaitlistStatus.assigned,
    'accepted' => WaitlistStatus.accepted,
    'cancelled' => WaitlistStatus.cancelled,
    _ => WaitlistStatus.waiting,
  };

  factory WaitlistEntry.fromJson(Map<String, dynamic> j) => WaitlistEntry(
    id: j['id'],
    userId: j['user_id'] ?? '',
    customerName: j['customer_name'] ?? '',
    customerPhone: j['customer_phone'] ?? '',
    serviceId: j['service_id'],
    serviceName: j['service_name'] ?? '',
    durationMin: (j['duration_min'] as num?)?.toInt() ?? 30,
    price: _num(j['price']),
    barberId: j['barber_id'],
    barberName: j['barber_name'] ?? (j['barbers'] as Map?)?['name'] ?? '',
    start: _dt(j['start_at']),
    status: statusFrom(j['status']),
    appointmentId: j['appointment_id'],
    createdAt: _dt(j['created_at']),
    position: (j['position'] as num?)?.toInt(),
  );
}

/// Quanti sono in lista per ogni orario (senza nomi: e' cio' che vede il cliente).
class WaitlistCount {
  WaitlistCount(this.start, this.barberId, this.waiting);
  final DateTime start;
  final String? barberId;
  final int waiting;
}

/// Persone in lista per l'orario [start] di [barberId] (null = qualunque barbiere).
int waitingFor(List<WaitlistCount> counts, DateTime start, String? barberId) => counts
    .where((c) => c.start == start && (c.barberId == null || barberId == null || c.barberId == barberId))
    .fold(0, (n, c) => n + c.waiting);

class Profile {
  String id;
  String email;
  String fullName;
  String phone;
  bool isAdmin;
  bool whatsappOptIn;

  /// Quando ha accettato l'informativa privacy (null = mai).
  DateTime? privacyAcceptedAt;

  /// Consenso a ricevere offerte e novita' (marketing).
  bool marketingOptIn;

  Profile({
    required this.id,
    this.email = '',
    this.fullName = '',
    this.phone = '',
    this.isAdmin = false,
    this.whatsappOptIn = true,
    this.privacyAcceptedAt,
    this.marketingOptIn = false,
  });

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
    id: j['id'],
    email: j['email'] ?? '',
    fullName: j['full_name'] ?? '',
    phone: j['phone'] ?? '',
    isAdmin: j['is_admin'] ?? false,
    whatsappOptIn: j['whatsapp_opt_in'] ?? true,
    privacyAcceptedAt: j['privacy_accepted_at'] == null ? null : _dt(j['privacy_accepted_at']),
    marketingOptIn: j['marketing_opt_in'] ?? false,
  );

  /// Profilo utilizzabile: nome, cellulare e informativa privacy accettata.
  bool get isComplete => fullName.trim().isNotEmpty && phone.trim().isNotEmpty && privacyAcceptedAt != null;

  String get firstName => fullName.trim().split(' ').first;
}

class CustomerSummary {
  final String id;
  final String email;
  final String fullName;
  final String phone;
  final int bookings;
  final DateTime? lastVisit;

  /// Consenso a ricevere offerte (dal profilo o, per i clienti dal banco,
  /// segnato in negozio) e data di accettazione dell'informativa privacy.
  final bool marketingOptIn;
  final DateTime? privacyAcceptedAt;

  CustomerSummary({
    required this.id,
    required this.email,
    required this.fullName,
    required this.phone,
    required this.bookings,
    this.lastVisit,
    this.marketingOptIn = false,
    this.privacyAcceptedAt,
  });

  factory CustomerSummary.fromJson(Map<String, dynamic> j) => CustomerSummary(
    id: j['id'],
    email: j['email'] ?? '',
    fullName: j['full_name'] ?? '',
    phone: j['phone'] ?? '',
    bookings: (j['bookings'] as num?)?.toInt() ?? 0,
    lastVisit: j['last_visit'] == null ? null : _dt(j['last_visit']),
    marketingOptIn: j['marketing_opt_in'] ?? false,
    privacyAcceptedAt: j['privacy_accepted_at'] == null ? null : _dt(j['privacy_accepted_at']),
  );

  /// Cliente inserito dal banco (senza account): id "banco:" seguito dal nome.
  bool get isWalkIn => id.startsWith(walkInPrefix);

  static const walkInPrefix = 'banco:';
}

/// Normalizza un numero italiano in formato internazionale (+39...).
String normalizePhone(String raw) {
  var p = raw.replaceAll(RegExp(r'[\s\-().]'), '');
  if (p.isEmpty) return '';
  if (p.startsWith('00')) p = '+${p.substring(2)}';
  if (!p.startsWith('+')) p = '+39$p';
  return p;
}

bool isValidPhone(String raw) => RegExp(r'^\+\d{8,15}$').hasMatch(normalizePhone(raw));
