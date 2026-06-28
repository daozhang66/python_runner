import 'package:flutter_test/flutter_test.dart';
import 'package:python_runner/services/native_bridge.dart';

void main() {
  group('NativeBridge 单例化 (B3)', () {
    test('factory 多次调用返回同一实例', () {
      final a = NativeBridge();
      final b = NativeBridge();
      expect(identical(a, b), isTrue);
    });

    test('NativeBridge() 与 NativeBridge.instance 同一', () {
      expect(identical(NativeBridge.instance, NativeBridge()), isTrue);
    });

    test('Fake 子类可通过 super.named() 构造（子类化未被破坏）', () {
      final fake = _DummyBridgeFake();
      expect(fake, isA<NativeBridge>());
      // 单例 instance 仍为基类实例，不应被 Fake 构造覆盖
      expect(identical(NativeBridge.instance, fake), isFalse);
    });
  });
}

class _DummyBridgeFake extends NativeBridge {
  _DummyBridgeFake() : super.named();
}
