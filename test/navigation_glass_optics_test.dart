import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:python_runner/ui/navigation_glass.dart';

// Exercise the packaged fragment program with an explicit scene texture. This
// tests refraction even when flutter_tester cannot use ImageFilter.shader.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ui.FragmentProgram program;
  setUpAll(() async {
    program =
        await ui.FragmentProgram.fromAsset(NavigationGlassResources.asset);
  });

  test('a uniform backdrop does not acquire dark or colored slots', () async {
    const base = ui.Color(0xff8090a0);
    final result = await _render(program, outside: base, track: base);
    for (var y = 717; y < 787; y++) {
      for (var x = 110; x < 156; x++) {
        final pixel = result.pixel(x, y);
        expect(pixel.r, greaterThanOrEqualTo(base.r - 2 / 255));
        expect(pixel.g, greaterThanOrEqualTo(base.g - 2 / 255));
        expect(pixel.b, greaterThanOrEqualTo(base.b - 2 / 255));
      }
    }
  });

  for (final dpr in [1, 3]) {
    test('edge bands inherit the outside color at ${dpr}x', () async {
      final dark =
          await _render(program, dpr: dpr, outside: const ui.Color(0xff030918));
      final red =
          await _render(program, dpr: dpr, outside: const ui.Color(0xffdf4524));
      final light =
          await _render(program, dpr: dpr, outside: const ui.Color(0xfff8fafc));
      for (final y in [722, 781]) {
        final darkPixel = dark.pixel(133, y);
        final redPixel = red.pixel(133, y);
        final lightPixel = light.pixel(133, y);
        expect(lightPixel.computeLuminance(),
            greaterThan(darkPixel.computeLuminance() + 0.25));
        expect(redPixel.r, greaterThan(redPixel.b + 0.25));
      }
      expect(dark.pixel(133, 752), red.pixel(133, 752),
          reason: 'The flat center must not inherit the outside band color');
    });
  }

  test('rest and a wider track do not produce the same recesses', () async {
    final active = await _render(program);
    final rest = await _render(program, progress: 0);
    final wide = await _render(program,
        trackBounds: const ui.Rect.fromLTWH(16, 700, 358, 104));
    expect(active.pixel(133, 722).computeLuminance(),
        lessThan(rest.pixel(133, 722).computeLuminance() * 0.4));
    expect(wide.pixel(133, 722).computeLuminance(),
        greaterThan(active.pixel(133, 722).computeLuminance() + 0.04));
  });
}

class _Pixels {
  _Pixels(this.bytes, this.width, this.dpr);
  final ByteData bytes;
  final int width;
  final int dpr;

  ui.Color pixel(int x, int y) {
    final i = ((y * dpr + dpr ~/ 2) * width + x * dpr + dpr ~/ 2) * 4;
    return ui.Color.fromARGB(bytes.getUint8(i + 3), bytes.getUint8(i),
        bytes.getUint8(i + 1), bytes.getUint8(i + 2));
  }
}

Future<_Pixels> _render(ui.FragmentProgram program,
    {ui.Color outside = const ui.Color(0xff030918),
    ui.Color track = const ui.Color(0xff50647c),
    ui.Rect trackBounds = const ui.Rect.fromLTWH(16, 720, 358, 64),
    double progress = 1,
    int dpr = 1}) async {
  const viewport = ui.Size(390, 844);
  const lens = ui.Rect.fromLTWH(80, 716, 106, 72);
  final width = (viewport.width * dpr).round();
  final height = (viewport.height * dpr).round();
  final sceneRecorder = ui.PictureRecorder();
  final sceneCanvas = ui.Canvas(sceneRecorder)..scale(dpr.toDouble());
  sceneCanvas.drawPaint(ui.Paint()..color = outside);
  sceneCanvas.drawRRect(
      ui.RRect.fromRectAndRadius(trackBounds, const ui.Radius.circular(32)),
      ui.Paint()..color = track);
  final scenePicture = sceneRecorder.endRecording();
  final scene = await scenePicture.toImage(width, height);
  scenePicture.dispose();
  final shader = program.fragmentShader();
  final values = <double>[
    width.toDouble(),
    height.toDouble(),
    dpr.toDouble(),
    NavigationGlassResources.lensDepth * progress,
    1 + (NavigationGlassResources.lensZoom - 1) * progress,
    NavigationGlassResources.lensDispersion * progress,
    lens.left,
    lens.top,
    lens.width,
    lens.height,
    viewport.width,
    viewport.height,
    1 - (1 - progress) * (1 - progress),
  ];
  for (var i = 0; i < values.length; i++) {
    shader.setFloat(i, values[i]);
  }
  shader.setImageSampler(0, scene);
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawImage(scene, ui.Offset.zero, ui.Paint());
  canvas.save();
  canvas.clipRRect(ui.RRect.fromRectAndRadius(
      ui.Rect.fromLTWH(
          lens.left * dpr, lens.top * dpr, lens.width * dpr, lens.height * dpr),
      ui.Radius.circular(lens.height / 2 * dpr)));
  canvas.drawRect(ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      ui.Paint()..shader = shader);
  canvas.restore();
  final picture = recorder.endRecording();
  final output = await picture.toImage(width, height);
  try {
    if (const bool.fromEnvironment('recordGlassOptics')) {
      final png = await output.toByteData(format: ui.ImageByteFormat.png);
      final path = 'build/glass-optics/${outside.toARGB32().toRadixString(16)}'
          '-${track.toARGB32().toRadixString(16)}-$progress-${trackBounds.height}-$dpr.png';
      final file = File(path);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(png!.buffer.asUint8List());
    }
    return _Pixels(
        (await output.toByteData(format: ui.ImageByteFormat.rawRgba))!,
        width,
        dpr);
  } finally {
    output.dispose();
    picture.dispose();
    shader.dispose();
    scene.dispose();
  }
}
