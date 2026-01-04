// Debug Logger Service
// Centralized logging with levels and timestamps for PDF operations
// 
// Usage:
//   DebugLogger.info('Loading PDF...');
//   DebugLogger.error('Failed to load', error);

import 'package:flutter/foundation.dart';

enum LogLevel { debug, info, success, warning, error }

class LogEntry {
  final DateTime timestamp;
  final LogLevel level;
  final String message;
  final String? details;

  LogEntry({
    required this.timestamp,
    required this.level,
    required this.message,
    this.details,
  });

  String get emoji {
    switch (level) {
      case LogLevel.debug:
        return '🟡';
      case LogLevel.info:
        return '🔵';
      case LogLevel.success:
        return '🟢';
      case LogLevel.warning:
        return '🟠';
      case LogLevel.error:
        return '🔴';
    }
  }

  String get levelName {
    switch (level) {
      case LogLevel.debug:
        return 'DEBUG';
      case LogLevel.info:
        return 'INFO';
      case LogLevel.success:
        return 'SUCCESS';
      case LogLevel.warning:
        return 'WARNING';
      case LogLevel.error:
        return 'ERROR';
    }
  }

  String get formatted {
    final time = '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}:${timestamp.second.toString().padLeft(2, '0')}';
    final detail = details != null ? ' | $details' : '';
    return '$emoji [$time] [$levelName] $message$detail';
  }

  @override
  String toString() => formatted;
}

class DebugLogger {
  static final List<LogEntry> _logs = [];
  static final ValueNotifier<List<LogEntry>> logsNotifier = ValueNotifier([]);
  
  static bool enabled = true;
  static LogLevel minLevel = LogLevel.debug;

  /// Get all logs
  static List<LogEntry> get logs => List.unmodifiable(_logs);

  /// Clear all logs
  static void clear() {
    _logs.clear();
    logsNotifier.value = [];
  }

  /// Add a log entry
  static void _log(LogLevel level, String message, [String? details]) {
    if (!enabled) return;
    if (level.index < minLevel.index) return;

    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      message: message,
      details: details,
    );

    _logs.add(entry);
    logsNotifier.value = List.from(_logs);

    // Also print to console
    debugPrint(entry.formatted);
  }

  /// Log debug message
  static void debug(String message, [String? details]) {
    _log(LogLevel.debug, message, details);
  }

  /// Log info message
  static void info(String message, [String? details]) {
    _log(LogLevel.info, message, details);
  }

  /// Log success message
  static void success(String message, [String? details]) {
    _log(LogLevel.success, message, details);
  }

  /// Log warning message
  static void warning(String message, [String? details]) {
    _log(LogLevel.warning, message, details);
  }

  /// Log error message
  static void error(String message, [dynamic error]) {
    _log(LogLevel.error, message, error?.toString());
  }

  /// Add logs from server response
  static void addServerLogs(List<dynamic> serverLogs) {
    for (final log in serverLogs) {
      if (log is String) {
        // Parse server log format: "🔵 [INFO] message"
        if (log.contains('[ERROR]')) {
          error(log);
        } else if (log.contains('[SUCCESS]')) {
          success(log);
        } else if (log.contains('[DEBUG]')) {
          debug(log);
        } else {
          info(log);
        }
      }
    }
  }

  /// Get logs as copyable text
  static String getLogsAsText() {
    return _logs.map((e) => e.formatted).join('\n');
  }
}
