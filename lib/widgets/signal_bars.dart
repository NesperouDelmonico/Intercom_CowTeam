import 'package:flutter/material.dart';

const _inactive = Color(0xFF445566);

/// Color del indicador según la calidad de señal (0 = sin señal … 3 = buena).
Color signalColor(int quality) {
  switch (quality) {
    case 3:
      return const Color(0xFF3DD68C); // verde
    case 2:
      return const Color(0xFFE5B800); // amarillo
    case 1:
      return const Color(0xFFE58A00); // naranja
    default:
      return const Color(0xFFCC4444); // rojo
  }
}

/// Tres barras estilo wifi. [quality] va de 0 a 3 y se acota si viene fuera.
class SignalBars extends StatelessWidget {
  final int quality;
  const SignalBars({super.key, required this.quality});

  @override
  Widget build(BuildContext context) {
    final q = quality.clamp(0, 3);
    const heights = [5.0, 8.0, 11.0];
    return Semantics(
      label: 'Calidad de señal $q de 3',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(3, (i) {
          final active = q > i;
          return Container(
            margin: const EdgeInsets.only(right: 1.5),
            width: 3,
            height: heights[i],
            decoration: BoxDecoration(
              color: active ? signalColor(q) : _inactive.withOpacity(0.35),
              borderRadius: BorderRadius.circular(1),
            ),
          );
        }),
      ),
    );
  }
}
