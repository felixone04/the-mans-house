# The Man's House – App prenotazioni

App Flutter (Android, iOS, web) per prenotare servizi presso **The Man's House**, Via Garibaldi 91, Andria.
Backend: **Supabase** (database, login, funzioni). Promemoria: **WhatsApp** (Meta Cloud API o Twilio).

## Funzioni

**Clienti**
- Apertura con logo animato su sfondo nero sfumato
- Home a schermata unica e pulita: tasto **Prenota ora** in alto, logo al centro, in basso Indicazioni, Orari, Chiama, WhatsApp, Instagram (se impostato in Impostazioni → Il locale) e l'indirizzo
- Accesso/registrazione con email, Google o Apple (iCloud). Il cellulare WhatsApp è obbligatorio.
- Prenotazione in 4 passi: servizio → barbiere (o "primo disponibile") → data e ora libere → conferma
- Conferma, elenco appuntamenti, spostamento e annullamento dall'app (fino a N ore prima, configurabile)
- Promemoria WhatsApp automatici 24 ore e 1 ora prima
- Eliminazione account (richiesta dall'App Store)

**Area riservata** (solo account amministratore)
- Agenda con settimana in alto (numero di appuntamenti per giorno), riepilogo del giorno e filtro per barbiere (un colore per barbiere)
  - **Barbieri** (predefinita su telefono, colori chiari): lo schermo è diviso in un riquadro pastello per barbiere con solo il nome. Toccandolo si apre la sua giornata: una scheda grande per appuntamento (orario, cliente, servizio, prezzo, note), rossa finché non è completato e bianca quando è completato, spazi liberi e ora attuale. Toccando la scheda: chiama, promemoria, scheda cliente, sposta, annulla
  - **Griglia** (predefinita su tablet/computer): una colonna per barbiere; su telefono scorre in verticale
- Nella giornata del barbiere ogni appuntamento ha i pulsanti **Completato** e **Pagamento** (pagato, paga dopo, acconto con importo e resto). Se il cliente deve ancora pagare visite precedenti compare l'avviso con il **totale da pagare oggi**, e pagando si può saldare tutto insieme
- Tocca un appuntamento per: promemoria WhatsApp, chiama, scheda cliente, sposta, completato, non presentato, annulla
- Tocca uno spazio libero per inserire un appuntamento; tienilo premuto (o "+" → Blocca un orario) per bloccarlo (pausa, imprevisto...). Tocca un blocco per rimuoverlo
- **Cliente entrato ora** (menu "+" dell'agenda o pulsante "Entrato ora" nella giornata del barbiere): servizio, barbiere o "primo libero", nome facoltativo → inserito nel primo orario libero da adesso
- **Cerca** (lente in alto nell'area riservata): nome o numero → cliente con il prossimo appuntamento, tocca per la scheda cliente
- **Chiusure e orari speciali** (Impostazioni): ferie e festività (niente prenotazioni) e giorni con orario diverso, anche solo per alcuni barbieri; i clienti li vedono in "Orari"
- **Messaggio a tutti** (Clienti): avviso di servizio a tutti i clienti con cellulare o promozione solo a chi ha dato il consenso; ogni tocco apre WhatsApp con il messaggio pronto e segna il cliente come fatto
- **Consensi**: alla registrazione informativa privacy (obbligatoria) e offerte (facoltativo), modificabili dal profilo; per i clienti dal banco si segnano nella scheda cliente
- **Esporta dati** (Impostazioni): clienti e incassi (mese, mese scorso, anno o periodo a scelta) in un file .csv per Excel, con totali per barbiere
- Servizi: aggiungi, modifica prezzo e durata, nascondi, elimina
- Barbieri: orari settimanali con più fasce al giorno, ferie e permessi
- Clienti: ricerca, numero di prenotazioni, contatto rapido; tocca un cliente per la **scheda cliente** (visite, non presentato, speso, servizio e barbiere preferiti, storico, prenota per lui)
- Impostazioni: dati del locale, intervallo tra gli orari, giorni prenotabili, limite di annullamento, promemoria on/off, amministratori

La grafica si adatta a telefono, tablet e computer senza deformarsi: il contenuto è centrato con una larghezza massima.

---

## Modalità DEMO (subito, senza server)

Se le chiavi Supabase non sono configurate, l'app parte in **modalità demo** con dati di esempio in memoria:
- cliente: registrati con qualsiasi email, oppure usa "Continua con Google"
- amministratore: `admin@demo.it` / `admin123`

```bash
flutter run -d chrome
```

> Flutter è installato in `C:\src\flutter\bin` e Git in `C:\src\git\cmd` (entrambi nel PATH dell'utente).

---

## 1. Configurare Supabase

1. Crea un progetto su [supabase.com](https://supabase.com) (regione EU).
2. In **SQL Editor** esegui, in ordine:
   - `supabase/migrations/20261010000000_init.sql` (tabelle, sicurezza, funzioni)
   - `supabase/migrations/20261013000000_reschedule.sql` (spostamento appuntamenti)
   - `supabase/migrations/20261013010000_visit_payment.sql` (arrivo e pagamenti)
   - `supabase/migrations/20261013020000_shop_days_consents.sql` (chiusure, orari speciali, consensi)
   - `supabase/seed.sql` (servizi, 3 barbieri e orari di esempio, da modificare poi in app)
3. Imposta l'email del titolare come amministratore:
   ```sql
   insert into public.admin_emails (email) values ('titolare@esempio.it');
   -- se l'account esiste già:
   update public.profiles set is_admin = true where email = 'titolare@esempio.it';
   ```
4. Copia `config.example.json` in `config.json` e inserisci URL e chiave pubblica (Project Settings → API).

### Login con Google e Apple
In Supabase → **Authentication → URL Configuration** aggiungi tra i Redirect URL:
```
themanshouse://login-callback
```
- **Google**: Google Cloud Console → crea un "OAuth client ID" (tipo Web) con redirect `https://<PROJECT_REF>.supabase.co/auth/v1/callback`, poi inserisci Client ID e Secret in Supabase → Authentication → Providers → Google.
- **Apple**: serve l'Apple Developer Program (99 €/anno). Crea un Services ID con "Sign in with Apple", stesso redirect, e configura il provider Apple in Supabase.

## 2. Promemoria WhatsApp

WhatsApp consente messaggi automatici solo con un **numero business** e **modelli di messaggio approvati**.

1. Crea due modelli (categoria *Utility*, lingua italiano) con 4 variabili, ad esempio:
   - `promemoria_24h`: *Ciao {{1}}, ti ricordiamo il tuo appuntamento per {{2}} {{3}} con {{4}} da The Man's House. Se non puoi venire annulla dall'app. A presto!*
   - `promemoria_1h`: *Ciao {{1}}, tra un'ora ti aspettiamo per {{2}} ({{3}}) con {{4}}. Via Garibaldi 91, Andria.*
2. Pubblica la funzione e imposta i segreti (con la [Supabase CLI](https://supabase.com/docs/guides/cli)):
   ```bash
   supabase functions deploy send-reminders --no-verify-jwt
   supabase secrets set REMINDER_SECRET=<una-stringa-casuale-lunga>
   # Meta WhatsApp Cloud API
   supabase secrets set WHATSAPP_PROVIDER=meta META_WA_TOKEN=... META_WA_PHONE_NUMBER_ID=... META_WA_TEMPLATE_24H=promemoria_24h META_WA_TEMPLATE_1H=promemoria_1h
   # oppure Twilio
   supabase secrets set WHATSAPP_PROVIDER=twilio TWILIO_ACCOUNT_SID=... TWILIO_AUTH_TOKEN=... TWILIO_WHATSAPP_FROM=+39... TWILIO_CONTENT_SID_24H=... TWILIO_CONTENT_SID_1H=...
   ```
3. Esegui `supabase/reminders_cron.sql` nel SQL Editor (sostituendo `<PROJECT_REF>` e `<REMINDER_SECRET>`): ogni 5 minuti invia i promemoria dovuti.

Finché WhatsApp non è configurato, dall'agenda puoi comunque inviare il promemoria a mano (menu ⋮ → *Promemoria WhatsApp*).

## 3. Generare l'APK di test (Android)

Servono JDK 17 e Android SDK (installabili con Android Studio).

```bash
flutter build apk --release --dart-define-from-file=config.json
```
Il file si trova in `build/app/outputs/flutter-apk/app-release.apk`. Senza `--dart-define-from-file` l'APK parte in modalità demo.

Per la pubblicazione su Play Store crea una chiave di firma ([guida](https://docs.flutter.dev/deployment/android#sign-the-app)) e genera un `appbundle`.

## 4. iOS

Serve un Mac con Xcode (oppure un servizio cloud come Codemagic) e un account Apple Developer.
```bash
flutter build ipa --dart-define-from-file=config.json
```
Bundle ID e schema di ritorno login sono già configurati (`themanshouse://`).

## Struttura

```
lib/
  main.dart, theme.dart, config.dart, models.dart
  data/        backend.dart (interfaccia), supabase_backend.dart, demo_backend.dart, slots.dart (calcolo disponibilità)
  state/       app_state.dart
  screens/     splash, home, auth, complete_profile, account, booking, booking_success
  screens/admin/ agenda, servizi, barbieri (+ editor orari), clienti, impostazioni
supabase/
  migrations/  schema + sicurezza (RLS) + funzioni book/cancel
  functions/send-reminders/  promemoria WhatsApp
  seed.sql, reminders_cron.sql
```

La disponibilità è verificata anche sul server (`book_appointment`) e un vincolo del database impedisce le doppie prenotazioni sullo stesso barbiere.
