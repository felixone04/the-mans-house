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
  /// Accesso da ospite (senza account): si prenota con nome, cognome,
  /// cellulare ed email facoltativa. L'ospite puo' poi creare l'account
  /// con [upgradeGuest] mantenendo i suoi appuntamenti.
  Future<void> signInAsGuest({
    required String fullName,
    required String phone,
    String email = '',
    bool marketingOptIn = false,
  });

  /// L'utente collegato e' un ospite (accesso senza account)?
  bool get isGuest;

  /// Trasforma l'ospite in account con email e password. Ritorna false se
  /// serve prima confermare l'email (link inviato).
  Future<bool> upgradeGuest({required String email, required String password});

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

  // --- Prodotti e magazzino ---
  /// Prodotti in vendita (i clienti vedono solo quelli attivi, senza giacenza).
  Future<List<Product>> fetchProducts({bool includeInactive = false});
  Future<void> saveProduct(Product product);
  Future<void> deleteProduct(String id);

  /// Carica una foto del prodotto e ne restituisce l'indirizzo.
  Future<String> uploadProductPhoto(List<int> bytes, String extension);

  /// Solo area riservata: giacenza e soglia di sottoscorta per prodotto.
  Future<Map<String, ProductStock>> fetchStock();
  Future<void> setStockThreshold(String productId, int threshold);

  /// Carico (positivo) o rettifica della giacenza.
  Future<void> adjustStock(String productId, int delta, {String note = ''});

  /// Vendita: scala la giacenza e, se legata a un appuntamento, ne aumenta
  /// il totale da pagare.
  Future<void> sellProduct(String productId, int qty, {String? appointmentId});

  /// Annulla una vendita (la giacenza torna come prima).
  Future<void> cancelSale(String saleId);

  /// Prodotti venduti con un appuntamento.
  Future<List<ProductSale>> appointmentSales(String appointmentId);

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
    String? customerEmail,

    /// Solo admin: prenota per un cliente con account (compare nella sua app).
    String? customerUserId,
  });
  Future<void> cancelAppointment(String id);

  /// Sposta un appuntamento confermato (stessa durata) su un altro orario
  /// e/o barbiere. Il cliente puo' farlo entro lo stesso limite dell'annullamento.
  Future<void> rescheduleAppointment(String id, {required String barberId, required DateTime start});
  Future<List<Appointment>> myAppointments();

  /// Il cliente conferma che ci sara' (conferma presenza del giorno prima).
  Future<void> confirmAttendance(String appointmentId);

  /// Voto dopo il taglio (1-5) con commento facoltativo, visibile solo al negozio.
  Future<void> submitReview(String appointmentId, int stars, {String comment = ''});

  /// Solo area riservata: appuntamenti con un voto, dal piu' recente.
  Future<List<Appointment>> fetchReviews();

  // --- Lista d'attesa ---
  /// Mette il cliente in lista per un orario occupato ([barberId] null =
  /// primo disponibile). Se si libera, il posto gli viene assegnato da solo.
  Future<WaitlistEntry> joinWaitlist({required String serviceId, String? barberId, required DateTime start});

  /// Esce dalla lista (il cliente le sue richieste, l'admin tutte).
  Future<void> leaveWaitlist(String id);

  /// Richieste del cliente collegato, con la posizione in lista.
  Future<List<WaitlistEntry>> myWaitlist();

  /// Quante persone sono in lista per ogni orario: solo numeri, nessun nome.
  Future<List<WaitlistCount>> waitlistCounts(DateTime from, DateTime to);

  /// Solo area riservata: chi e' in lista (in attesa) tra [from] e [to].
  Future<List<WaitlistEntry>> fetchWaitlist(DateTime from, DateTime to);

  /// Solo area riservata: accetta comunque la richiesta anche se si e' pieni.
  /// L'appuntamento va al barbiere scelto dal cliente o a uno a caso tra chi
  /// lavora a quell'ora, segnato come extra.
  Future<Appointment> acceptWaitlist(String id);

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
