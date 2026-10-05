import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
// Test the narrowly patched dependency seam, not its public widget facade.
// ignore: implementation_imports
import 'package:g1455/src/proxy/proxy_layer_watch.dart';

void main() {
  test('empty stock followers are inert until content appears', () {
    final root = OffsetLayer();
    final follower = FollowerLayer(link: LayerLink());
    root.append(follower);
    final watch = ProxyLayerWatch();
    expect(watch.changeSince(root).changed, isTrue);
    expect(watch.changeSince(root).changed, isFalse);
    follower.linkedOffset = const Offset(20, 40);
    expect(watch.changeSince(root).changed, isFalse);

    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(
      const ui.Rect.fromLTWH(0, 0, 40, 40),
      ui.Paint()..color = const ui.Color(0xff123456),
    );
    final picture = PictureLayer(const ui.Rect.fromLTWH(0, 0, 40, 40))
      ..picture = recorder.endRecording();
    follower.append(picture);
    expect(watch.changeSince(root).changed, isTrue);
    expect(
      watch.changeSince(root).changed,
      isTrue,
      reason: 'Populated followers retain upstream conservative invalidation',
    );
    picture.remove();
    expect(watch.changeSince(root).changed, isTrue);
    expect(watch.changeSince(root).changed, isFalse);
    root.dispose();
  });

  test('a follower subclass is never assumed empty of custom drawing', () {
    final root = OffsetLayer()..append(_CustomFollower());
    final watch = ProxyLayerWatch();
    watch.changeSince(root);
    expect(watch.changeSince(root).changed, isTrue);
    root.dispose();
  });
}

class _CustomFollower extends FollowerLayer {
  _CustomFollower() : super(link: LayerLink());
}
