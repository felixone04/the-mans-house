import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../notifications.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// Notifiche (area riservata): ogni tipo si attiva, si disattiva e si
/// modifica (titolo, testo, quando arriva), con l'anteprima com'e' sul telefono.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late NotifSettings _n = NotifSettings.fromJson(AppScope.read(context).settings.notifications);

  Future<void> _save(NotifSettings n, {String? message}) async {
    final state = AppScope.read(context);
    final s = state.settings.copy()..notifications = n.toJson();
    try {
      await state.backend.saveSettings(s);
      await state.refreshCatalog();
      if (!mounted) return;
      setState(() => _n = n);
      if (message != null) showMessage(context, message);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  void _toggle(NotifType t, bool on) {
    final n = _n.copy();
    n.prefs.putIfAbsent(t.key, NotifPref.new).enabled = on;
    setState(() => _n = n); // subito, senza attendere il salvataggio
    _save(n);
  }

  Future<void> _edit(NotifType t) async {
    final pref = await Navigator.of(context).push<NotifPref>(
      fadeRoute(_NotificationEditor(type: t, settings: _n)),
    );
    if (pref == null || !mounted) return;
    final n = _n.copy();
    n.prefs[t.key] = pref;
    await _save(n, message: 'Notifica salvata');
  }

  Widget _row(NotifType t) {
    final on = _n.enabled(t.kind);
    final c = _n.build(t.kind, notifSample);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                    Text(
                      _when(t, _n),
                      style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              Switch(value: on, onChanged: (v) => _toggle(t, v)),
            ],
          ),
          const SizedBox(height: 6),
          Opacity(
            opacity: on ? 1 : 0.45,
            child: NotificationCard(
              type: t,
              title: c?.title ?? fillNotif(_n.title(t.kind), notifSample),
              body: c?.body ?? fillNotif(_n.body(t.kind), notifSample),
              onTap: () => _edit(t),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AppScaffold(
    title: 'Notifiche',
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          ResponsiveCenter(
            maxWidth: 640,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 6),
                const Text(
                  'Tocca una notifica per cambiare testo e orario. Con l\'interruttore la attivi o la spegni.',
                  style: TextStyle(color: AppColors.silver, fontSize: 13, height: 1.4),
                ),
                const SectionTitle('Per i clienti'),
                for (final t in notifTypes.where((t) => !t.forShop)) _row(t),
                const SectionTitle('Per il negozio'),
                for (final t in notifTypes.where((t) => t.forShop)) _row(t),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// "1 giorno prima", "il giorno prima alle 18:00", "1 ora dopo la fine", ...
String _when(NotifType t, NotifSettings n) {
  final o = n.offset(t.kind);
  String dur(int m) => m % (24 * 60) == 0 && m > 0
      ? (m == 24 * 60 ? '1 giorno' : '${m ~/ (24 * 60)} giorni')
      : m % 60 == 0
      ? (m == 60 ? '1 ora' : '${m ~/ 60} ore')
      : '$m minuti';
  return switch (t.timing) {
    NotifTiming.before => '${dur(o)} prima dell\'appuntamento',
    NotifTiming.dayBeforeAt =>
      'Il giorno prima alle ${(o ~/ 60).toString().padLeft(2, '0')}:${(o % 60).toString().padLeft(2, '0')}',
    NotifTiming.afterEnd => '${dur(o)} dopo la fine',
    null => t.description,
  };
}

class _NotificationEditor extends StatefulWidget {
  const _NotificationEditor({required this.type, required this.settings});
  final NotifType type;
  final NotifSettings settings;

  @override
  State<_NotificationEditor> createState() => _NotificationEditorState();
}

class _NotificationEditorState extends State<_NotificationEditor> {
  NotifType get t => widget.type;
  late bool _on = widget.settings.enabled(t.kind);
  late final _title = TextEditingController(text: widget.settings.title(t.kind));
  late final _body = TextEditingController(text: widget.settings.body(t.kind));
  late int _offset = widget.settings.offset(t.kind);
  late final _offsetCtrl = TextEditingController(text: '${_offsetForField()}');
  final _titleFocus = FocusNode();
  final _bodyFocus = FocusNode();
  TextEditingController? _last; // ultimo campo usato: li' si inseriscono i segnaposto

  @override
  void initState() {
    super.initState();
    _titleFocus.addListener(() {
      if (_titleFocus.hasFocus) _last = _title;
    });
    _bodyFocus.addListener(() {
      if (_bodyFocus.hasFocus) _last = _body;
    });
  }

  @override
  void dispose() {
    for (final c in [_title, _body, _offsetCtrl]) {
      c.dispose();
    }
    _titleFocus.dispose();
    _bodyFocus.dispose();
    super.dispose();
  }

  /// Promemoria in ore se tonde, altrimenti minuti; conferma presenza in ora del giorno.
  late bool _inHours = t.timing != NotifTiming.dayBeforeAt && _offset % 60 == 0 && _offset >= 60;
  int _offsetForField() => _inHours ? _offset ~/ 60 : _offset;

  void _insert(String key) {
    final c = _last ?? _body;
    final sel = c.selection;
    final text = c.text;
    final at = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : text.length;
    final token = '{$key}';
    c.value = TextEditingValue(
      text: text.replaceRange(at, end, token),
      selection: TextSelection.collapsed(offset: at + token.length),
    );
    setState(() {});
  }

  void _reset() => setState(() {
    _title.text = t.title;
    _body.text = t.body;
    _offset = t.defaultOffset;
    _inHours = t.timing != NotifTiming.dayBeforeAt && _offset % 60 == 0 && _offset >= 60;
    _offsetCtrl.text = '${_offsetForField()}';
  });

  Future<void> _pickTime() async {
    final v = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _offset ~/ 60, minute: _offset % 60),
    );
    if (v != null) setState(() => _offset = v.hour * 60 + v.minute);
  }

  void _save() {
    if (_title.text.trim().isEmpty) return showMessage(context, 'Scrivi il titolo', error: true);
    Navigator.pop(
      context,
      NotifPref(
        enabled: _on,
        title: _title.text.trim() == t.title ? null : _title.text.trim(),
        body: _body.text.trim() == t.body ? null : _body.text.trim(),
        offset: _offset == t.defaultOffset ? null : _offset,
      ),
    );
  }

  Widget _timing() {
    switch (t.timing) {
      case null:
        return const SizedBox.shrink();
      case NotifTiming.dayBeforeAt:
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.schedule),
          title: const Text('Il giorno prima alle'),
          trailing: OutlinedButton(
            onPressed: _pickTime,
            child: Text(
              '${(_offset ~/ 60).toString().padLeft(2, '0')}:${(_offset % 60).toString().padLeft(2, '0')}',
            ),
          ),
        );
      case NotifTiming.before:
      case NotifTiming.afterEnd:
        final hours = _inHours;
        return Row(
          children: [
            Expanded(
              child: TextField(
                controller: _offsetCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: t.timing == NotifTiming.before ? 'Quanto prima' : 'Quanto dopo la fine',
                  suffixText: hours ? 'ore' : 'minuti',
                ),
                onChanged: (v) {
                  final n = int.tryParse(v);
                  if (n != null && n > 0) setState(() => _offset = hours ? n * 60 : n);
                },
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => setState(() {
                // passa da ore a minuti e viceversa mantenendo il valore
                if (!hours) _offset = (_offset / 60).ceil() * 60;
                _inHours = !hours;
                _offsetCtrl.text = '${_offsetForField()}';
              }),
              child: Text(hours ? 'in minuti' : 'in ore'),
            ),
          ],
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = NotifSettings({
      t.key: NotifPref(title: _title.text, body: _body.text, offset: _offset),
    });
    return AppScaffold(
      title: t.label,
      actions: [TextButton(onPressed: _save, child: const Text('Salva'))],
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            ResponsiveCenter(
              maxWidth: 640,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // anteprima com'e' sul telefono, con dati di esempio
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: AppColors.concrete, borderRadius: BorderRadius.circular(18)),
                    child: Opacity(
                      opacity: _on ? 1 : 0.45,
                      child: NotificationCard(
                        type: t,
                        title: fillNotif(preview.title(t.kind), notifSample),
                        body: fillNotif(preview.body(t.kind), notifSample),
                      ),
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _on,
                    onChanged: (v) => setState(() => _on = v),
                    title: const Text('Attiva'),
                    subtitle: Text(t.description),
                  ),
                  _timing(),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _title,
                    focusNode: _titleFocus,
                    decoration: const InputDecoration(labelText: 'Titolo'),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _body,
                    focusNode: _bodyFocus,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(labelText: 'Testo'),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Tocca per inserire nel testo:',
                    style: TextStyle(color: AppColors.silver, fontSize: 12.5),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final p in t.placeholders)
                        ActionChip(
                          label: Text('{$p}'),
                          tooltip: 'Es. ${notifSample[p] ?? ''}',
                          onPressed: () => _insert(p),
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  FilledButton(onPressed: _save, child: const Text('SALVA')),
                  const SizedBox(height: 6),
                  TextButton.icon(
                    onPressed: _reset,
                    icon: const Icon(Icons.restart_alt),
                    label: const Text('Ripristina il testo originale'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
