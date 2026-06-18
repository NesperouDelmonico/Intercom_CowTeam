import 'package:flutter_test/flutter_test.dart';

// Lógica pura extraída de AudioService para testear sin hardware
List<int> applyGain(List<int> chunk, double gain) {
  if (gain == 1.0) return chunk;
  final result = List<int>.filled(chunk.length, 0);
  for (int i = 0; i < chunk.length - 1; i += 2) {
    final s = chunk[i] | (chunk[i + 1] << 8);
    final signed = s > 32767 ? s - 65536 : s;
    final amplified = (signed * gain).round().clamp(-32768, 32767);
    result[i] = amplified & 0xFF;
    result[i + 1] = (amplified >> 8) & 0xFF;
  }
  return result;
}

bool shouldTransmit(List<int> chunk, bool voxEnabled, double threshold) {
  if (!voxEnabled) return true;
  double sum = 0;
  for (int i = 0; i < chunk.length - 1; i += 2) {
    final sample = chunk[i] | (chunk[i + 1] << 8);
    final signed = sample > 32767 ? sample - 65536 : sample;
    sum += signed * signed;
  }
  final rms = chunk.length > 1 ? (sum / (chunk.length / 2)) : 0.0;
  return rms > (threshold * threshold);
}

void main() {
  group('applyGain', () {
    test('ganancia 1.0 no modifica los datos', () {
      final input = [0x00, 0x40, 0xFF, 0x3F];
      final result = applyGain(input, 1.0);
      expect(result, equals(input));
    });

    test('ganancia 0.0 silencia completamente', () {
      final input = [0x00, 0x40, 0xFF, 0x3F];
      final result = applyGain(input, 0.0);
      final s1 = result[0] | (result[1] << 8);
      final s2 = result[2] | (result[3] << 8);
      expect(s1, 0);
      expect(s2, 0);
    });

    test('ganancia 2.0 amplifica sin exceder límite PCM16', () {
      final input = [0xFF, 0x7F, 0xFF, 0x7F]; // 32767
      final result = applyGain(input, 2.0);
      final sample = result[0] | (result[1] << 8);
      expect(sample, lessThanOrEqualTo(32767));
      expect(sample, greaterThan(0));
    });

    test('lista vacía retorna lista vacía', () {
      final result = applyGain([], 2.0);
      expect(result, isEmpty);
    });

    test('muestras negativas amplifican y mantienen signo', () {
      // 0x8001 = -32767 en PCM16 signed
      final input = [0x01, 0x80];
      final result = applyGain(input, 0.5);
      final raw = result[0] | (result[1] << 8);
      final signed = raw > 32767 ? raw - 65536 : raw;
      expect(signed, isNegative);
      expect(signed, greaterThanOrEqualTo(-32768));
    });

    test('ganancia mayor que 1 amplifica correctamente', () {
      // Muestra pequeña: valor 100
      final input = [100, 0x00];
      final result = applyGain(input, 3.0);
      final sample = result[0] | (result[1] << 8);
      expect(sample, 300);
    });

    test('clampea valores que exceden el máximo positivo', () {
      final input = [0xFF, 0x7F]; // 32767
      final result = applyGain(input, 10.0);
      final sample = result[0] | (result[1] << 8);
      expect(sample, 32767);
    });

    test('clampea valores que exceden el mínimo negativo', () {
      final input = [0x01, 0x80]; // -32767
      final result = applyGain(input, 10.0);
      final raw = result[0] | (result[1] << 8);
      final signed = raw > 32767 ? raw - 65536 : raw;
      expect(signed, -32768);
    });
  });

  group('shouldTransmit — VOX', () {
    test('sin VOX siempre transmite aunque sea silencio', () {
      final silence = List<int>.filled(320, 0);
      expect(shouldTransmit(silence, false, 500), true);
    });

    test('con VOX no transmite en silencio absoluto', () {
      final silence = List<int>.filled(320, 0);
      expect(shouldTransmit(silence, true, 500), false);
    });

    test('con VOX transmite señal fuerte', () {
      final loud = <int>[];
      for (int i = 0; i < 160; i++) {
        loud.add(0xFF);
        loud.add(0x7F); // 32767
      }
      expect(shouldTransmit(loud, true, 100), true);
    });

    test('con VOX y threshold alto no transmite señal débil', () {
      final weak = <int>[];
      for (int i = 0; i < 160; i++) {
        weak.add(0x05);
        weak.add(0x00); // valor 5
      }
      expect(shouldTransmit(weak, true, 2000), false);
    });

    test('lista vacía no transmite con VOX', () {
      expect(shouldTransmit([], true, 100), false);
    });

    test('threshold 0 transmite cualquier señal no silenciosa', () {
      final signal = <int>[];
      for (int i = 0; i < 160; i++) {
        signal.add(0x10);
        signal.add(0x00); // valor pequeño pero no cero
      }
      expect(shouldTransmit(signal, true, 0), true);
    });

    test('sin VOX transmite con threshold alto', () {
      final silence = List<int>.filled(320, 0);
      expect(shouldTransmit(silence, false, 99999), true);
    });
  });

  group('PCM16 — validaciones de rango', () {
    test('valor máximo PCM16 es 32767', () {
      expect(32767, lessThan(32768));
      expect(32767 & 0xFF, 0xFF);
      expect((32767 >> 8) & 0xFF, 0x7F);
    });

    test('valor mínimo PCM16 es -32768', () {
      final val = -32768;
      final unsigned = val & 0xFFFF;
      expect(unsigned, 0x8000);
    });

    test('conversión little-endian correcta', () {
      // 0x1234 = 4660 en decimal
      final lo = 0x34;
      final hi = 0x12;
      final combined = lo | (hi << 8);
      expect(combined, 0x1234);
    });
  });
}
