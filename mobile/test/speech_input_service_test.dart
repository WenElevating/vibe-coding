import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/services/speech_input_service.dart';

void main() {
  test('pcm16 little endian samples convert to normalized floats', () {
    final bytes = Uint8List.fromList(<int>[
      0x00, 0x00,
      0x00, 0x40,
      0x00, 0x80,
    ]);

    final samples = pcm16LittleEndianToFloatSamples(bytes);

    expect(samples, hasLength(3));
    expect(samples[0], 0);
    expect(samples[1], closeTo(0.5, 0.0001));
    expect(samples[2], -1);
  });
}
