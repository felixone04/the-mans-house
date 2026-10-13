import '../models.dart';

/// Errore leggibile dall'utente.
class AppException implements Exception {
  final String message;
  AppException(this.message);
  @override
  String toString() => message;
}

/// Accesso ai dati. Implementato da [SupabaseBackend] (produzione)
/// e [DemoBackend] (dati locali per prove senza server).
abstract class Backend {
  bool get isDemo;

  Future<void> init();

  /// Notifica login / logout.
  Stream<void> get authChanges;
  bool get isSignedIn;

  // --- Autenticazione ---
  Future<void> signInWithEmail(String email, String password);

  /// Ritorna false se serve confermare l'email prima di accedere.
  /// La registrazione implica l'accettazione dell'informativa privacy;
  /// [marketingOptIn] e' il consenso facoltativo a offerte e novita'.
  Future<bool> signUpWithEmail({
    required String email,
    required String password,
    required String fullName,
    required String phone,
    bool marketingOptIn = false,
  });
  Future<void> signInWithGoogle();
  Future<void> signInWithApple();
  Future<void> resetPassword(String email);
  Future<void> signOut();
  Future<void> deleteAccount();

  Future<Profile?> fetchProfile();
  Future<void> updateProfile(Profile profile);

  // --- Dati del negozio ---
  Future<ShopSettings> fetchSettings();
  Future<void> saveSettings(ShopSettings settings);

  Future<List<Service>> fetchServices({bool includeInactive = false});
  Future<void> saveService(Service service);
  Future<void> deleteService(String id);

  Future<List<Barber>> fetchBarbers({bool includeInactive = false});
  Future<void> saveBarber(Barber barber);
  Future<void> deleteBarber(String id);

  /// Chiusure e orari speciali del negozio (dati pubblici).
  Future<List<ShopDay>> fetchShopDays();
  Future<void> saveShopDays(List<ShopDay> days);
  Future<void> deleteShopDay(DateTime day);

  Future<List<TimeOff>> fetchTimeOff(String barberId);
  Future<void> addTimeOff(TimeOff timeOff);
  Future<void> deleteTimeOff(String id);

  // --- Prenotazioni ---
  Future<List<BusyInterval>> fetchBusy(DateTime from, DateTime to);
  Future<Appointment> book({
    required String barberId,
    required String serviceId,
    required DateTime start,
    String notes = '',
    String? customerName,
    String? customerPhone,
  });
  Future<void> cancelAppointment(String id);

  /// Sposta un appuntamento confermato (stessa durata) su un altro orario
  /// e/o barbiere. Il cliente puo' farlo entro lo stesso limite dell'annullamento.
  Future<void> rescheduleAppointment(String id, {required String barberId, required DateTime start});
  Future<List<Appointment>> myAppointments();

  // --- Area riservata ---
  Future<List<Appointment>> appointmentsBetween(DateTime from, DateTime to);
  Future<void> setAppointmentStatus(String id, AppointmentStatus status);

  /// Arrivo del cliente e pagamento (pagato, paga dopo, acconto).
  Future<void> updateVisit(
    String id, {
    required DateTime? arrivedAt,
    required PaymentStatus payment,
    required double amountPaid,
  });
  Future<List<CustomerSummary>> customers();

  /// Tutti gli appuntamenti di un cliente (scheda cliente), dal piu' recente.
  Future<List<Appointment>> customerAppointments(CustomerSummary customer);

  /// Consensi di un cliente dal banco (dati a voce in negozio).
  Future<void> setWalkInConsent(String customerName, {required bool marketing});
  Future<List<String>> adminEmails();
  Future<void> addAdminEmail(String email);
  Future<void> removeAdminEmail(String email);
}
