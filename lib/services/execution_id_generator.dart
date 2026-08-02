import 'dart:math';

/// Produces execution identifiers that remain ordered through wall-clock
/// adjustments and are isolated across app/provider lifetimes.
class ExecutionIdGenerator {
  ExecutionIdGenerator({DateTime Function()? clock, Random? random})
      : _clock = clock ?? DateTime.now,
        _random = random ?? Random.secure();

  final DateTime Function() _clock;
  final Random _random;
  int _sequence = 0;
  int _lastMicros = -1;

  String next() {
    final observedMicros = _clock().microsecondsSinceEpoch;
    final micros =
        observedMicros > _lastMicros ? observedMicros : _lastMicros + 1;
    _lastMicros = micros;
    _sequence = (_sequence + 1) & 0xFFFF;

    final sequence = _sequence.toRadixString(16).padLeft(4, '0');
    final entropy =
        _random.nextInt(0x7fffffff).toRadixString(16).padLeft(8, '0');
    return '${micros.toRadixString(16)}-$sequence-$entropy';
  }
}
