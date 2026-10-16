import 'dart:async';

import 'package:flutter/material.dart';

import '../notifications.dart';

final _queue = <(NotifContent, VoidCallback?)>[];
bool _showing = false;

/// Mostra la notifica in alto dentro l'app (stile essenziale), una alla volta.
void showNotifBanner(BuildContext context, NotifContent c, {VoidCallback? onTap}) {
  _queue.add((c, onTap));
  if (!_showing) _next(Overlay.of(context, rootOverlay: true));
}

void _next(OverlayState overlay) {
  if (_queue.isEmpty || !overlay.mounted) {
    _showing = false;
    return;
  }
  _showing = true;
  final (c, onTap) = _queue.removeAt(0);
  late OverlayEntry entry;
  var closed = false;
  void close() {
    if (closed) return;
    closed = true;
    entry.remove();
    Future<void>.delayed(const Duration(milliseconds: 250), () => _next(overlay));
  }

  entry = OverlayEntry(
    builder: (_) => _Banner(
      content: c,
      onTap: () {
        close();
        onTap?.call();
      },
      onDone: close,
    ),
  );
  overlay.insert(entry);
}

class _Banner extends StatefulWidget {
  const _Banner({required this.content, required this.onTap, required this.onDone});
  final NotifContent content;
  final VoidCallback onTap;
  final VoidCallback onDone;

  @override
  State<_Banner> createState() => _BannerState();
}

class _BannerState extends State<_Banner> with SingleTickerProviderStateMixin {
  late final _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 260))..forward();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(seconds: 5), _hide);
  }

  Future<void> _hide() async {
    _timer?.cancel();
    if (!mounted) return;
    await _anim.reverse();
    widget.onDone();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Positioned(
    top: 0,
    left: 0,
    right: 0,
    child: SafeArea(
      bottom: false,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
            child: SlideTransition(
              position: Tween(begin: const Offset(0, -1.2), end: Offset.zero).animate(
                CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic),
              ),
              child: Dismissible(
                key: const ValueKey('notif'),
                direction: DismissDirection.up,
                onDismissed: (_) => widget.onDone(),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 18)],
                  ),
                  child: NotificationCard(
                    type: widget.content.type,
                    title: widget.content.title,
                    body: widget.content.body,
                    onTap: widget.onTap,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
