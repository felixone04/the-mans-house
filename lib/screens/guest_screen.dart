import 'package:flutter/material.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'auth_screen.dart';
import 'privacy_screen.dart';

/// Prenotazione senza account: nome, cognome e cellulare obbligatori,
/// email facoltativa. Consiglia di creare l'account per le prossime volte.
/// Ritorna true quando l'ospite e' collegato e si puo' prenotare.
class GuestScreen extends StatefulWidget {
  const GuestScreen({super.key});

  @override
  State<GuestScreen> createState() => _GuestScreenState();
}

class _GuestScreenState extends State<GuestScreen> {
  final _form = GlobalKey<FormState>();
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _phone = TextEditingController(text: '+39 ');
  final _email = TextEditingController();
  bool _privacy = false;
  bool _marketing = false;
  bool _loading = false;

  @override
  void dispose() {
    for (final c in [_first, _last, _phone, _email]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _continue() async {
    if (!_form.currentState!.validate()) return;
    if (!_privacy) {
      showMessage(context, 'Accetta l\'informativa privacy per continuare', error: true);
      return;
    }
    final state = AppScope.read(context);
    setState(() => _loading = true);
    try {
      await state.backend.signInAsGuest(
        fullName: '${_first.text.trim()} ${_last.text.trim()}',
        phone: _phone.text,
        email: _email.text.trim(),
        marketingOptIn: _marketing,
      );
      await state.refreshProfile();
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createAccount() async {
    await Navigator.of(context).push<bool>(fadeRoute(const AuthScreen(startRegister: true)));
    if (!mounted) return;
    final state = AppScope.read(context);
    if (state.isSignedIn && !state.needsProfile) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'I tuoi dati',
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(top: 8, bottom: 24),
          children: [
            ResponsiveCenter(
              maxWidth: 480,
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _first,
                            textCapitalization: TextCapitalization.words,
                            autofillHints: const [AutofillHints.givenName],
                            decoration: const InputDecoration(labelText: 'Nome *'),
                            validator: (v) => (v ?? '').trim().isEmpty ? 'Obbligatorio' : null,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextFormField(
                            controller: _last,
                            textCapitalization: TextCapitalization.words,
                            autofillHints: const [AutofillHints.familyName],
                            decoration: const InputDecoration(labelText: 'Cognome *'),
                            validator: (v) => (v ?? '').trim().isEmpty ? 'Obbligatorio' : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      autofillHints: const [AutofillHints.telephoneNumber],
                      decoration: const InputDecoration(
                        labelText: 'Cellulare WhatsApp *',
                        helperText: 'Per la conferma e i promemoria dell\'appuntamento',
                        prefixIcon: Icon(Icons.phone_iphone),
                      ),
                      validator: (v) => isValidPhone(v ?? '') ? null : 'Numero non valido',
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(
                        labelText: 'Email (facoltativa)',
                        prefixIcon: Icon(Icons.mail_outline),
                      ),
                      validator: (v) {
                        final t = (v ?? '').trim();
                        return t.isEmpty || RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t)
                            ? null
                            : 'Email non valida';
                      },
                    ),
                    const SizedBox(height: 8),
                    ConsentBox(
                      value: _privacy,
                      onChanged: (v) => setState(() => _privacy = v),
                      text: 'Ho letto l\'informativa privacy e accetto i promemoria su WhatsApp (obbligatorio)',
                    ),
                    ConsentBox(
                      value: _marketing,
                      onChanged: (v) => setState(() => _marketing = v),
                      text: 'Voglio ricevere offerte e novità su WhatsApp (facoltativo)',
                    ),
                    const Align(alignment: Alignment.centerLeft, child: PrivacyLink()),
                    const SizedBox(height: 12),
                    // consiglio: con l'account non si riscrivono i dati
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(12)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Crea un account in pochi secondi',
                            style: slab(size: 15, weight: FontWeight.w700, color: AppColors.black, spacing: 0.2),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'La prossima volta prenoti con un tocco, senza riscrivere i dati, e ritrovi tutti i tuoi '
                            'appuntamenti.',
                            style: TextStyle(color: AppColors.black, fontSize: 13, height: 1.4),
                          ),
                          const SizedBox(height: 10),
                          OutlinedButton(
                            onPressed: _loading ? null : _createAccount,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.black,
                              side: const BorderSide(color: AppColors.black),
                              minimumSize: const Size.fromHeight(44),
                            ),
                            child: const Text('Crea account e prenota'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    PrimaryButton(label: 'Prenota senza account', loading: _loading, onPressed: _continue),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Da ospite ad account: email e password, mantenendo gli appuntamenti.
class GuestUpgradeScreen extends StatefulWidget {
  const GuestUpgradeScreen({super.key});

  @override
  State<GuestUpgradeScreen> createState() => _GuestUpgradeScreenState();
}

class _GuestUpgradeScreenState extends State<GuestUpgradeScreen> {
  final _form = GlobalKey<FormState>();
  late final _email = TextEditingController(text: AppScope.read(context).profile?.email ?? '');
  final _password = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final state = AppScope.read(context);
    setState(() => _loading = true);
    try {
      final done = await state.backend.upgradeGuest(email: _email.text, password: _password.text);
      await state.refreshProfile();
      if (!mounted) return;
      if (done) {
        showMessage(context, 'Account creato: i tuoi appuntamenti sono salvati');
        Navigator.of(context).pop(true);
      } else {
        await showDialog<void>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Conferma la tua email'),
            content: Text(
              'Ti abbiamo inviato un link a ${_email.text.trim()}. Aprilo per attivare l\'account: '
              'poi torna qui e imposta la password.',
            ),
            actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Ok'))],
          ),
        );
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => AppScaffold(
    title: 'Crea account',
    body: SafeArea(
      child: FitBody(
        maxWidth: 460,
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Tieni i tuoi dati e i tuoi appuntamenti: scegli email e password per accedere anche da altri '
                'dispositivi.',
                style: TextStyle(color: AppColors.silver, height: 1.4),
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.mail_outline)),
                validator: (v) =>
                    RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch((v ?? '').trim()) ? null : 'Email non valida',
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Password', prefixIcon: Icon(Icons.lock_outline)),
                validator: (v) => (v ?? '').length < 6 ? 'Minimo 6 caratteri' : null,
              ),
              const SizedBox(height: 18),
              PrimaryButton(label: 'Crea account', loading: _loading, onPressed: _save),
            ],
          ),
        ),
      ),
    ),
  );
}
