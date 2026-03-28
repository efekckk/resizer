import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class WarpPainter extends CustomPainter {
  final ui.Image image;
  final ui.Vertices vertices;
  final bool mirrorHorizontally;

  WarpPainter({
    required this.image,
    required this.vertices,
    this.mirrorHorizontally = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final imgW = image.width.toDouble();
    final imgH = image.height.toDouble();

    // Scale to fill the widget while preserving aspect ratio.
    final scale = max(size.width / imgW, size.height / imgH);
    final scaledW = imgW * scale;
    final scaledH = imgH * scale;
    final dx = (size.width - scaledW) / 2;
    final dy = (size.height - scaledH) / 2;

    canvas.save();
    canvas.translate(dx, dy);

    if (mirrorHorizontally) {
      canvas.translate(scaledW, 0);
      canvas.scale(-scale, scale);
    } else {
      canvas.scale(scale, scale);
    }

    final shader = ui.ImageShader(
      image,
      ui.TileMode.clamp,
      ui.TileMode.clamp,
      Matrix4.identity().storage,
    );

    canvas.drawVertices(
      vertices,
      BlendMode.srcOver,
      Paint()..shader = shader,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(WarpPainter old) =>
      image != old.image || vertices != old.vertices;
}
