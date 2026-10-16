import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/slots.dart';
import '../../models.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../notifications.dart';
import 'export_sheet.dart';
import 'notifications_screen.dart';
import 'reviews_screen.dart';
import 'shop_days_screen.dart';

/// Informazioni del locale, regole di prenotazione, promemoria e amministratori.
class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key});

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  late ShopSettings _s;
  final _c = <String, TextEditingController>{};
  List<String> _admins = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final state = AppScope.read(context);
    _s = state.settings.copy();
    _c['name'] = TextEditingController(text: _s.name);
    _c['tagline'] = TextEditingController(text: _s.tagline);
    _c['address'] = TextEditingController(text: _s.address);
    _c['maps'] = TextEditingController(text: _s.mapsUrl);
    _c['phone'] = TextEditingController(text: _s.phone);
    _c['whatsapp'] = TextEditingController(text: _s.whatsapp);
    _c['instagram'] = TextEditingController(text: _s.instagram);
    _c['step'] = TextEditingController(text: '${_s.slotStepMin}');
    _c['days'] = TextEditingController(text: '${_s.bookingDaysAhead}');
    _c['cancel'] = TextEditingController(text: '${_s.minCancelHours}');
    _c['review'] = TextEditingController(text: _s.googleReviewUrl);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAdmins());
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadAdmins() async {
    try {
      final list = await AppScope.read(context).backend.adminEmails();
      if (mounted) setState(() => _admins = list);
    } catch (_) {}
  }

  Future<void> _save() async {
    _s
      ..name = _c['name']!.text.trim()
      ..tagline = _c['tagline']!.text.trim()
      ..address = _c['address']!.text.trim()
      ..mapsUrl = _c['maps']!.text.trim()
      ..phone = _c['phone']!.text.trim()
      ..whatsapp = _c['whatsapp']!.text.trim()
      ..instagram = _c['instagram']!.text.trim().replaceAll('@', '')
      ..slotStepMin = int.parse(_c['step']!.text)
      ..bookingDaysAhead = int.parse(_c['days']!.text)
      ..minCancelHours = int.parse(_c['cancel']!.text)
      ..googleReviewUrl = _c['review']!.text.trim();
    setState(() => _saving = true);
    final state = AppScope.read(context);
    try {
      await state.backend.saveSettings(_s);
      await state.refreshCatalog();
      if (mounted) showMessage(context, 'Impostazioni salvate');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _addAdmin() async {
    final ctrl = TextEditingController();
    final email = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Nuovo amministratore'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'Email dell\'account'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Annulla')),
          FilledButton(onPressed: () => Navigator.pop(c, ctrl.text.trim()), child: const Text('Aggiungi')),
        ],
      ),
    );
    if (email == null || !email.contains('@') || !mounted) return;
    try {
      await AppScope.read(context).backend.addAdminEmail(email);
      await _loadAdmins();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _removeAdmin(String email) async {
    final ok = await confirmDialog(
      context,
      title: 'Rimuovere amministratore?',
      message: email,
      confirm: 'Rimuovi',
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      await AppScope.read(context).backend.removeAdminEmail(email);
      await _loadAdmins();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Widget _field(String key, String label, {IconData? icon, int lines = 1, TextInputType? type, String? hint}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          controller: _c[key],
          maxLines: lines,
          keyboardType: type,
          decoration: InputDecoration(labelText: label, hintText: hint, prefixIcon: icon == null ? null : Icon(icon)),
        ),
      );

  Widget _number(String key, String label, String suffix, int min, int max) => Expanded(
    child: TextFormField(
      controller: _c[key],
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(labelText: label, suffixText: suffix),
      validator: (v) {
        final n = int.tryParse(v ?? '');
        return n == null || n < min || n > max ? '$min–$max' : null;
      },
    ),
  );

  /// Annulla le modifiche non salvate nei campi.
  void _resetFields() {
    _c['name']!.text = _s.name;
    _c['tagline']!.text = _s.tagline;
    _c['address']!.text = _s.address;
    _c['maps']!.text = _s.mapsUrl;
    _c['phone']!.text = _s.phone;
    _c['whatsapp']!.text = _s.whatsapp;
    _c['instagram']!.text = _s.instagram;
    _c['step']!.text = '${_s.slotStepMin}';
    _c['days']!.text = '${_s.bookingDaysAhead}';
    _c['cancel']!.text = '${_s.minCancelHours}';
    _c['review']!.text = _s.googleReviewUrl;
  }

  /// Sezione modificabile in un pannello: la pagina resta senza scorrimento.
  Future<void> _editSection(String title, List<Widget> fields) async {
    final form = GlobalKey<FormState>();
    final saved = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 460,
          child: Form(
            key: form,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: fields),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annulla')),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) Navigator.pop(c, true);
            },
            child: const Text('Salva'),
          ),
        ],
      ),
    );
    if (saved == true) {
      await _save();
    } else {
      _resetFields();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final myEmail = state.profile?.email.toLowerCase();
    final today = dayOnly(DateTime.now());
    final nextDay = state.shopDays.where((d) => !d.day.isBefore(today)).firstOrNull;

    Widget tile(IconData icon, String title, String subtitle, {VoidCallback? onTap, Widget? trailing}) => GlassCard(
      margin: const EdgeInsets.only(bottom: 10),
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, color: AppColors.silver),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
                ),
              ],
            ),
          ),
          trailing ?? const Icon(Icons.chevron_right, color: AppColors.muted),
        ],
      ),
    );

    // voci a grandezza normale, raggruppate; su tablet e computer in due colonne
    Widget group(String title, List<Widget> tiles) => LayoutBuilder(
      builder: (context, c) {
        final two = c.maxWidth >= 700;
        final w = two ? (c.maxWidth - 12) / 2 : c.maxWidth;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionTitle(title),
            Wrap(
              spacing: 12,
              children: [for (final t in tiles) SizedBox(width: w, child: t)],
            ),
          ],
        );
      },
    );

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        ResponsiveCenter(
          maxWidth: 900,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              group('Negozio', [
                tile(
                  Icons.storefront_outlined,
                  'Il locale',
                  '${_s.name} · ${_s.address}',
                  onTap: () => _editSection('Il locale', [
                    _field('name', 'Nome', icon: Icons.storefront_outlined),
                    _field('tagline', 'Sottotitolo', icon: Icons.short_text),
                    _field('address', 'Indirizzo', icon: Icons.location_on_outlined),
                    _field('maps', 'Link Google Maps', icon: Icons.map_outlined, type: TextInputType.url),
                    _field('phone', 'Telefono', icon: Icons.call_outlined, type: TextInputType.phone),
                    _field('whatsapp', 'WhatsApp del negozio', icon: Icons.chat_outlined, type: TextInputType.phone),
                    _field(
                      'instagram',
                      'Instagram (mostrato nella home)',
                      icon: Icons.camera_alt_outlined,
                      hint: 'nomeutente',
                    ),
                    _field(
                      'review',
                      'Link recensioni Google',
                      icon: Icons.star_outline,
                      type: TextInputType.url,
                      hint: 'https://g.page/r/…/review',
                    ),
                  ]),
                ),
                tile(
                  Icons.event_note_outlined,
                  'Prenotazioni',
                  'Orari ogni ${_s.slotStepMin} min · prenotabile fino a ${_s.bookingDaysAhead} giorni · '
                      'annullabile fino a ${_s.minCancelHours} ore prima',
                  onTap: () => _editSection('Prenotazioni', [
                    Row(children: [_number('step', 'Intervallo tra gli orari', 'min', 5, 120)]),
                    const SizedBox(height: 12),
                    Row(children: [_number('days', 'Prenotabile fino a', 'giorni', 1, 365)]),
                    const SizedBox(height: 12),
                    Row(children: [_number('cancel', 'Annullabile fino a', 'ore prima', 0, 72)]),
                  ]),
                ),
                tile(
                  Icons.door_front_door_outlined,
                  'Chiusure e orari speciali',
                  nextDay == null
                      ? 'Ferie, festività e giorni con orario diverso'
                      : 'Prossimo: ${fmtDayShort(nextDay.day)} · '
                            '${nextDay.closed ? 'chiuso' : '${formatTime(nextDay.open!)}–${formatTime(nextDay.close!)}'}',
                  onTap: () => Navigator.of(context).push(fadeRoute(const ShopDaysScreen())),
                ),
              ]),
              group('Clienti', [
                tile(
                  Icons.notifications_active_outlined,
                  'Notifiche',
                  () {
                    final n = NotifSettings.fromJson(state.settings.notifications);
                    final on = notifTypes.where((t) => n.enabled(t.kind)).length;
                    return '$on di ${notifTypes.length} attive · testi e orari modificabili';
                  }(),
                  onTap: () async {
                    await Navigator.of(context).push(fadeRoute(const NotificationsScreen()));
                    if (mounted) setState(() => _s = AppScope.read(context).settings.copy());
                  },
                ),
                tile(
                  Icons.chat_outlined,
                  'Promemoria WhatsApp',
                  '24 ore e 1 ora prima di ogni appuntamento',
                  trailing: Switch(
                    value: _s.remindersEnabled,
                    onChanged: _saving
                        ? null
                        : (v) {
                            setState(() => _s.remindersEnabled = v);
                            _save();
                          },
                  ),
                ),
                tile(
                  Icons.star_outline,
                  'Valutazioni dei clienti',
                  'Voti dopo il taglio e commenti privati',
                  onTap: () => Navigator.of(context).push(fadeRoute(const ReviewsScreen())),
                ),
              ]),
              group('Strumenti', [
                tile(
                  Icons.file_download_outlined,
                  'Esporta dati',
                  'Clienti e incassi in un file per Excel (anche per il commercialista)',
                  onTap: () => showExportSheet(context),
                ),
              ]),
              SectionTitle(
                'Amministratori',
                trailing: TextButton.icon(
                  onPressed: _addAdmin,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Aggiungi'),
                ),
              ),
              for (final e in _admins)
                GlassCard(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
                  child: Row(
                    children: [
                      const Icon(Icons.admin_panel_settings_outlined, color: AppColors.muted),
                      const SizedBox(width: 12),
                      Expanded(child: Text(e, overflow: TextOverflow.ellipsis)),
                      if (e != myEmail)
                        IconButton(onPressed: () => _removeAdmin(e), icon: const Icon(Icons.close))
                      else
                        const Padding(
                          padding: EdgeInsets.all(12),
                          child: Text('tu', style: TextStyle(color: AppColors.muted)),
                        ),
                    ],
                  ),
                ),
              if (state.backend.isDemo) ...[
                const SizedBox(height: 16),
                const Text(
                  'Modalità demo: i dati sono locali e si azzerano alla chiusura dell\'app.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.warning, fontSize: 12.5),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
