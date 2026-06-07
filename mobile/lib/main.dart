import 'package:flutter/material.dart';

import 'src/app/app.dart';
import 'src/services/performance_trace_startup_buffer.dart';

void main() {
  final startupBuffer = PerformanceTraceStartupBuffer.global;
  startupBuffer.captureStartupMark('app.main.started', critical: true);
  runApp(LanAiCliControlApp(startupBuffer: startupBuffer));
}
