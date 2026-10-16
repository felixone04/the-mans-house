import 'package:flutter/material.dart';

import '../../models.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// Voti dei clienti dopo il taglio, con i commenti privati (area riservata).
class ReviewsScreen extends StatefulWidget {
  const ReviewsScreen({super.key});

  @override
  State<ReviewsScreen> createState() => _ReviewsScreenState();
}

class _ReviewsScreenState extends State<ReviewsScreen> {
  List<Appointment> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final list = await AppScope.read(context).backend.fetchReviews();
      if (mounted) setState(() => _items = list);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _stars(int n, {double size = 16}) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var i = 1; i <= 5; i++)
        Icon(
          i <= n ? Icons.star_rounded : Icons.star_outline_rounded,
          size: size,
          color: i <= n ? const Color(0xFFE0A030) : AppColors.muted,
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final avg = _items.isEmpty ? 0.0 : _items.fold<int>(0, (s, a) => s + a.reviewStars!) / _items.length;
    final low = _items.where((a) => a.reviewStars! < 4).length;
    return AppScaffold(
      title: 'Valutazioni',
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.only(bottom: 32),
                children: [
                  ResponsiveCenter(
                    maxWidth: 640,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 8),
                        GlassCard(
                          child: Row(
                            children: [
                              Text(
                                _items.isEmpty ? '–' : avg.toStringAsFixed(1).replaceAll('.', ','),
                                style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _stars(avg.round(), size: 20),
                                    Text(
                                      '${_items.length} ${_items.length == 1 ? 'voto' : 'voti'}'
                                      '${low > 0 ? ' · $low con meno di 4 stelle' : ''}',
                                      style: const TextStyle(color: AppColors.silver, fontSize: 13),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Con 4-5 stelle il cliente viene invitato a scrivere la recensione su Google; '
                          'sotto le 4 il commento resta privato e lo trovi qui.',
                          style: TextStyle(color: AppColors.muted, fontSize: 12.5, height: 1.4),
                        ),
                        if (_items.isEmpty)
                          const Padding(
                            padding: EdgeInsets.only(top: 40),
                            child: EmptyState(icon: Icons.star_outline, text: 'Ancora nessun voto'),
                          ),
                        const SizedBox(height: 10),
                        for (final a in _items)
                          GlassCard(
                            margin: const EdgeInsets.only(bottom: 10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    _stars(a.reviewStars!),
                                    const Spacer(),
                                    Text(
                                      fmtDayShort(a.start),
                                      style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  a.customerName.isEmpty ? 'Cliente' : a.customerName,
                                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                                ),
                                Text(
                                  '${a.serviceName}${a.barberName.isEmpty ? '' : ' · con ${a.barberName}'}',
                                  style: const TextStyle(color: AppColors.silver, fontSize: 13),
                                ),
                                if (a.reviewComment.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text('“${a.reviewComment}”', style: const TextStyle(fontStyle: FontStyle.italic)),
                                ],
                              ],
                            ),
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
