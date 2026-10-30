import 'package:flutter/material.dart';

/// Barra di avanzamento moderna: verde con righe crema che scorrono.
/// [value] da 0 a 1; null = in corso senza percentuale.
class StripedBar extends StatefulWidget {
  const StripedBar({super.key, this.value, this.height = 6, this.color = const Color(0xFF3BE37F)});
  final double? value;
  final double height;
  final Color color;

  @override
  State<StripedBar> createState() => _StripedBarState();
}

class _StripedBarState extends State<StripedBar> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final track = Theme.of(context).colorScheme.surfaceContainerHighest;
    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) => CustomPaint(
          painter: _StripePainter(
            value: widget.value?.clamp(0.0, 1.0),
            phase: _c.value,
            color: widget.color,
            track: track,
          ),
        ),
      ),
    );
  }
}

class _StripePainter extends CustomPainter {
  _StripePainter({required this.value, required this.phase, required this.color, required this.track});
  final double? value;
  final double phase;
  final Color color;
  final Color track;

  static const _cream = Color(0xFFFFF4DC);

  @override
  void paint(Canvas canvas, Size size) {
    final r = Radius.circular(size.height / 2);
    canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, r), Paint()..color = track);
    // senza percentuale: un tratto che scorre avanti e indietro
    final double start, width;
    if (value == null) {
      width = size.width * 0.35;
      start = (size.width + width) * phase - width;
    } else {
      start = 0;
      width = size.width * value!;
    }
    if (width <= 0) return;
    final fill = Rect.fromLTWH(start.clamp(0, size.width), 0,
        (start + width).clamp(0, size.width) - start.clamp(0, size.width), size.height);
    if (fill.width <= 0) return;
    final rr = RRect.fromRectAndRadius(fill, r);
    canvas.save();
    canvas.clipRRect(rr);
    canvas.drawRect(fill, Paint()..color = color);
    // righe diagonali crema
    final stripe = Paint()
      ..color = _cream.withValues(alpha: 0.55)
      ..strokeWidth = size.height * 0.9;
    final step = size.height * 2.6;
    final shift = phase * step;
    for (double x = fill.left - size.height * 2 - step + shift; x < fill.right + step; x += step) {
      canvas.drawLine(Offset(x, size.height + 2), Offset(x + size.height * 1.6, -2), stripe);
    }
    // riflesso in alto
    canvas.drawRect(Rect.fromLTWH(fill.left, 0, fill.width, size.height * 0.35),
        Paint()..color = Colors.white.withValues(alpha: 0.12));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_StripePainter o) => o.value != value || o.phase != phase || o.color != color;
}
