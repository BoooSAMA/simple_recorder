import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:logger/logger.dart';

class Log {
  static final List<LogEntry> _debugLogs = [];
  static final RxInt logCounter = 0.obs;
  static Logger? _logger;

  static Logger get logger {
    _logger ??= Logger(
      printer: PrettyPrinter(
        methodCount: 1,
        errorMethodCount: 3,
        lineLength: 120,
        dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
      ),
    );
    return _logger!;
  }

  static List<LogEntry> get debugLogs => List.unmodifiable(_debugLogs);

  static void d(dynamic message) {
    logger.d(message);
    _addDebugLog(message.toString(), Colors.grey);
  }

  static void i(dynamic message) {
    logger.i(message);
    _addDebugLog(message.toString(), Colors.blue);
  }

  static void w(dynamic message) {
    logger.w(message);
    _addDebugLog(message.toString(), Colors.orange);
  }

  static void e(dynamic message, [StackTrace? stackTrace]) {
    logger.e(message, stackTrace: stackTrace);
    _addDebugLog(message.toString(), Colors.red);
  }

  static void logPrint(dynamic message) {
    logger.log(Level.info, message.toString());
    _addDebugLog(message.toString(), Colors.grey);
  }

  static void _addDebugLog(String message, Color color) {
    _debugLogs.add(LogEntry(message: message, color: color));
    if (_debugLogs.length > 500) {
      _debugLogs.removeAt(0);
    }
    logCounter.value++;
  }

  static void clearDebugLogs() {
    _debugLogs.clear();
    logCounter.value++;
  }
}

class LogEntry {
  final String message;
  final Color color;
  final DateTime time;

  LogEntry({
    required this.message,
    required this.color,
  }) : time = DateTime.now();
}
