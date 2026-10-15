import 'package:flutter/material.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'complete_profile_screen.dart';
import 'privacy_screen.dart';

/// Apre login/registrazione e, se serve, il completamento profilo.
/// Ritorna true se al termine l'utente e' autenticato con profilo completo.
Future<bool> openAuthFlow(BuildContext context) async {
  final state = AppScope.read(context);
  if (!state.isSignedIn) {
    await Navigator.of(context).push<bool>(fadeRoute(const AuthScreen()));
  }
  if (!context.mounted || !state.isSignedIn) return false;
  if (state.needsProfile) {
    await Navigator.of(context).push<bool>(fadeRoute(const CompleteProfileScreen()));
  }
  return state.isSignedIn && !state.needsProfile;
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController(text: '+39 ');
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _register = false;
  bool _loading = false;
  bool _obscure = true;
  bool _privacy = false;
  bool _marketing = false;
  bool _closed = false;

  @override
  void dispose() {
    for (final c in [_name, _phone, _email, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _loading = true);
    try {
      await action();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    if (_register && !_privacy) {
      showMessage(context, 'Accetta l\'informativa privacy per continuare', error: true);
      return;
    }
    final state = AppScope.read(context);
    await _run(() async {
      if (_register) {
        final signedIn = await state.backend.signUpWithEmail(
          email: _email.text,
          password: _password.text,
          fullName: _name.text,
          phone: _phone.text,
          marketingOptIn: _marketing,
        );
        if (!signedIn) {
          if (!mounted) return;
          await showDialog<void>(
            context: context,
            builder: (c) => AlertDialog(
              title: const Text('Conferma la tua email'),
              content: Text(
                'Ti abbiamo inviato un link a ${_email.text.trim()}. '
                'Aprilo per attivare l\'account, poi accedi.',
              ),
              actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Ok'))],
            ),
          );
          setState(() => _register = false);
          return;
        }
      } else {
        await state.backend.signInWithEmail(_email.text, _password.text);
      }
      await state.refreshProfile();
      _close();
    });
  }

  Future<void> _forgot() async {
    final email = _email.text.trim();
    if (!email.contains('@')) {
      showMessage(context, 'Inserisci prima la tua email', error: true);
      return;
    }
    await _run(() async {
      await AppScope.read(context).backend.resetPassword(email);
      if (mounted) showMessage(context, 'Ti abbiamo inviato un\'email per reimpostare la password');
    });
  }

  void _close() {
    if (_closed || !mounted) return;
    _closed = true;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    // Ritorno dal login Google/Apple: l'evento di autenticazione arriva qui.
    if (state.isSignedIn && state.profile != null && !_closed) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _close());
    }

    return AppScaffold(
      title: _register ? 'Crea account' : 'Accedi',
      body: SafeArea(
        child: FitBody(
          maxWidth: 460,
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!_register) ...[
                  const Center(child: AppLogo(height: 120)),
                  const SizedBox(height: 18),
                ],
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('Accedi')),
                    ButtonSegment(value: true, label: Text('Registrati')),
                  ],
                  selected: {_register},
                  showSelectedIcon: false,
                  onSelectionChanged: (v) => setState(() => _register = v.first),
                  style: SegmentedButton.styleFrom(
                    selectedBackgroundColor: AppColors.white,
                    selectedForegroundColor: AppColors.black,
                    minimumSize: const Size(0, 44),
                  ),
                ),
                const SizedBox(height: 18),
                if (_register) ...[
                  TextFormField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    autofillHints: const [AutofillHints.name],
                    decoration: const InputDecoration(
                      labelText: 'Nome e cognome',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    validator: (v) => (v ?? '').trim().length < 2 ? 'Inserisci il tuo nome' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    autofillHints: const [AutofillHints.telephoneNumber],
                    decoration: const InputDecoration(
                      labelText: 'Cellulare WhatsApp (per i promemoria)',
                      prefixIcon: Icon(Icons.phone_iphone),
                    ),
                    validator: (v) => isValidPhone(v ?? '') ? null : 'Numero non valido',
                  ),
                  const SizedBox(height: 12),
                ],
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.mail_outline)),
                  validator: (v) =>
                      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch((v ?? '').trim()) ? null : 'Email non valida',
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _password,
                  obscureText: _obscure,
                  autofillHints: [_register ? AutofillHints.newPassword : AutofillHints.password],
                  onFieldSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  validator: (v) => (v ?? '').length < 6 ? 'Minimo 6 caratteri' : null,
                ),
                if (_register) ...[
                  const SizedBox(height: 4),
                  ConsentBox(
                    value: _privacy,
                    onChanged: (v) => setState(() => _privacy = v),
                    text: 'Ho letto l\'informativa privacy e accetto i promemoria degli appuntamenti su WhatsApp (obbligatorio)',
                  ),
                  ConsentBox(
                    value: _marketing,
                    onChanged: (v) => setState(() => _marketing = v),
                    text: 'Voglio ricevere offerte e novità su WhatsApp (facoltativo)',
                  ),
                  const Align(alignment: Alignment.centerLeft, child: PrivacyLink()),
                ] else
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(onPressed: _loading ? null : _forgot, child: const Text('Password dimenticata?')),
                  ),
                const SizedBox(height: 8),
                PrimaryButton(label: _register ? 'Crea account' : 'Accedi', loading: _loading, onPressed: _submit),
                const SizedBox(height: 18),
                const Row(
                  children: [
                    Expanded(child: Divider()),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text('oppure', style: TextStyle(color: AppColors.muted)),
                    ),
                    Expanded(child: Divider()),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _SocialButton(
                        label: 'Google',
                        icon: const _GoogleMark(),
                        onPressed: _loading ? null : () => _run(() => state.backend.signInWithGoogle()),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _SocialButton(
                        label: 'Apple',
                        icon: const Icon(Icons.apple, size: 24),
                        onPressed: _loading ? null : () => _run(() => state.backend.signInWithApple()),
                      ),
                    ),
                  ],
                ),
                if (state.backend.isDemo) ...[
                  const SizedBox(height: 14),
                  const Text(
                    'Demo · amministratore: admin@demo.it / admin123',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.warning, fontSize: 11.5),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SocialButton extends StatelessWidget {
  const _SocialButton({required this.label, required this.icon, required this.onPressed});
  final String label;
  final Widget icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: onPressed,
    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(width: 24, height: 24, child: Center(child: icon)),
        const SizedBox(width: 12),
        Text(label),
      ],
    ),
  );
}

class _GoogleMark extends StatelessWidget {
  const _GoogleMark();

  @override
  Widget build(BuildContext context) => Container(
    width: 22,
    height: 22,
    decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
    alignment: Alignment.center,
    child: const Text(
      'G',
      style: TextStyle(color: Color(0xFF4285F4), fontWeight: FontWeight.w900, fontSize: 14, height: 1.1),
    ),
  );
}
