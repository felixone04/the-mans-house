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
  Future<bool> signUpWithEmail({
    required String email,
    required String password,
    required String fullName,
    required String phone,
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
  Future<List<Appointment>> myAppointments();

  // --- Area riservata ---
  Future<List<Appointment>> appointmentsBetween(DateTime from, DateTime to);
  Future<void> setAppointmentStatus(String id, AppointmentStatus status);
  Future<List<CustomerSummary>> customers();
  Future<List<String>> adminEmails();
  Future<void> addAdminEmail(String email);
  Future<void> removeAdminEmail(String email);
}
