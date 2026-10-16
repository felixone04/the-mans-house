import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';
import '../notifications.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Chiede il voto dopo il taglio, una volta sola per appuntamento: con 4-5
/// stelle invita a lasciare la recensione su Google, sotto le 4 il commento
/// resta privato e lo legge solo il negozio.
class ReviewPrompter extends StatefulWidget {
  const ReviewPrompter({super.key});

  @override
  State<ReviewPrompter> createState() => _ReviewPrompterState();
}

class _ReviewPrompterState extends State<ReviewPrompter> {
  static const _skipKey = 'review_skipped';
  static bool _askedThisSession = false; // al massimo una richiesta per apertura

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = AppScope.of(context);
    if (_askedThisSession || !state.isSignedIn || state.isAdmin) return;
    final n = NotifSettings.fromJson(state.settings.notifications);
    final now = DateTime.now();
    final due = state.myAppointments.where((a) => needsReview(a, n, now)).toList()
      ..sort((a, b) => b.end.compareTo(a.end));
    if (due.isEmpty) return;
    _askedThisSession = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _ask(due.first));
  }

  Future<void> _ask(Appointment a) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if ((prefs.getStringList(_skipKey) ?? const []).contains(a.id)) return;
    } catch (_) {
      // senza memoria locale si chiede comunque
    }
    if (!mounted) return;
    final done = await showReviewSheet(context, a);
    if (done) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_skipKey, [...?prefs.getStringList(_skipKey), a.id]);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// Ritorna true se il voto e' stato inviato.
Future<bool> showReviewSheet(BuildContext context, Appointment a) async {
  final sent = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: 520),
    builder: (_) => _ReviewSheet(appointment: a),
  );
  return sent ?? false;
}

class _ReviewSheet extends StatefulWidget {
  const _ReviewSheet({required this.appointment});
  final Appointment appointment;

  @override
  State<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<_ReviewSheet> {
  int _stars = 0;
  bool _sent = false;
  bool _busy = false;
  final _comment = TextEditingController();

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() => _busy = true);
    final state = AppScope.read(context);
    try {
      await state.backend.submitReview(widget.appointment.id, _stars, comment: _comment.text);
      await state.refreshAppointments();
      if (!mounted) return;
      setState(() => _sent = true);
      if (_stars < 4) {
        Navigator.pop(context, true);
        showMessage(context, 'Grazie: il tuo messaggio è arrivato al negozio');
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.appointment;
    final reviewUrl = AppScope.of(context).settings.googleReviewUrl;
    final happy = _stars >= 4;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(22, 4, 22, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 52,
                height: 52,
                decoration: const BoxDecoration(color: Color(0xFFEEEDFE), shape: BoxShape.circle),
                child: const Icon(Icons.star_outline, color: Color(0xFF3C3489), size: 28),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              a.barberName.isEmpty ? 'Com\'è andata?' : 'Com\'è andata con ${a.barberName}?',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            Text(
              '${a.serviceName} · ${fmtDayShort(a.start).toLowerCase()}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.silver, fontSize: 13.5),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 1; i <= 5; i++)
                  IconButton(
                    tooltip: '$i ${i == 1 ? 'stella' : 'stelle'}',
                    iconSize: 40,
                    onPressed: _sent ? null : () => setState(() => _stars = i),
                    icon: Icon(
                      i <= _stars ? Icons.star_rounded : Icons.star_outline_rounded,
                      color: i <= _stars ? const Color(0xFFE0A030) : AppColors.muted,
                    ),
                  ),
              ],
            ),
            if (_stars > 0 && !happy) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _comment,
                minLines: 2,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Cosa possiamo migliorare?',
                  helperText: 'Lo legge solo il negozio',
                ),
              ),
            ],
            if (happy && _sent) ...[
              const SizedBox(height: 6),
              const Text(
                'Grazie! Ci aiuti con una recensione su Google? Bastano due righe.',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w700, height: 1.4),
              ),
            ],
            const SizedBox(height: 16),
            if (happy && _sent && reviewUrl.isNotEmpty)
              FilledButton.icon(
                onPressed: () {
                  openUrl(context, reviewUrl);
                  Navigator.pop(context, true);
                },
                icon: const Icon(Icons.rate_review_outlined),
                label: const Text('Scrivi la recensione su Google'),
              )
            else if (!_sent)
              FilledButton(
                onPressed: _stars == 0 || _busy ? null : _send,
                child: Text(_stars == 0 ? 'Scegli le stelle' : 'Invia'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context, _sent),
              child: Text(_sent ? 'Chiudi' : 'Non ora'),
            ),
          ],
        ),
      ),
    );
  }
}
