import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Unified perf logger. Writes start/end/error events to the `perf_logs`
/// table on the remote DB so frontend Flutter timings can be correlated
/// with DB function timings via a shared `correlation_id`.
///
/// Usage:
/// ```dart
/// final corr = PerfLogger.start('resume_chat', chatId: chatId);
/// try {
///   await client.rpc('host_resume_chat', params: {'p_chat_id': chatId});
///   PerfLogger.end(corr);
/// } catch (e) {
///   PerfLogger.error(corr, e);
///   rethrow;
/// }
/// ```
///
/// Or wrap a future via [PerfLogger.measure]:
/// ```dart
/// await PerfLogger.measure(
///   'host_resume_chat_rpc',
///   () => client.rpc('host_resume_chat', params: {'p_chat_id': chatId}),
///   chatId: chatId,
/// );
/// ```
///
/// Best-effort by design: log writes are fire-and-forget. A logging failure
/// must never break the actual operation. We swallow exceptions silently
/// (mirrors the DB-side `log_perf` SECURITY DEFINER function).
class PerfLogger {
  PerfLogger._();

  /// Lookup keys for SharedPreferences-backed device id.
  static const String _deviceIdKey = 'perf_logger.device_id';

  /// Cached device id (populated lazily on first call).
  static String? _deviceId;

  /// In-flight start timestamps keyed by correlation id.
  static final Map<String, DateTime> _starts = {};

  /// Toggle for production builds. Set to false to disable logging entirely
  /// (e.g. for normal users who don't need diagnostics writing to the DB).
  static bool enabled = kDebugMode;

  /// One-time random per-install id so multiple devices in the same chat
  /// can be told apart. Persisted via SharedPreferences.
  static Future<String> _resolveDeviceId() async {
    if (_deviceId != null) return _deviceId!;
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_deviceIdKey);
    if (id == null) {
      final r = Random();
      id = List<String>.generate(
              16, (_) => r.nextInt(16).toRadixString(16))
          .join();
      await prefs.setString(_deviceIdKey, id);
    }
    _deviceId = id;
    return id;
  }

  /// Generate a correlation id and emit a 'start' row. Returns the id so
  /// the caller can pass it to [end] / [error] when the action finishes.
  static String start(
    String action, {
    int? chatId,
    int? roundId,
    Map<String, dynamic>? payload,
  }) {
    final id = _uuid();
    _starts[id] = DateTime.now();
    if (enabled) {
      _emit(
        correlationId: id,
        action: action,
        phase: 'start',
        chatId: chatId,
        roundId: roundId,
        payload: payload,
      );
    }
    return id;
  }

  /// Emit an 'end' row with the duration computed from the matching [start].
  /// If no start was recorded, duration_ms is null.
  static void end(
    String correlationId, {
    String? action,
    int? chatId,
    int? roundId,
    Map<String, dynamic>? payload,
  }) {
    if (!enabled) return;
    final startedAt = _starts.remove(correlationId);
    final durationMs = startedAt == null
        ? null
        : DateTime.now().difference(startedAt).inMilliseconds;
    _emit(
      correlationId: correlationId,
      action: action ?? 'end',
      phase: 'end',
      durationMs: durationMs,
      chatId: chatId,
      roundId: roundId,
      payload: payload,
    );
  }

  /// Emit an 'error' row. Same correlation id so the timeline shows the
  /// failure attached to its start event.
  static void error(
    String correlationId,
    Object err, {
    String? action,
    int? chatId,
    int? roundId,
    StackTrace? stackTrace,
  }) {
    if (!enabled) return;
    final startedAt = _starts.remove(correlationId);
    final durationMs = startedAt == null
        ? null
        : DateTime.now().difference(startedAt).inMilliseconds;
    _emit(
      correlationId: correlationId,
      action: action ?? 'error',
      phase: 'error',
      durationMs: durationMs,
      chatId: chatId,
      roundId: roundId,
      error: err.toString(),
      payload: stackTrace == null
          ? null
          : {'stack': stackTrace.toString().split('\n').take(20).join('\n')},
    );
  }

  /// Convenience wrapper: time a future and emit start/end/error rows.
  /// Returns the future's result. Re-throws any error after logging it.
  static Future<T> measure<T>(
    String action,
    Future<T> Function() fn, {
    int? chatId,
    int? roundId,
    Map<String, dynamic>? payload,
  }) async {
    final corr = start(action,
        chatId: chatId, roundId: roundId, payload: payload);
    try {
      final result = await fn();
      end(corr, action: action, chatId: chatId, roundId: roundId);
      return result;
    } catch (e, st) {
      error(corr, e,
          action: action, chatId: chatId, roundId: roundId, stackTrace: st);
      rethrow;
    }
  }

  // --- internals ---

  static Future<void> _emit({
    required String correlationId,
    required String action,
    required String phase,
    int? durationMs,
    int? chatId,
    int? roundId,
    Map<String, dynamic>? payload,
    String? error,
  }) async {
    // Resolve device id off the hot path (cheap, but needs SharedPreferences).
    final deviceId = await _resolveDeviceId();
    // Fire-and-forget over an async lambda so the call actually executes.
    //
    // IMPORTANT: PostgrestFilterBuilder is a *lazy* future — it doesn't
    // start the HTTP request until `.then()` (or `await`) is called.
    // Wrapping in a plain `unawaited()` that ignores the builder leaves
    // the request never sent. Awaiting inside the lambda (which itself
    // is invoked but not awaited) does the right thing: the request
    // fires, errors are swallowed, the caller doesn't block.
    () async {
      try {
        await Supabase.instance.client.rpc('log_perf', params: {
          'p_correlation_id': correlationId,
          'p_source': 'flutter',
          'p_action': action,
          'p_phase': phase,
          'p_duration_ms': durationMs,
          'p_chat_id': chatId,
          'p_round_id': roundId,
          'p_device_id': deviceId,
          'p_payload': payload,
          'p_error': error,
        });
      } catch (_) {
        // Swallow — logging must never break the caller.
      }
    }();
  }

  /// Generate a v4-shaped UUID without depending on `package:uuid`.
  /// Random hex with the standard 8-4-4-4-12 layout. Good enough for
  /// correlation purposes (we just need uniqueness within a session).
  static String _uuid() {
    final r = Random.secure();
    String hex(int n) => List.generate(
            n, (_) => r.nextInt(16).toRadixString(16))
        .join();
    return '${hex(8)}-${hex(4)}-4${hex(3)}-'
        '${(8 + r.nextInt(4)).toRadixString(16)}${hex(3)}-'
        '${hex(12)}';
  }
}

