import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:python_runner/services/execution_id_generator.dart';

void main() {
  test('ids remain monotonic when the wall clock moves back', () {
    final samples = <DateTime>[
      DateTime.fromMicrosecondsSinceEpoch(1000),
      DateTime.fromMicrosecondsSinceEpoch(999),
    ];
    final generator = ExecutionIdGenerator(
      clock: () => samples.removeAt(0),
      random: Random(7),
    );

    final firstId = generator.next();
    final secondId = generator.next();

    int timestampPart(String id) => int.parse(id.split('-').first, radix: 16);
    expect(timestampPart(secondId), greaterThan(timestampPart(firstId)));
    expect(firstId.split('-'), hasLength(3));
    expect(secondId.split('-'), hasLength(3));
    expect(secondId, isNot(firstId));
  });
}
