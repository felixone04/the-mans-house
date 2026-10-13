import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../models.dart';
import 'backend.dart';

class SupabaseBackend implements Backend {
  SupabaseClient get _db => Supabase.instance.client;

  @override
  bool get isDemo => false;

  @override
  Future<void> init() async {
    await Supabase.initialize(url: AppConfig.supabaseUrl, publishableKey: AppConfig.supabaseAnonKey);
  }

  @override
  Stream<void> get authChanges =>
      _db.auth.onAuthStateChange.where((s) => s.event != AuthChangeEvent.tokenRefreshed).map((_) {});

  @override
  bool get isSignedIn => _db.auth.currentUser != null;

  String? get _redirect => kIsWeb ? null : AppConfig.authRedirect;

  /// Traduce gli errori Supabase/Postgres in messaggi in italiano.
  Future<T> _guard<T>(Future<T> Function() fn) async {
    try {
      return await fn();
    } on AuthException catch (e) {
      throw AppException(_authMessage(e));
    } on PostgrestException catch (e) {
      throw AppException(e.message);
    }
  }

  String _authMessage(AuthException e) {
    final m = e.message.toLowerCase();
    if (m.contains('invalid login')) return 'Email o password non corretti';
    if (m.contains('already registered')) return 'Esiste gia\' un account con questa email';
    if (m.contains('email not confirmed')) return 'Conferma prima la tua email (controlla la posta)';
    if (m.contains('password')) return 'La password deve avere almeno 6 caratteri';
    if (m.contains('rate limit')) return 'Troppi tentativi, riprova tra qualche minuto';
    return e.message;
  }

  // --- Autenticazione ---

  @override
  Future<void> signInWithEmail(String email, String password) => _guard(() async {
    await _db.auth.signInWithPassword(email: email.trim(), password: password);
  });

  @override
  Future<bool> signUpWithEmail({
    required String email,
    required String password,
    required String fullName,
    required String phone,
  }) => _guard(() async {
    final res = await _db.auth.signUp(
      email: email.trim(),
      password: password,
      emailRedirectTo: _redirect,
      data: {'full_name': fullName.trim(), 'phone': normalizePhone(phone)},
    );
    return res.session != null;
  });

  @override
  Future<void> signInWithGoogle() => _guard(() async {
    await _db.auth.signInWithOAuth(OAuthProvider.google, redirectTo: _redirect);
  });

  @override
  Future<void> signInWithApple() => _guard(() async {
    await _db.auth.signInWithOAuth(OAuthProvider.apple, redirectTo: _redirect);
  });

  @override
  Future<void> resetPassword(String email) => _guard(() async {
    await _db.auth.resetPasswordForEmail(email.trim(), redirectTo: _redirect);
  });

  @override
  Future<void> signOut() => _guard(() => _db.auth.signOut());

  @override
  Future<void> deleteAccount() => _guard(() async {
    await _db.rpc('delete_my_account');
    await _db.auth.signOut();
  });

  @override
  Future<Profile?> fetchProfile() => _guard(() async {
    final user = _db.auth.currentUser;
    if (user == null) return null;
    final row = await _db.from('profiles').select().eq('id', user.id).maybeSingle();
    if (row == null) return Profile(id: user.id, email: user.email ?? '');
    return Profile.fromJson(row);
  });

  @override
  Future<void> updateProfile(Profile p) => _guard(() async {
    await _db
        .from('profiles')
        .update({'full_name': p.fullName.trim(), 'phone': normalizePhone(p.phone), 'whatsapp_opt_in': p.whatsappOptIn})
        .eq('id', p.id);
  });

  // --- Negozio ---

  @override
  Future<ShopSettings> fetchSettings() => _guard(() async {
    final row = await _db.from('shop_settings').select().eq('id', 1).maybeSingle();
    return row == null ? ShopSettings() : ShopSettings.fromJson(row);
  });

  @override
  Future<void> saveSettings(ShopSettings s) => _guard(() async {
    await _db.from('shop_settings').upsert({'id': 1, ...s.toJson()});
  });

  @override
  Future<List<Service>> fetchServices({bool includeInactive = false}) => _guard(() async {
    var q = _db.from('services').select();
    if (!includeInactive) q = q.eq('active', true);
    final rows = await q.order('sort_order').order('name');
    return rows.map(Service.fromJson).toList();
  });

  @override
  Future<void> saveService(Service s) => _guard(() async {
    await _db.from('services').upsert(s.toJson());
  });

  @override
  Future<void> deleteService(String id) => _guard(() async {
    await _db.from('services').delete().eq('id', id);
  });

  @override
  Future<List<Barber>> fetchBarbers({bool includeInactive = false}) => _guard(() async {
    var q = _db.from('barbers').select('*, barber_hours(*)');
    if (!includeInactive) q = q.eq('active', true);
    final rows = await q.order('sort_order').order('name');
    return rows.map(Barber.fromJson).toList();
  });

  @override
  Future<void> saveBarber(Barber b) => _guard(() async {
    final row = await _db.from('barbers').upsert(b.toJson()).select().single();
    final id = row['id'] as String;
    await _db.from('barber_hours').delete().eq('barber_id', id);
    if (b.hours.isNotEmpty) {
      await _db.from('barber_hours').insert(b.hours.map((h) => h.toJson(id)).toList());
    }
  });

  @override
  Future<void> deleteBarber(String id) => _guard(() async {
    try {
      await _db.from('barbers').delete().eq('id', id);
    } on PostgrestException catch (e) {
      if (e.code == '23503') {
        // ha appuntamenti: lo disattiviamo invece di eliminarlo
        await _db.from('barbers').update({'active': false}).eq('id', id);
        throw AppException('Il barbiere ha appuntamenti in archivio: e\' stato disattivato.');
      }
      rethrow;
    }
  });

  @override
  Future<List<TimeOff>> fetchTimeOff(String barberId) => _guard(() async {
    final rows = await _db
        .from('barber_time_off')
        .select()
        .eq('barber_id', barberId)
        .gte('end_at', DateTime.now().toUtc().toIso8601String())
        .order('start_at');
    return rows.map(TimeOff.fromJson).toList();
  });

  @override
  Future<void> addTimeOff(TimeOff t) => _guard(() async {
    await _db.from('barber_time_off').insert(t.toJson());
  });

  @override
  Future<void> deleteTimeOff(String id) => _guard(() async {
    await _db.from('barber_time_off').delete().eq('id', id);
  });

  // --- Prenotazioni ---

  @override
  Future<List<BusyInterval>> fetchBusy(DateTime from, DateTime to) => _guard(() async {
    final rows = await _db.rpc(
      'get_busy_intervals',
      params: {'p_from': from.toUtc().toIso8601String(), 'p_to': to.toUtc().toIso8601String()},
    ) as List;
    return rows.map((r) => BusyInterval.fromJson(r as Map<String, dynamic>)).toList();
  });

  @override
  Future<Appointment> book({
    required String barberId,
    required String serviceId,
    required DateTime start,
    String notes = '',
    String? customerName,
    String? customerPhone,
  }) => _guard(() async {
    final row = await _db.rpc(
      'book_appointment',
      params: {
        'p_barber': barberId,
        'p_service': serviceId,
        'p_start': start.toUtc().toIso8601String(),
        'p_notes': notes,
        'p_customer_name': customerName,
        'p_customer_phone': customerPhone == null ? null : normalizePhone(customerPhone),
      },
    ) as Map<String, dynamic>;
    return Appointment.fromJson(row);
  });

  @override
  Future<void> cancelAppointment(String id) => _guard(() async {
    await _db.rpc('cancel_appointment', params: {'p_id': id});
  });

  @override
  Future<void> rescheduleAppointment(String id, {required String barberId, required DateTime start}) =>
      _guard(() async {
        await _db.rpc(
          'reschedule_appointment',
          params: {'p_id': id, 'p_barber': barberId, 'p_start': start.toUtc().toIso8601String()},
        );
      });

  @override
  Future<List<Appointment>> myAppointments() => _guard(() async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return <Appointment>[];
    final rows = await _db
        .from('appointments')
        .select('*, barbers(name)')
        .eq('user_id', uid)
        .order('start_at', ascending: false)
        .limit(100);
    return rows.map(Appointment.fromJson).toList();
  });

  // --- Area riservata ---

  @override
  Future<List<Appointment>> appointmentsBetween(DateTime from, DateTime to) => _guard(() async {
    final rows = await _db
        .from('appointments')
        .select('*, barbers(name)')
        .gte('start_at', from.toUtc().toIso8601String())
        .lt('start_at', to.toUtc().toIso8601String())
        .order('start_at');
    return rows.map(Appointment.fromJson).toList();
  });

  @override
  Future<void> setAppointmentStatus(String id, AppointmentStatus status) => _guard(() async {
    if (status == AppointmentStatus.cancelled) {
      await cancelAppointment(id);
      return;
    }
    await _db.from('appointments').update({'status': statusToString(status)}).eq('id', id);
  });

  @override
  Future<void> updateVisit(
    String id, {
    required DateTime? arrivedAt,
    required PaymentStatus payment,
    required double amountPaid,
  }) => _guard(() async {
    await _db
        .from('appointments')
        .update({
          'arrived_at': arrivedAt?.toUtc().toIso8601String(),
          'payment_status': paymentToString(payment),
          'amount_paid': amountPaid,
        })
        .eq('id', id);
  });

  @override
  Future<List<CustomerSummary>> customers() => _guard(() async {
    final rows = await _db.rpc('admin_customers') as List;
    return rows.map((r) => CustomerSummary.fromJson(r as Map<String, dynamic>)).toList();
  });

  @override
  Future<List<Appointment>> customerAppointments(CustomerSummary c) => _guard(() async {
    var q = _db.from('appointments').select('*, barbers(name)');
    q = c.isWalkIn ? q.isFilter('user_id', null).eq('customer_name', c.fullName) : q.eq('user_id', c.id);
    final rows = await q.order('start_at', ascending: false).limit(200);
    return rows.map(Appointment.fromJson).toList();
  });

  @override
  Future<List<String>> adminEmails() => _guard(() async {
    final rows = await _db.from('admin_emails').select().order('email');
    return rows.map((r) => r['email'] as String).toList();
  });

  /// Email come pattern ILIKE letterale: "_" e "%" non devono fare da jolly
  /// (es. "mario_rossi@..." promuoveva anche "mario.rossi@...").
  String _likeLiteral(String e) => e.replaceAllMapped(RegExp(r'[\\%_]'), (m) => '\\${m[0]}');

  @override
  Future<void> addAdminEmail(String email) => _guard(() async {
    final e = email.trim().toLowerCase();
    await _db.from('admin_emails').upsert({'email': e});
    await _db.from('profiles').update({'is_admin': true}).ilike('email', _likeLiteral(e));
  });

  @override
  Future<void> removeAdminEmail(String email) => _guard(() async {
    final e = email.trim().toLowerCase();
    await _db.from('admin_emails').delete().eq('email', e);
    await _db.from('profiles').update({'is_admin': false}).ilike('email', _likeLiteral(e));
  });
}
