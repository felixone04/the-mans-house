import 'package:flutter/material.dart';

/// Tipi di notifica. Ognuno si attiva, si disattiva e si modifica dall'area
/// riservata (Opzioni -> Notifiche); i testi usano segnaposto come {ora}.
enum NotifKind {
  bookingConfirmed,
  reminderDay,
  reminderHour,
  attendanceCheck,
  waitlistAssigned,
  moved,
  cancelled,
  shopNotice,
  review,
  news,
  newBooking,
  bookingCancelled,
  waitlistShop,
  lowStock,
}

/// Quando arriva una notifica programmata (promemoria, conferma presenza, recensione).
enum NotifTiming {
  /// minuti prima dell'appuntamento
  before,

  /// il giorno prima, all'ora indicata (minuti dalla mezzanotte)
  dayBeforeAt,

  /// minuti dopo la fine dell'appuntamento
  afterEnd,
}

/// Descrizione di un tipo di notifica, con i testi di partenza (stile essenziale:
/// icona tonda nel colore del tipo).
class NotifType {
  const NotifType({
    required this.kind,
    required this.label,
    required this.description,
    required this.icon,
    required this.bg,
    required this.fg,
    required this.title,
    required this.body,
    required this.placeholders,
    this.forShop = false,
    this.timing,
    this.defaultOffset = 0,
    this.actions = const [],
  });

  final NotifKind kind;
  final String label;
  final String description;
  final IconData icon;
  final Color bg;
  final Color fg;
  final String title;
  final String body;
  final List<String> placeholders;
  final bool forShop;
  final NotifTiming? timing;
  final int defaultOffset;
  final List<String> actions;

  String get key => kind.name;
}

// colori per tipologia: verde conferma, blu promemoria, arancio da fare/avviso,
// rosso annullato, viola recensione, nero novita'
const _green = (Color(0xFFDDF1E3), Color(0xFF145C35));
const _blue = (Color(0xFFE6F1FB), Color(0xFF0C447C));
const _amber = (Color(0xFFFFF1DB), Color(0xFF8A4B00));
const _red = (Color(0xFFFCEBEB), Color(0xFF791F1F));
const _purple = (Color(0xFFEEEDFE), Color(0xFF3C3489));
const _black = (Color(0xFF141414), Color(0xFFF1F0ED));

const _appt = ['nome', 'servizio', 'giorno', 'ora', 'barbiere', 'indirizzo'];

final notifTypes = <NotifType>[
  NotifType(
    kind: NotifKind.bookingConfirmed,
    label: 'Prenotazione confermata',
    description: 'Subito dopo la prenotazione',
    icon: Icons.check,
    bg: _green.$1,
    fg: _green.$2,
    title: 'Prenotazione confermata',
    body: '{giorno} · {ora} · {servizio} con {barbiere}',
    placeholders: _appt,
  ),
  NotifType(
    kind: NotifKind.reminderDay,
    label: 'Promemoria del giorno prima',
    description: 'Il giorno prima dell\'appuntamento',
    icon: Icons.schedule,
    bg: _blue.$1,
    fg: _blue.$2,
    title: 'Domani hai appuntamento',
    body: '{ora} · {servizio} con {barbiere}. Ti aspettiamo',
    placeholders: _appt,
    timing: NotifTiming.before,
    defaultOffset: 24 * 60,
  ),
  NotifType(
    kind: NotifKind.reminderHour,
    label: 'Promemoria poco prima',
    description: 'Poco prima dell\'appuntamento',
    icon: Icons.alarm,
    bg: _blue.$1,
    fg: _blue.$2,
    title: 'Tra un\'ora tocca a te',
    body: '{ora} · {indirizzo}',
    placeholders: _appt,
    timing: NotifTiming.before,
    defaultOffset: 60,
  ),
  NotifType(
    kind: NotifKind.attendanceCheck,
    label: 'Conferma presenza',
    description: 'Il giorno prima: «Ci sono» o «Annulla»',
    icon: Icons.help_outline,
    bg: _amber.$1,
    fg: _amber.$2,
    title: 'Ci sei domani alle {ora}?',
    body: 'Se non puoi venire, libera il posto per chi aspetta',
    placeholders: _appt,
    timing: NotifTiming.dayBeforeAt,
    defaultOffset: 18 * 60,
    actions: ['Ci sono', 'Annulla'],
  ),
  NotifType(
    kind: NotifKind.waitlistAssigned,
    label: 'Posto dalla lista d\'attesa',
    description: 'Quando si libera il posto atteso',
    icon: Icons.celebration_outlined,
    bg: _green.$1,
    fg: _green.$2,
    title: 'Si è liberato il tuo posto',
    body: '{giorno} · {ora} è tuo. Lo trovi nei tuoi appuntamenti',
    placeholders: _appt,
  ),
  NotifType(
    kind: NotifKind.moved,
    label: 'Appuntamento spostato',
    description: 'Quando il negozio sposta l\'appuntamento',
    icon: Icons.swap_horiz,
    bg: _blue.$1,
    fg: _blue.$2,
    title: 'Appuntamento spostato',
    body: 'Ora è {giorno} · {ora} con {barbiere}',
    placeholders: _appt,
  ),
  NotifType(
    kind: NotifKind.cancelled,
    label: 'Appuntamento annullato',
    description: 'Quando il negozio annulla l\'appuntamento',
    icon: Icons.event_busy_outlined,
    bg: _red.$1,
    fg: _red.$2,
    title: 'Appuntamento annullato',
    body: '{giorno} · {ora}. Scegli un nuovo orario quando vuoi',
    placeholders: _appt,
    actions: ['Prenota'],
  ),
  NotifType(
    kind: NotifKind.shopNotice,
    label: 'Avviso del negozio',
    description: 'Chiusure, ferie, orari speciali',
    icon: Icons.warning_amber_rounded,
    bg: _amber.$1,
    fg: _amber.$2,
    title: 'Avviso dal negozio',
    body: '{messaggio}',
    placeholders: ['nome', 'messaggio', 'negozio'],
  ),
  NotifType(
    kind: NotifKind.review,
    label: 'Recensione dopo il taglio',
    description: 'Dopo la fine dell\'appuntamento',
    icon: Icons.star_outline,
    bg: _purple.$1,
    fg: _purple.$2,
    title: 'Com\'è andata con {barbiere}?',
    body: 'Lascia un voto, bastano 5 secondi',
    placeholders: _appt,
    timing: NotifTiming.afterEnd,
    defaultOffset: 60,
  ),
  NotifType(
    kind: NotifKind.news,
    label: 'Novità e offerte',
    description: 'Solo a chi ha dato il consenso',
    icon: Icons.campaign_outlined,
    bg: _black.$1,
    fg: _black.$2,
    title: 'Novità in negozio',
    body: '{messaggio}',
    placeholders: ['nome', 'messaggio', 'negozio'],
  ),
  NotifType(
    kind: NotifKind.newBooking,
    label: 'Nuova prenotazione',
    description: 'Quando un cliente prenota dall\'app',
    icon: Icons.event_available_outlined,
    bg: _green.$1,
    fg: _green.$2,
    title: 'Nuova prenotazione · {cliente}',
    body: '{giorno} · {ora} · {servizio} con {barbiere}',
    placeholders: ['cliente', 'servizio', 'giorno', 'ora', 'barbiere'],
    forShop: true,
  ),
  NotifType(
    kind: NotifKind.bookingCancelled,
    label: 'Prenotazione annullata',
    description: 'Quando un cliente annulla',
    icon: Icons.event_busy_outlined,
    bg: _red.$1,
    fg: _red.$2,
    title: '{cliente} ha annullato',
    body: '{giorno} · {ora} · {servizio}',
    placeholders: ['cliente', 'servizio', 'giorno', 'ora', 'barbiere'],
    forShop: true,
  ),
  NotifType(
    kind: NotifKind.waitlistShop,
    label: 'Lista d\'attesa',
    description: 'Quando qualcuno si mette in lista',
    icon: Icons.hourglass_bottom,
    bg: _amber.$1,
    fg: _amber.$2,
    title: '{persone} in lista d\'attesa per {giorno}',
    body: '{ora} con {barbiere} · puoi accettarle come extra',
    placeholders: ['persone', 'giorno', 'ora', 'barbiere'],
    forShop: true,
  ),
  NotifType(
    kind: NotifKind.lowStock,
    label: 'Prodotto da riordinare',
    description: 'Quando la giacenza scende sotto la soglia',
    icon: Icons.inventory_2_outlined,
    bg: _red.$1,
    fg: _red.$2,
    title: '{prodotto} da riordinare',
    body: 'Ne restano {rimasti} · avviso sotto {soglia}',
    placeholders: ['prodotto', 'rimasti', 'soglia'],
    forShop: true,
  ),
];

NotifType notifType(NotifKind k) => notifTypes.firstWhere((t) => t.kind == k);

/// Esempi per l'anteprima nell'area riservata.
const notifSample = {
  'nome': 'Marco',
  'cliente': 'Marco Rossi',
  'servizio': 'Taglio',
  'giorno': 'sab 17 ott',
  'ora': '10:30',
  'barbiere': 'Antonio',
  'indirizzo': 'Via Garibaldi 91, Andria',
  'negozio': 'The Man\'s House',
  'messaggio': 'Lunedì 2 novembre siamo chiusi',
  'persone': '2 persone',
  'prodotto': 'Cera opaca',
  'rimasti': '2',
  'soglia': '4',
};

/// Sostituisce i segnaposto {chiave} con i valori.
String fillNotif(String template, Map<String, String> values) =>
    template.replaceAllMapped(RegExp(r'\{(\w+)\}'), (m) => values[m.group(1)] ?? m.group(0)!);

/// Impostazioni di una notifica scelte dal titolare (null = testo di partenza).
class NotifPref {
  NotifPref({this.enabled = true, this.title, this.body, this.offset});
  bool enabled;
  String? title;
  String? body;
  int? offset;

  factory NotifPref.fromJson(Map<String, dynamic> j) => NotifPref(
    enabled: j['enabled'] ?? true,
    title: j['title'],
    body: j['body'],
    offset: (j['offset'] as num?)?.toInt(),
  );

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    if (title != null) 'title': title,
    if (body != null) 'body': body,
    if (offset != null) 'offset': offset,
  };
}

/// Notifica pronta da mostrare (testi gia' compilati).
class NotifContent {
  const NotifContent({required this.type, required this.title, required this.body});
  final NotifType type;
  final String title;
  final String body;
}

/// Insieme delle preferenze: si legge con i testi di partenza come riserva.
class NotifSettings {
  NotifSettings([Map<String, NotifPref>? prefs]) : prefs = prefs ?? {};
  final Map<String, NotifPref> prefs;

  factory NotifSettings.fromJson(dynamic j) => NotifSettings({
    if (j is Map)
      for (final e in j.entries)
        if (e.value is Map) e.key as String: NotifPref.fromJson(Map<String, dynamic>.from(e.value as Map)),
  });

  Map<String, dynamic> toJson() => {for (final e in prefs.entries) e.key: e.value.toJson()};

  NotifPref _pref(NotifKind k) => prefs[k.name] ?? NotifPref();

  bool enabled(NotifKind k) => _pref(k).enabled;
  String title(NotifKind k) => _pref(k).title ?? notifType(k).title;
  String body(NotifKind k) => _pref(k).body ?? notifType(k).body;
  int offset(NotifKind k) => _pref(k).offset ?? notifType(k).defaultOffset;

  /// Testi compilati, o null se la notifica e' disattivata.
  NotifContent? build(NotifKind k, Map<String, String> values) => enabled(k)
      ? NotifContent(type: notifType(k), title: fillNotif(title(k), values), body: fillNotif(body(k), values))
      : null;

  NotifSettings copy() => NotifSettings.fromJson(toJson());
}

/// Notifica in stile essenziale: icona tonda nel colore del tipo, nome
/// dell'app, titolo e testo, eventuali pulsanti.
class NotificationCard extends StatelessWidget {
  const NotificationCard({
    super.key,
    required this.type,
    required this.title,
    required this.body,
    this.when = 'ora',
    this.onTap,
    this.onAction,
  });

  final NotifType type;
  final String title;
  final String body;
  final String when;
  final VoidCallback? onTap;
  final ValueChanged<String>? onAction;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white.withValues(alpha: 0.94),
    borderRadius: BorderRadius.circular(16),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: type.bg, shape: BoxShape.circle),
              child: Icon(type.icon, size: 19, color: type.fg),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          type.forShop ? 'Area riservata' : 'The Man\'s House',
                          style: const TextStyle(color: Color(0xFF5F5E5A), fontSize: 11.5),
                        ),
                      ),
                      Text(when, style: const TextStyle(color: Color(0xFF5F5E5A), fontSize: 11.5)),
                    ],
                  ),
                  const SizedBox(height: 1),
                  Text(
                    title,
                    style: const TextStyle(color: Color(0xFF141414), fontSize: 14, fontWeight: FontWeight.w800),
                  ),
                  Text(body, style: const TextStyle(color: Color(0xFF444441), fontSize: 13, height: 1.3)),
                  if (type.actions.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        for (final (i, a) in type.actions.indexed) ...[
                          if (i > 0) const SizedBox(width: 6),
                          Material(
                            color: i == 0 ? const Color(0xFF141414) : const Color(0xFFF1EFE8),
                            borderRadius: BorderRadius.circular(8),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: onAction == null ? null : () => onAction!(a),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                child: Text(
                                  a,
                                  style: TextStyle(
                                    color: i == 0 ? const Color(0xFFF1F0ED) : const Color(0xFF141414),
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
