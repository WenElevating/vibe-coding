class SpeechTextPostProcessor {
  const SpeechTextPostProcessor();

  String processFinalText(String text) {
    final normalized = _normalizeSpacing(text);
    if (normalized.isEmpty) return normalized;

    final withTerms = _normalizeDomainTerms(normalized);
    if (!_containsChinese(withTerms)) return withTerms;

    final withBreaks = _hasSentencePunctuation(withTerms)
        ? withTerms
        : _insertChineseBreaks(withTerms);
    return _ensureTerminalPunctuation(withBreaks);
  }

  static String _normalizeSpacing(String text) {
    var result = text.trim().replaceAll(RegExp(r'[ \t\r\n]+'), ' ');
    while (true) {
      final next = result.replaceAllMapped(
        RegExp(r'([\u4e00-\u9fff])\s+([\u4e00-\u9fff])'),
        (match) => '${match[1]}${match[2]}',
      );
      if (next == result) return result;
      result = next;
    }
  }

  static String _normalizeDomainTerms(String text) {
    var result = text;
    for (final entry in _phraseReplacements.entries) {
      result = result.replaceAll(entry.key, entry.value);
    }
    for (final entry in _asciiTermReplacements.entries) {
      result = result.replaceAllMapped(
        RegExp(entry.key, caseSensitive: false),
        (_) => entry.value,
      );
    }
    return result;
  }

  static String _insertChineseBreaks(String text) {
    var result = text.replaceAllMapped(
      RegExp(r'([^，。！？；：!?])((?:然后|接着|另外|但是|不过|所以|而且))'),
      (match) => '${match[1]}，${match[2]}',
    );
    result = result.replaceAllMapped(
      RegExp(r'([^，。！？；：!?])(再(?=提交|运行|看|帮|推送|打开|检查|修|改|发|试))'),
      (match) => '${match[1]}，${match[2]}',
    );
    return result;
  }

  static String _ensureTerminalPunctuation(String text) {
    final trimmed = text.trimRight();
    if (_terminalPunctuation.hasMatch(trimmed)) return text;
    final punctuation = _looksLikeQuestion(trimmed) ? '？' : '。';
    return '$text$punctuation';
  }

  static bool _looksLikeQuestion(String text) => _questionCue.hasMatch(text);

  static bool _containsChinese(String text) => _chinese.hasMatch(text);

  static bool _hasSentencePunctuation(String text) =>
      _sentencePunctuation.hasMatch(text);

  static final RegExp _chinese = RegExp(r'[\u4e00-\u9fff]');
  static final RegExp _sentencePunctuation = RegExp(r'[，。！？；：!?]');
  static final RegExp _terminalPunctuation = RegExp(r'[。！？!?]$');
  static final RegExp _questionCue =
      RegExp(r'(吗|么|呢|是不是|能不能|要不要|可不可以|为什么|怎么|哪里|哪个|多少|是否|能否)');

  static const Map<String, String> _phraseReplacements = {
    '扣得克斯': 'Codex',
    '扣的克斯': 'Codex',
    '寇德克斯': 'Codex',
    '克劳德': 'Claude',
    '克劳的': 'Claude',
    '弗拉特': 'Flutter',
    '福拉特': 'Flutter',
    '达特语言': 'Dart',
    '瑞德米': 'README',
  };

  static const Map<String, String> _asciiTermReplacements = {
    r'\bcodex\b': 'Codex',
    r'\bclaude\b': 'Claude',
    r'\bflutter\b': 'Flutter',
    r'\bdart\b': 'Dart',
    r'\bgit\b': 'Git',
    r'\bgithub\b': 'GitHub',
    r'\bread\s*me\b': 'README',
    r'\basr\b': 'ASR',
    r'\bapi\b': 'API',
    r'\bjson\b': 'JSON',
  };
}
