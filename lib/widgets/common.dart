import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models.dart';
import '../theme.dart';

// ---------------------------------------------------------------------------
// Formattazione
// ---------------------------------------------------------------------------

String capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

final _price = NumberFormat.currency(locale: 'it_IT', symbol: '€', decimalDigits: 2);
String fmtPrice(double v) => v == v.roundToDouble() ? '€ ${v.toStringAsFixed(0)}' : _price.format(v);
String fmtTime(DateTime d) => DateFormat.Hm('it_IT').format(d);
String fmtDayLong(DateTime d) => capitalize(DateFormat('EEEE d MMMM', 'it_IT').format(d));
String fmtDayShort(DateTime d) => capitalize(DateFormat('EEE d MMM', 'it_IT').format(d));
String fmtDuration(int min) => min < 60 ? '$min min' : '${min ~/ 60} h${min % 60 == 0 ? '' : ' ${min % 60} min'}';

const weekdayNames = ['Lunedì', 'Martedì', 'Mercoledì', 'Giovedì', 'Venerdì', 'Sabato', 'Domenica'];

// ---------------------------------------------------------------------------
// Azioni esterne
// ---------------------------------------------------------------------------

Future<void> openUrl(BuildContext context, String url) async {
  final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) showMessage(context, 'Impossibile aprire il link');
}

Future<void> callPhone(BuildContext context, String phone) => openUrl(context, 'tel:${normalizePhone(phone)}');

Future<void> openWhatsApp(BuildContext context, String phone, [String text = '']) {
  final number = normalizePhone(phone).replaceAll('+', '');
  return openUrl(context, 'https://wa.me/$number${text.isEmpty ? '' : '?text=${Uri.encodeComponent(text)}'}');
}

void showMessage(BuildContext context, String text, {bool error = false, String? actionLabel, VoidCallback? onAction}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        action: onAction == null
            ? null
            : SnackBarAction(label: actionLabel ?? 'Annulla', textColor: AppColors.white, onPressed: onAction),
        content: Row(
          children: [
            Icon(
              error ? Icons.error_outline : Icons.check_circle_outline,
              color: error ? AppColors.danger : AppColors.success,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
}

void showError(BuildContext context, Object e) =>
    showMessage(context, e.toString().replaceFirst('Exception: ', ''), error: true);

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirm = 'Conferma',
  bool destructive = false,
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Indietro')),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(backgroundColor: AppColors.danger, minimumSize: const Size(64, 44))
              : FilledButton.styleFrom(minimumSize: const Size(64, 44)),
          onPressed: () => Navigator.pop(c, true),
          child: Text(confirm),
        ),
      ],
    ),
  );
  return r ?? false;
}

// ---------------------------------------------------------------------------
// Layout
// ---------------------------------------------------------------------------

/// Sfondo nero sfumato al grigio usato in tutta l'app.
class AppBackground extends StatelessWidget {
  const AppBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(gradient: AppColors.backgroundGradient),
    child: Stack(
      fit: StackFit.expand,
      children: [
        // vignettatura + grana leggera, come una parete di bottega
        const IgnorePointer(
          child: RepaintBoundary(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, -0.35),
                  radius: 1.15,
                  colors: [Color(0x0FFFFFFF), Color(0x00000000), Color(0x66000000)],
                  stops: [0, 0.55, 1],
                ),
              ),
              child: CustomPaint(painter: _GrainPainter.instance),
            ),
          ),
        ),
        child,
      ],
    ),
  );
}

class _GrainPainter extends CustomPainter {
  const _GrainPainter();
  static const instance = _GrainPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = Random(11);
    final light = Paint()..color = const Color(0x09FFFFFF);
    final dark = Paint()..color = const Color(0x12000000);
    final count = (size.width * size.height / 90).clamp(0, 30000).toInt();
    for (var i = 0; i < count; i++) {
      canvas.drawRect(
        Rect.fromLTWH(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height, 1, 1),
        i.isEven ? light : dark,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Divisore decorativo: linea — forbici — linea.
class Ornament extends StatelessWidget {
  const Ornament({super.key, this.width = 180, this.icon = Icons.content_cut});
  final double width;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    Widget line(bool left) => Expanded(
      child: Container(
        height: 1,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.white.withValues(alpha: left ? 0 : 0.45),
              AppColors.white.withValues(alpha: left ? 0.45 : 0),
            ],
          ),
        ),
      ),
    );
    return SizedBox(
      width: width,
      child: Row(
        children: [
          line(true),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Transform.rotate(
              angle: -pi / 2,
              child: Icon(icon, size: 14, color: AppColors.silver),
            ),
          ),
          line(false),
        ],
      ),
    );
  }
}

/// Titolo di sezione in stile insegna, con ornamento.
class ShopHeading extends StatelessWidget {
  const ShopHeading(this.title, {super.key, this.subtitle});
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4, bottom: 18),
    child: Column(
      children: [
        Text(
          title.toUpperCase(),
          textAlign: TextAlign.center,
          style: slab(size: 20, weight: FontWeight.w600, spacing: 3),
        ),
        const SizedBox(height: 8),
        const Ornament(width: 150),
        if (subtitle != null) ...[
          const SizedBox(height: 8),
          Text(
            subtitle!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted, fontSize: 13),
          ),
        ],
      ],
    ),
  );
}

/// Palo da barbiere animato (strisce diagonali monocromatiche).
class BarberPole extends StatefulWidget {
  const BarberPole({super.key, this.width = 140, this.height = 8, this.animate = true});
  final double width;
  final double height;
  final bool animate;

  @override
  State<BarberPole> createState() => _BarberPoleState();
}

class _BarberPoleState extends State<BarberPole> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void initState() {
    super.initState();
    if (widget.animate) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
    width: widget.width,
    height: widget.height,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(widget.height),
      border: Border.all(color: AppColors.white.withValues(alpha: 0.5), width: 0.8),
    ),
    clipBehavior: Clip.antiAlias,
    child: AnimatedBuilder(
      animation: _c,
      builder: (_, _) => CustomPaint(painter: _PolePainter(_c.value)),
    ),
  );
}

class _PolePainter extends CustomPainter {
  _PolePainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    const stripe = 9.0;
    final colors = [AppColors.white, AppColors.black, AppColors.muted, AppColors.black];
    final period = stripe * colors.length;
    final shift = t * period;
    canvas.drawRect(Offset.zero & size, Paint()..color = AppColors.black);
    for (var x = -period * 2 + shift; x < size.width + size.height; x += stripe) {
      final i = (((x - shift) / stripe).round()) % colors.length;
      final path = Path()
        ..moveTo(x, size.height)
        ..lineTo(x + size.height, 0)
        ..lineTo(x + size.height + stripe, 0)
        ..lineTo(x + stripe, size.height)
        ..close();
      canvas.drawPath(path, Paint()..color = colors[i < 0 ? i + colors.length : i]);
    }
  }

  @override
  bool shouldRepaint(covariant _PolePainter old) => old.t != t;
}

/// Icona di Instagram (quadrato arrotondato, obiettivo e flash), disegnata
/// perche' le icone Material non la includono.
class InstagramIcon extends StatelessWidget {
  const InstagramIcon({super.key, this.size = 24, this.color = AppColors.white});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) =>
      SizedBox.square(dimension: size, child: CustomPaint(painter: _InstagramPainter(color)));
}

class _InstagramPainter extends CustomPainter {
  _InstagramPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.085;
    final inset = s * 0.1;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(inset, inset, s - 2 * inset, s - 2 * inset), Radius.circular(s * 0.24)),
      stroke,
    );
    canvas.drawCircle(Offset(s / 2, s / 2), s * 0.19, stroke);
    canvas.drawCircle(Offset(s * 0.72, s * 0.28), s * 0.05, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _InstagramPainter old) => old.color != color;
}

/// Puntini di riempimento tra nome e prezzo, come nei listini da bottega.
class DottedLeader extends StatelessWidget {
  const DottedLeader({super.key});

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 12,
    child: CustomPaint(painter: _DotsPainter(), size: const Size(double.infinity, 12)),
  );
}

class _DotsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = AppColors.muted.withValues(alpha: 0.7);
    for (var x = 4.0; x < size.width - 4; x += 6) {
      canvas.drawCircle(Offset(x, size.height - 2), 0.9, p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Icona del servizio in base al nome.
class ServiceIcon extends StatelessWidget {
  const ServiceIcon(this.name, {super.key, this.size = 40, this.selected = false});
  final String name;
  final double size;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final n = name.toLowerCase();
    final fg = selected ? AppColors.black : AppColors.white;
    Widget icon;
    if (n.contains('barba') || n.contains('beard')) {
      icon = ColorFiltered(
        colorFilter: ColorFilter.mode(fg, BlendMode.srcIn),
        child: Image.asset('assets/images/logo_mark.png', width: size * 0.62),
      );
    } else {
      final data = n.contains('bambin')
          ? Icons.child_care_outlined
          : n.contains('shampoo') || n.contains('lavaggio')
          ? Icons.water_drop_outlined
          : n.contains('rasatura') || n.contains('panno')
          ? Icons.spa_outlined
          : n.contains('colore') || n.contains('tinta')
          ? Icons.palette_outlined
          : Icons.content_cut;
      icon = Icon(data, size: size * 0.46, color: fg);
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? AppColors.white : Colors.transparent,
        border: Border.all(color: AppColors.white.withValues(alpha: selected ? 1 : 0.3)),
      ),
      alignment: Alignment.center,
      child: icon,
    );
  }
}

/// Centra il contenuto con larghezza massima: la grafica resta identica su
/// telefono, tablet e computer.
class ResponsiveCenter extends StatelessWidget {
  const ResponsiveCenter({
    super.key,
    required this.child,
    this.maxWidth = 560,
    this.padding,
    this.alignment = Alignment.topCenter,
  });
  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry? padding;

  /// Su schermi larghi: centrato (predefinito) o allineato a sinistra.
  final Alignment alignment;

  @override
  Widget build(BuildContext context) => Align(
    alignment: alignment,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Padding(padding: padding ?? const EdgeInsets.symmetric(horizontal: 20), child: child),
    ),
  );
}

/// Pagina senza scorrimento: il contenuto sta sempre nello schermo e sui
/// telefoni piu' piccoli si riduce leggermente invece di scorrere.
/// Solo con la tastiera aperta diventa scorrevole, per raggiungere i campi.
/// Il [child] deve essere una Column con mainAxisSize.min (niente Expanded).
class FitBody extends StatefulWidget {
  const FitBody({super.key, required this.child, this.maxWidth = 560, this.alignment = Alignment.center});

  final Widget child;
  final double maxWidth;
  final Alignment alignment;

  @override
  State<FitBody> createState() => _FitBodyState();
}

class _FitBodyState extends State<FitBody> {
  // Conserva lo stato dei campi (testo, focus) quando si passa dalla vista
  // adattata a quella scorrevole: senza, all'apertura della tastiera il campo
  // veniva ricreato, perdeva il focus e la tastiera si richiudeva.
  final _contentKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        // Lo Scaffold toglie la tastiera dal MediaQuery del body (si limita a
        // rimpicciolirlo): per sapere se e' aperta si legge la finestra.
        final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0 || View.of(context).viewInsets.bottom > 0;
        final content = KeyedSubtree(
          key: _contentKey,
          child: ResponsiveCenter(maxWidth: widget.maxWidth, child: widget.child),
        );
        if (keyboard) {
          return SingleChildScrollView(child: content);
        }
        // Align: rispetta l'allineamento anche dentro uno Stack (AnimatedSwitcher
        // della prenotazione), che altrimenti centrava la pagina in verticale
        return Align(
          alignment: widget.alignment,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: widget.alignment,
            child: SizedBox(width: c.maxWidth, child: content),
          ),
        );
      },
    );
  }
}

/// Scaffold con sfondo sfumato e AppBar trasparente.
class AppScaffold extends StatelessWidget {
  const AppScaffold({
    super.key,
    this.title,
    required this.body,
    this.actions,
    this.bottom,
    this.floatingActionButton,
    this.leading,
  });

  final String? title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? bottom;
  final Widget? floatingActionButton;
  final Widget? leading;

  @override
  Widget build(BuildContext context) => AppBackground(
    child: Scaffold(
      backgroundColor: Colors.transparent,
      appBar: title == null && actions == null
          ? null
          : AppBar(title: title == null ? null : Text(title!.toUpperCase()), actions: actions, leading: leading),
      body: body,
      bottomNavigationBar: bottom,
      floatingActionButton: floatingActionButton,
    ),
  );
}

class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.selected = false,
    this.margin,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final bool selected;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(8);
    return Padding(
      padding: margin ?? EdgeInsets.zero,
      child: Material(
        color: selected ? Colors.white.withValues(alpha: 0.12) : AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: selected ? AppColors.white : AppColors.cardBorder, width: selected ? 1.4 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({super.key, required this.label, this.onPressed, this.icon, this.loading = false});
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: FilledButton(
      onPressed: loading ? null : onPressed,
      child: loading
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.black),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 10)],
                Text(label.toUpperCase()),
              ],
            ),
    ),
  );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 10),
    child: Row(
      children: [
        Expanded(
          child: Text(
            text.toUpperCase(),
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.6,
            ),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.height = 160, this.markOnly = false});
  final double height;
  final bool markOnly;

  @override
  Widget build(BuildContext context) => Image.asset(
    markOnly ? 'assets/images/logo_mark.png' : 'assets/images/logo_full.png',
    height: height,
    fit: BoxFit.contain,
    filterQuality: FilterQuality.high,
    color: AppColors.white, // logo in avorio, coerente con i testi
    colorBlendMode: BlendMode.srcIn,
  );
}

class BarberAvatar extends StatelessWidget {
  const BarberAvatar({super.key, required this.barber, this.size = 48});
  final Barber barber;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: const LinearGradient(colors: [AppColors.steel, AppColors.graphite]),
      border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      image: barber.photoUrl == null || barber.photoUrl!.isEmpty
          ? null
          : DecorationImage(image: NetworkImage(barber.photoUrl!), fit: BoxFit.cover),
    ),
    alignment: Alignment.center,
    child: barber.photoUrl == null || barber.photoUrl!.isEmpty
        ? Text(
            barber.initials,
            style: slab(size: size * 0.36, weight: FontWeight.w600),
          )
        : null,
  );
}

class StatusBadge extends StatelessWidget {
  const StatusBadge(this.status, {super.key});
  final AppointmentStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      AppointmentStatus.confirmed => AppColors.success,
      AppointmentStatus.completed => AppColors.silver,
      AppointmentStatus.cancelled => AppColors.danger,
      AppointmentStatus.noShow => AppColors.warning,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
      child: Text(
        statusLabel(status),
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.4),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 32),
    child: Column(
      children: [
        Icon(icon, size: 40, color: AppColors.muted),
        const SizedBox(height: 12),
        Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.muted),
        ),
      ],
    ),
  );
}

/// Transizione morbida tra le pagine.
Route<T> fadeRoute<T>(Widget page) => PageRouteBuilder<T>(
  transitionDuration: const Duration(milliseconds: 380),
  reverseTransitionDuration: const Duration(milliseconds: 280),
  pageBuilder: (_, _, _) => page,
  transitionsBuilder: (_, anim, _, child) => FadeTransition(
    opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
    child: SlideTransition(
      position: Tween(
        begin: const Offset(0, 0.03),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
      child: child,
    ),
  ),
);
