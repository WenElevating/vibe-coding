abstract class PerformanceTraceClock {
  const PerformanceTraceClock();

  int nowWallTimeMs();
  int nowMonotonicUs();
}

class SystemPerformanceTraceClock extends PerformanceTraceClock {
  const SystemPerformanceTraceClock();

  static final Stopwatch _stopwatch = Stopwatch()..start();

  @override
  int nowWallTimeMs() => DateTime.now().millisecondsSinceEpoch;

  @override
  int nowMonotonicUs() => _stopwatch.elapsedMicroseconds;
}
