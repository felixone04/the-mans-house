import 'package:flutter/material.dart';

import '../../models.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// Cliente di una prenotazione inserita dal titolare.
class BookingCustomer {
  const BookingCustomer({this.userId, required this.name, this.phone = '', this.email = '', this.anonymous = false});

  /// Cliente "senza dati": per fare in fretta, appare come "Cliente".
  const BookingCustomer.anonymous() : this(name: 'Cliente', anonymous: true);

  /// Id dell'account se il cliente usa l'app: l'appuntamento compare nella sua app.
  final String? userId;
  final String name;
  final String phone;
  final String email;
  final bool anonymous;

  String get detail => anonymous
      ? 'Senza dati'
      : [if (phone.isNotEmpty) phone, if (email.isNotEmpty) email, if (userId != null) 'con app'].join(' · ');
}

/// Scelta del cliente: esistente (ricerca), nuovo oppure senza dati.
Future<BookingCustomer?> pickCustomer(BuildContext context) => showModalBottomSheet<BookingCustomer>(
  context: context,
  isScrollControlled: true,
  constraints: const BoxConstraints(maxWidth: 560),
  builder: (_) => const _CustomerPicker(),
);

class _CustomerPicker extends StatefulWidget {
  const _CustomerPicker();

  @override
  State<_CustomerPicker> createState() => _CustomerPickerState();
}

class _CustomerPickerState extends State<_CustomerPicker> {
  List<CustomerSummary> _all = [];
  bool _loading = true;
  String _query = '';
  bool _newCustomer = false;

  final _form = GlobalKey<FormState>();
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _phone = TextEditingController(text: '+39 ');
  final _email = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    for (final c in [_first, _last, _phone, _email]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final list = await AppScope.read(context).backend.customers();
      if (mounted) setState(() => _all = list);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<CustomerSummary> get _results {
    final q = _query.trim().toLowerCase();
    final digits = q.replaceAll(RegExp(r'\D'), '');
    return _all
        .where(
          (c) =>
              q.isEmpty ||
              c.fullName.toLowerCase().contains(q) ||
              c.email.toLowerCase().contains(q) ||
              (digits.length >= 3 && c.phone.replaceAll(RegExp(r'\D'), '').contains(digits)),
        )
        .take(40)
        .toList();
  }

  void _saveNew() {
    if (!_form.currentState!.validate()) return;
    final phone = _phone.text.trim();
    Navigator.pop(
      context,
      BookingCustomer(
        name: '${_first.text.trim()} ${_last.text.trim()}'.trim(),
        phone: isValidPhone(phone) ? phone : '',
        email: _email.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.8;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SizedBox(
          height: height,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: _newCustomer ? _buildNew() : _buildSearch(),
          ),
        ),
      ),
    );
  }

  Widget _buildSearch() {
    final results = _results;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Per chi è l\'appuntamento?', style: slab(size: 19, weight: FontWeight.w600, spacing: 0.3)),
        const SizedBox(height: 12),
        TextField(
          autofocus: true,
          onChanged: (v) => setState(() => _query = v),
          decoration: const InputDecoration(hintText: 'Cerca per nome o numero', prefixIcon: Icon(Icons.search)),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : results.isEmpty
              ? const EmptyState(icon: Icons.person_search_outlined, text: 'Nessun cliente trovato')
              : ListView.builder(
                  itemCount: results.length,
                  itemBuilder: (context, i) {
                    final c = results[i];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                      leading: CircleAvatar(
                        backgroundColor: AppColors.white,
                        child: Text(
                          c.fullName.isEmpty ? '?' : c.fullName[0].toUpperCase(),
                          style: const TextStyle(color: AppColors.black, fontWeight: FontWeight.w800),
                        ),
                      ),
                      title: Text(
                        c.fullName.isEmpty ? '(senza nome)' : c.fullName,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        [
                          if (c.phone.isNotEmpty) c.phone,
                          '${c.bookings} ${c.bookings == 1 ? 'visita' : 'visite'}',
                          if (!c.isWalkIn) 'con app',
                        ].join(' · '),
                        style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
                      ),
                      onTap: () => Navigator.pop(
                        context,
                        BookingCustomer(
                          userId: c.isWalkIn ? null : c.id,
                          name: c.fullName,
                          phone: c.phone,
                          email: c.email,
                        ),
                      ),
                    );
                  },
                ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () => setState(() => _newCustomer = true),
                icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
                label: const Text('Nuovo cliente'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => Navigator.pop(context, const BookingCustomer.anonymous()),
                icon: const Icon(Icons.bolt, size: 18),
                label: const Text('Senza dati'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildNew() => Form(
    key: _form,
    child: ListView(
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Indietro',
              onPressed: () => setState(() => _newCustomer = false),
              icon: const Icon(Icons.arrow_back),
            ),
            Text('Nuovo cliente', style: slab(size: 19, weight: FontWeight.w600, spacing: 0.3)),
          ],
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _first,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Nome *'),
          validator: (v) => (v ?? '').trim().isEmpty ? 'Obbligatorio' : null,
        ),
        const SizedBox(height: 10),
        TextFormField(
          controller: _last,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Cognome'),
        ),
        const SizedBox(height: 10),
        TextFormField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: 'Cellulare (per i promemoria)'),
          validator: (v) {
            final t = (v ?? '').replaceAll(RegExp(r'[\s+]'), '');
            if (t.isEmpty || t == '39') return null;
            return isValidPhone(v!) ? null : 'Numero non valido';
          },
        ),
        const SizedBox(height: 10),
        TextFormField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'Email (facoltativa)'),
          validator: (v) {
            final t = (v ?? '').trim();
            return t.isEmpty || RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t) ? null : 'Email non valida';
          },
        ),
        const SizedBox(height: 16),
        PrimaryButton(label: 'Usa questo cliente', icon: Icons.check, onPressed: _saveNew),
      ],
    ),
  );
}
