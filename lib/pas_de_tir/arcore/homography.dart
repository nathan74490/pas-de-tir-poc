import 'dart:ui' show Offset, Size;

import 'package:flutter/rendering.dart' show Matrix4;

/// Transformation perspective d'un rectangle [size] vers un quadrilatère
/// écran (coins haut-gauche, haut-droite, bas-droite, bas-gauche).
/// Sert à dessiner la plaque ancrée par ARCore avec la bonne perspective.
class Homography {
  Homography._(this._a, this._b, this._c, this._d, this._e, this._f, this._g, this._h, this._size);

  factory Homography.rectToQuad(Size size, List<Offset> quad) {
    final p0 = quad[0], p1 = quad[1], p2 = quad[2], p3 = quad[3];
    final dx1 = p1.dx - p2.dx, dx2 = p3.dx - p2.dx, dx3 = p0.dx - p1.dx + p2.dx - p3.dx;
    final dy1 = p1.dy - p2.dy, dy2 = p3.dy - p2.dy, dy3 = p0.dy - p1.dy + p2.dy - p3.dy;
    double g = 0, h = 0;
    final det = dx1 * dy2 - dx2 * dy1;
    if ((dx3.abs() > 1e-9 || dy3.abs() > 1e-9) && det.abs() > 1e-12) {
      g = (dx3 * dy2 - dx2 * dy3) / det;
      h = (dx1 * dy3 - dx3 * dy1) / det;
    }
    return Homography._(
      p1.dx - p0.dx + g * p1.dx,
      p3.dx - p0.dx + h * p3.dx,
      p0.dx,
      p1.dy - p0.dy + g * p1.dy,
      p3.dy - p0.dy + h * p3.dy,
      p0.dy,
      g,
      h,
      size,
    );
  }

  final double _a, _b, _c, _d, _e, _f, _g, _h;
  final Size _size;

  /// Point local au rectangle → point écran.
  Offset map(Offset local) {
    final u = local.dx / _size.width, v = local.dy / _size.height;
    final w = _g * u + _h * v + 1;
    return Offset((_a * u + _b * v + _c) / w, (_d * u + _e * v + _f) / w);
  }

  /// Matrice pour le widget Transform (enfant de taille [_size] en 0,0).
  Matrix4 toMatrix4() {
    final m = Matrix4(
      _a, _d, 0, _g, //
      _b, _e, 0, _h, //
      0, 0, 1, 0, //
      _c, _f, 0, 1, //
    );
    return m..multiply(Matrix4.diagonal3Values(1 / _size.width, 1 / _size.height, 1));
  }
}
