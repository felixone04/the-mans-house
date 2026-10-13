import 'package:flutter/material.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'privacy_screen.dart';

/// Richiede nome e cellulare (per i promemoria WhatsApp) dopo il login
/// con Google/Apple o per modificare il profilo.
class CompleteProfileScreen extends StatefulWidget {
  const CompleteProfileScreen({super.key, this.editing = false});
  final bool editing;

  @override
  State<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends State<CompleteProfileScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late bool _optIn;
  late bool _marketing;
  late bool _privacy;
  late final bool _privacyAlreadyAccepted;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    final p = AppScope.read(context).profile;
    _name = TextEditingController(text: p?.fullName ?? '');
    _phone = TextEditingController(text: (p?.phone.isNotEmpty ?? false) ? p!.phone : '+39 ');
    _optIn = p?.whatsappOptIn ?? true;
    _marketing = p?.marketingOptIn ?? false;
    _privacyAlreadyAccepted = p?.privacyAcceptedAt != null;
    _privacy = _privacyAlreadyAccepted;
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (!_privacy) {
      showMessage(context, 'Accetta l\'informativa privacy per continuare', error: true);
      return;
    }
    final state = AppScope.read(context);
    final p = state.profile;
    if (p == null) return;
    setState(() => _loading = true);
    try {
      await state.backend.updateProfile(
        Profile(
          id: p.id,
          email: p.email,
          fullName: _name.text,
          phone: _phone.text,
          isAdmin: p.isAdmin,
          whatsappOptIn: _optIn,
          privacyAcceptedAt: p.privacyAcceptedAt ?? DateTime.now(),
          marketingOptIn: _marketing,
        ),
      );
      await state.refreshProfile();
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: widget.editing ? 'Il mio profilo' : 'Completa il profilo',
      body: SafeArea(
        child: FitBody(
          maxWidth: 460,
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 12),
                if (!widget.editing) ...[
                  Text(
                    'Ancora un passo',
                    style: slab(size: 22, weight: FontWeight.w600),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Ci servono il tuo nome e il numero WhatsApp per confermare gli appuntamenti e mandarti i promemoria.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.silver, height: 1.4),
                  ),
                  const SizedBox(height: 28),
                ],
                TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Nome e cognome',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  validator: (v) => (v ?? '').trim().length < 2 ? 'Inserisci il tuo nome' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Cellulare WhatsApp',
                    prefixIcon: Icon(Icons.phone_iphone),
                  ),
                  validator: (v) => isValidPhone(v ?? '') ? null : 'Numero non valido',
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  value: _optIn,
                  onChanged: (v) => setState(() => _optIn = v),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Promemoria su WhatsApp'),
                  subtitle: const Text(
                    '24 ore e 1 ora prima dell\'appuntamento',
                    style: TextStyle(color: AppColors.muted, fontSize: 12.5),
                  ),
                ),
                SwitchListTile(
                  value: _marketing,
                  onChanged: (v) => setState(() => _marketing = v),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Offerte e novità su WhatsApp'),
                  subtitle: const Text(
                    'Facoltativo: puoi cambiare idea quando vuoi',
                    style: TextStyle(color: AppColors.muted, fontSize: 12.5),
                  ),
                ),
                // l'informativa si accetta una volta: poi resta solo il collegamento
                if (!_privacyAlreadyAccepted)
                  ConsentBox(
                    value: _privacy,
                    onChanged: (v) => setState(() => _privacy = v),
                    text: 'Ho letto l\'informativa privacy (obbligatorio)',
                  ),
                const Align(alignment: Alignment.centerLeft, child: PrivacyLink()),
                const SizedBox(height: 12),
                PrimaryButton(label: 'Salva', loading: _loading, onPressed: _save),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
