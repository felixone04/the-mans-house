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
  String notes;
  bool createdByAdmin;

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
    this.notes = '',
    this.createdByAdmin = false,
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
    notes: j['notes'] ?? '',
    createdByAdmin: j['created_by_admin'] ?? false,
  );

  bool get isUpcoming => status == AppointmentStatus.confirmed && start.isAfter(DateTime.now());
}

class Profile {
  String id;
  String email;
  String fullName;
  String phone;
  bool isAdmin;
  bool whatsappOptIn;

  Profile({
    required this.id,
    this.email = '',
    this.fullName = '',
    this.phone = '',
    this.isAdmin = false,
    this.whatsappOptIn = true,
  });

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
    id: j['id'],
    email: j['email'] ?? '',
    fullName: j['full_name'] ?? '',
    phone: j['phone'] ?? '',
    isAdmin: j['is_admin'] ?? false,
    whatsappOptIn: j['whatsapp_opt_in'] ?? true,
  );

  bool get isComplete => fullName.trim().isNotEmpty && phone.trim().isNotEmpty;

  String get firstName => fullName.trim().split(' ').first;
}

class CustomerSummary {
  final String id;
  final String email;
  final String fullName;
  final String phone;
  final int bookings;
  final DateTime? lastVisit;

  CustomerSummary({
    required this.id,
    required this.email,
    required this.fullName,
    required this.phone,
    required this.bookings,
    this.lastVisit,
  });

  factory CustomerSummary.fromJson(Map<String, dynamic> j) => CustomerSummary(
    id: j['id'],
    email: j['email'] ?? '',
    fullName: j['full_name'] ?? '',
    phone: j['phone'] ?? '',
    bookings: (j['bookings'] as num?)?.toInt() ?? 0,
    lastVisit: j['last_visit'] == null ? null : _dt(j['last_visit']),
  );
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
