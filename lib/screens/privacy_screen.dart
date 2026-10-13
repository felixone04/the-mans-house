import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Informativa privacy (testo base: da far verificare a un consulente).
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context).settings;
    final sections = <(String, String)>[
      ('Titolare del trattamento', '${s.name}, ${s.address}${s.phone.isEmpty ? '' : ' · tel. ${s.phone}'}.'),
      (
        'Quali dati raccogliamo',
        'Nome e cognome, numero di cellulare, email, appuntamenti prenotati e svolti, '
            'pagamenti registrati in negozio ed eventuali note sul servizio.',
      ),
      (
        'Perché li usiamo',
        '• Gestire le prenotazioni e i servizi richiesti (esecuzione del servizio).\n'
            '• Inviare conferme e promemoria degli appuntamenti su WhatsApp (puoi disattivarli dal profilo).\n'
            '• Avvisarti di chiusure o cambi di orario che riguardano i tuoi appuntamenti.\n'
            '• Solo con il tuo consenso facoltativo: inviarti offerte, promozioni e novità.',
      ),
      (
        'Per quanto tempo',
        'Per il tempo necessario a gestire il rapporto e gli obblighi di legge (es. fiscali); '
            'i dati usati per le offerte fino alla revoca del consenso.',
      ),
      (
        'Con chi li condividiamo',
        'Con i fornitori tecnici che ci permettono di far funzionare il servizio '
            '(hosting e database, invio dei messaggi WhatsApp), nominati responsabili del trattamento. '
            'Non vendiamo i tuoi dati.',
      ),
      (
        'I tuoi diritti',
        'Puoi chiedere accesso, correzione, cancellazione, limitazione, portabilità dei dati e '
            'opporti al trattamento; puoi revocare in ogni momento il consenso alle offerte dal tuo profilo. '
            'Puoi eliminare l\'account dall\'app. Hai diritto di reclamo al Garante per la protezione dei dati personali.',
      ),
    ];
    return AppScaffold(
      title: 'Privacy',
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            ResponsiveCenter(
              maxWidth: 640,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Informativa sul trattamento dei dati', style: slab(size: 19, weight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  const Text(
                    'Ai sensi del Regolamento UE 2016/679 (GDPR)',
                    style: TextStyle(color: AppColors.muted, fontSize: 12.5),
                  ),
                  for (final (title, body) in sections) ...[
                    SectionTitle(title),
                    Text(body, style: const TextStyle(color: AppColors.silver, height: 1.5)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Casella di consenso con testo cliccabile.
class ConsentBox extends StatelessWidget {
  const ConsentBox({super.key, required this.value, required this.onChanged, required this.text});
  final bool value;
  final ValueChanged<bool> onChanged;
  final String text;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => onChanged(!value),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Checkbox(value: value, onChanged: (v) => onChanged(v ?? false), visualDensity: VisualDensity.compact),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 12.5, color: AppColors.silver)),
          ),
        ],
      ),
    ),
  );
}

/// Collegamento all'informativa, da mettere accanto alle caselle di consenso.
class PrivacyLink extends StatelessWidget {
  const PrivacyLink({super.key});

  @override
  Widget build(BuildContext context) => TextButton(
    style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
    onPressed: () => Navigator.of(context).push(fadeRoute(const PrivacyScreen())),
    child: const Text('Leggi l\'informativa privacy', style: TextStyle(decoration: TextDecoration.underline)),
  );
}
