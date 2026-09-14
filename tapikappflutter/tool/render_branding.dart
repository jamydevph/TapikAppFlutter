import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

const String outputDir = 'assets/branding';
const String windowsIconPath = 'windows/runner/resources/app_icon.ico';
const List<int> windowsIconSizes = [16, 24, 32, 48, 64, 128, 256];

const double markSize = 88;
const double markRadius = 28;
const double glyphStroke = 5;

const Rgb primary = Rgb(0x7C, 0x5C, 0xFF);
const Rgb onPrimary = Rgb(0xFF, 0xFF, 0xFF);

const double glowOffsetY = 6;
const double glowBlur = 20;
const double glowOpacity = 0.4;

const double desktopIconFraction = 824 / 1024;
const double android12IconDp = 240;
const int android12IconSize = 1152;

Future<void> main() async {
  final mark = LogoMark();
  final outputs = <String, img.Image>{
    'icon.png': _renderIcon(mark),
    'icon_foreground.png': _renderAdaptiveForeground(mark),
    'icon_desktop.png': _renderDesktopIcon(mark),
    'splash_mark.png': _renderSplashMark(mark),
    'splash_android12.png': _renderAndroid12Icon(mark),
  };
  Directory(outputDir).createSync(recursive: true);
  for (final entry in outputs.entries) {
    final path = '$outputDir/${entry.key}';
    File(path).writeAsBytesSync(img.encodePng(entry.value));
    stdout.writeln('wrote $path (${entry.value.width}x${entry.value.height})');
  }
  File(windowsIconPath).writeAsBytesSync(_encodeWindowsIcon(outputs['icon_desktop.png']!));
  stdout.writeln('wrote $windowsIconPath (${windowsIconSizes.join(', ')})');
}

Uint8List _encodeWindowsIcon(img.Image source) {
  final frames = [
    for (final size in windowsIconSizes)
      img.copyResize(
        source,
        width: size,
        height: size,
        interpolation: img.Interpolation.cubic,
      ),
  ];
  return img.IcoEncoder().encodeImages(frames);
}

img.Image _renderIcon(LogoMark mark) {
  const size = 1024;
  final canvas = Canvas(size);
  canvas.fill(primary);
  final placement = Placement.fit(size, markSize);
  canvas.paint(mark.glyph, placement, onPrimary);
  return canvas.toImage();
}

img.Image _renderAdaptiveForeground(LogoMark mark) {
  const size = 1024;
  final canvas = Canvas(size, bleed: onPrimary);
  final placement = Placement.fit(size, markSize);
  canvas.paint(mark.glyph, placement, onPrimary);
  return canvas.toImage();
}

img.Image _renderDesktopIcon(LogoMark mark) {
  const size = 1024;
  final canvas = Canvas(size, bleed: primary);
  final placement = Placement.fit(size, markSize, fraction: desktopIconFraction);
  canvas.paint(mark.tile, placement, primary);
  canvas.paint(mark.glyph, placement, onPrimary);
  return canvas.toImage();
}

img.Image _renderSplashMark(LogoMark mark) {
  const scale = 4.0;
  const margin = 32.0;
  final size = ((markSize + margin * 2) * scale).round();
  final canvas = Canvas(size, bleed: primary);
  final placement = Placement(scale: scale, dx: margin * scale, dy: margin * scale);
  _paintGlowingMark(canvas, mark, placement);
  return canvas.toImage();
}

img.Image _renderAndroid12Icon(LogoMark mark) {
  const scale = android12IconSize / android12IconDp;
  const offset = (android12IconSize - markSize * scale) / 2;
  final canvas = Canvas(android12IconSize, bleed: primary);
  const placement = Placement(scale: scale, dx: offset, dy: offset);
  _paintGlowingMark(canvas, mark, placement);
  return canvas.toImage();
}

void _paintGlowingMark(Canvas canvas, LogoMark mark, Placement placement) {
  final glow = placement.shifted(dy: glowOffsetY * placement.scale);
  canvas.paint(
    mark.tile,
    glow,
    primary,
    opacity: glowOpacity,
    blurSigma: glowBlur / 2 * placement.scale,
  );
  canvas.paint(mark.tile, placement, primary);
  canvas.paint(mark.glyph, placement, onPrimary);
}

class Rgb {
  const Rgb(this.r, this.g, this.b);

  final int r;
  final int g;
  final int b;
}

typedef Sdf = double Function(double x, double y);

class LogoMark {
  LogoMark()
      : tile = RoundedSquare(size: markSize, radius: markRadius).distance,
        glyph = Union([
          Arc.fromChord(x0: 26, x1: 58, y: 23, radius: 18.7, stroke: glyphStroke),
          Arc.fromChord(x0: 30, x1: 54, y: 34, radius: 15, stroke: glyphStroke),
          Circle(cx: 33, cy: 55, radius: 9),
        ]).distance;

  final Sdf tile;
  final Sdf glyph;
}

abstract class Shape {
  double distance(double x, double y);
}

class RoundedSquare implements Shape {
  const RoundedSquare({required this.size, required this.radius});

  final double size;
  final double radius;

  @override
  double distance(double x, double y) {
    final half = size / 2;
    final qx = (x - half).abs() - (half - radius);
    final qy = (y - half).abs() - (half - radius);
    final outside = math.sqrt(
      math.max(qx, 0) * math.max(qx, 0) + math.max(qy, 0) * math.max(qy, 0),
    );
    return outside + math.min(math.max(qx, qy), 0) - radius;
  }
}

class Circle implements Shape {
  const Circle({required this.cx, required this.cy, required this.radius});

  final double cx;
  final double cy;
  final double radius;

  @override
  double distance(double x, double y) {
    final dx = x - cx;
    final dy = y - cy;
    return math.sqrt(dx * dx + dy * dy) - radius;
  }
}

class Arc implements Shape {
  const Arc._({
    required this.cx,
    required this.cy,
    required this.radius,
    required this.startAngle,
    required this.endAngle,
    required this.x0,
    required this.y0,
    required this.x1,
    required this.y1,
    required this.stroke,
  });

  factory Arc.fromChord({
    required double x0,
    required double x1,
    required double y,
    required double radius,
    required double stroke,
  }) {
    final halfChord = (x1 - x0) / 2;
    final cx = (x0 + x1) / 2;
    final cy = y + math.sqrt(radius * radius - halfChord * halfChord);
    return Arc._(
      cx: cx,
      cy: cy,
      radius: radius,
      startAngle: math.atan2(y - cy, x0 - cx),
      endAngle: math.atan2(y - cy, x1 - cx),
      x0: x0,
      y0: y,
      x1: x1,
      y1: y,
      stroke: stroke,
    );
  }

  final double cx;
  final double cy;
  final double radius;
  final double startAngle;
  final double endAngle;
  final double x0;
  final double y0;
  final double x1;
  final double y1;
  final double stroke;

  @override
  double distance(double x, double y) {
    final dx = x - cx;
    final dy = y - cy;
    final angle = math.atan2(dy, dx);
    final double centerline;
    if (angle >= startAngle && angle <= endAngle) {
      centerline = (math.sqrt(dx * dx + dy * dy) - radius).abs();
    } else {
      centerline = math.min(_length(x - x0, y - y0), _length(x - x1, y - y1));
    }
    return centerline - stroke / 2;
  }

  static double _length(double dx, double dy) => math.sqrt(dx * dx + dy * dy);
}

class Union implements Shape {
  const Union(this.shapes);

  final List<Shape> shapes;

  @override
  double distance(double x, double y) {
    var nearest = double.infinity;
    for (final shape in shapes) {
      nearest = math.min(nearest, shape.distance(x, y));
    }
    return nearest;
  }
}

class Placement {
  const Placement({required this.scale, required this.dx, required this.dy});

  factory Placement.fit(int canvasSize, double sourceSize, {double fraction = 1}) {
    final scale = canvasSize * fraction / sourceSize;
    final offset = (canvasSize - sourceSize * scale) / 2;
    return Placement(scale: scale, dx: offset, dy: offset);
  }

  final double scale;
  final double dx;
  final double dy;

  Placement shifted({double dx = 0, double dy = 0}) {
    return Placement(scale: scale, dx: this.dx + dx, dy: this.dy + dy);
  }
}

class Canvas {
  Canvas(this.size, {Rgb? bleed})
      : _r = Float64List(size * size),
        _g = Float64List(size * size),
        _b = Float64List(size * size),
        _a = Float64List(size * size) {
    if (bleed != null) {
      _r.fillRange(0, _r.length, bleed.r / 255);
      _g.fillRange(0, _g.length, bleed.g / 255);
      _b.fillRange(0, _b.length, bleed.b / 255);
    }
  }

  final int size;
  final Float64List _r;
  final Float64List _g;
  final Float64List _b;
  final Float64List _a;

  void fill(Rgb color) {
    for (var i = 0; i < size * size; i++) {
      _r[i] = color.r / 255;
      _g[i] = color.g / 255;
      _b[i] = color.b / 255;
      _a[i] = 1;
    }
  }

  void paint(
    Sdf sdf,
    Placement placement,
    Rgb color, {
    double opacity = 1,
    double blurSigma = 0,
  }) {
    final mask = _coverage(sdf, placement);
    if (blurSigma > 0) {
      _blur(mask, blurSigma);
    }
    final sr = color.r / 255;
    final sg = color.g / 255;
    final sb = color.b / 255;
    for (var i = 0; i < size * size; i++) {
      final sa = mask[i] * opacity;
      if (sa <= 0) continue;
      final da = _a[i];
      final outA = sa + da * (1 - sa);
      _r[i] = (sr * sa + _r[i] * da * (1 - sa)) / outA;
      _g[i] = (sg * sa + _g[i] * da * (1 - sa)) / outA;
      _b[i] = (sb * sa + _b[i] * da * (1 - sa)) / outA;
      _a[i] = outA;
    }
  }

  img.Image toImage() {
    final image = img.Image(width: size, height: size, numChannels: 4);
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        final i = y * size + x;
        image.setPixelRgba(
          x,
          y,
          (_r[i] * 255).round(),
          (_g[i] * 255).round(),
          (_b[i] * 255).round(),
          (_a[i] * 255).round(),
        );
      }
    }
    return image;
  }

  Float64List _coverage(Sdf sdf, Placement placement) {
    final mask = Float64List(size * size);
    for (var y = 0; y < size; y++) {
      final sy = (y + 0.5 - placement.dy) / placement.scale;
      for (var x = 0; x < size; x++) {
        final sx = (x + 0.5 - placement.dx) / placement.scale;
        final pixels = sdf(sx, sy) * placement.scale;
        mask[y * size + x] = (0.5 - pixels).clamp(0.0, 1.0);
      }
    }
    return mask;
  }

  void _blur(Float64List mask, double sigma) {
    final radius = (sigma * 3).ceil();
    final kernel = Float64List(radius * 2 + 1);
    var sum = 0.0;
    for (var i = -radius; i <= radius; i++) {
      final weight = math.exp(-(i * i) / (2 * sigma * sigma));
      kernel[i + radius] = weight;
      sum += weight;
    }
    for (var i = 0; i < kernel.length; i++) {
      kernel[i] /= sum;
    }
    final temp = Float64List(size * size);
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        var acc = 0.0;
        for (var k = -radius; k <= radius; k++) {
          final sx = x + k;
          if (sx < 0 || sx >= size) continue;
          acc += mask[y * size + sx] * kernel[k + radius];
        }
        temp[y * size + x] = acc;
      }
    }
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        var acc = 0.0;
        for (var k = -radius; k <= radius; k++) {
          final sy = y + k;
          if (sy < 0 || sy >= size) continue;
          acc += temp[sy * size + x] * kernel[k + radius];
        }
        mask[y * size + x] = acc;
      }
    }
  }
}
