import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/data/models/adapter_models.dart';

void main() {
  group('AdapterStatus model parsing', () {
    test('uses safe defaults for old daemon payloads', () {
      final status = AdapterStatus.fromJson(<String, Object?>{
        'adapter': 'codex',
        'available': true,
        'status': 'available',
      });

      expect(status.models, isEmpty);
      expect(status.selectedModel, isNull);
      expect(status.canSelectModel, isFalse);
    });

    test('parses selected model rows from new daemon payloads', () {
      final status = AdapterStatus.fromJson(<String, Object?>{
        'adapter': 'codex',
        'available': true,
        'status': 'available',
        'models': <Object?>[
          <String, Object?>{
            'id': 'gpt-5-codex',
            'label': 'GPT-5 Codex',
            'source': 'codex_config',
            'selected': true,
          },
        ],
        'selectedModel': 'gpt-5-codex',
        'canSelectModel': true,
      });

      expect(status.canSelectModel, isTrue);
      expect(status.selectedModel, 'gpt-5-codex');
      expect(status.models, hasLength(1));
      expect(
        status.models.single,
        isA<AdapterModelOption>()
            .having((model) => model.id, 'id', 'gpt-5-codex')
            .having((model) => model.label, 'label', 'GPT-5 Codex')
            .having((model) => model.source, 'source', 'codex_config')
            .having((model) => model.selected, 'selected', isTrue),
      );
    });
  });
}
