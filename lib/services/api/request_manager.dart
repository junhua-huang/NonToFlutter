import 'dart:async';
import 'package:flutter/foundation.dart';

/// 请求管理器：去重 + 限并发 + 可取消
///
/// 浏览器 HTTP/1.1 单域名并发上限为 6。管理器预留 4 个槽位，
/// 余下 2 个供 AppWarmup 直连请求使用，避免浏览器层排队阻塞。
///
/// 用法：
/// ```dart
/// final rm = RequestManager(maxConcurrent: 4);
/// final result = await rm.execute(
///   key: 'GET:/chat/sessions',
///   task: () => api.get('/chat/sessions'),
/// );
/// ```
class RequestManager {
  final int maxConcurrent;
  final Duration ttl;

  /// 当前正在执行的请求数
  int _running = 0;

  /// 当前正在执行的请求（key → _Entry）
  final Map<String, _Entry> _inFlight = {};

  /// 等待队列（按优先级排序，高优先级在前）
  final List<_QueuedItem> _waitQueue = [];

  RequestManager({
    this.maxConcurrent = 4,
    this.ttl = const Duration(seconds: 30),
  });

  // ── 公开 API ──

  /// 执行一个可去重的请求。
  ///
  /// - 如果 [key] 已有相同请求在执行中，直接复用其结果（等待同一个 Future）
  /// - 如果当前并发数已满，排队等待
  /// - [priority] 高优先级请求排在队列前面（默认 0，值越大越优先）
  ///
  /// [task] 返回 Future\<T\>，可以是任何类型。
  /// [key] 建议格式：`"METHOD:path"`，如 `"GET:/chat/conversations/2/messages"`。
  Future<T> execute<T>({
    required String key,
    required Future<T> Function() task,
    int priority = 0,
    bool bypassManager = false,
  }) {
    // 绕开管理器：直接执行，不占槽位、不去重
    if (bypassManager) return task();
    // 去重：如果有相同的 key 正在执行中，复用其结果
    final existing = _inFlight[key];
    if (existing != null) {
      if (existing.isDone) {
        // 已完成（rare case: completed between check and now），
        // 需要重新执行。但如果 ttl 内完成过，直接返回缓存结果。
        if (_isFresh(existing)) {
          debugPrint('[RequestManager] cache hit: $key');
          return existing.completer.future as Future<T>;
        }
        // 已过期，移除并进入并发判断
        _inFlight.remove(key);
      } else {
        debugPrint('[RequestManager] dedup hit: $key');
        return existing.completer.future as Future<T>;
      }
    }

    // 并发限制：如果当前并发已满，入队等待（按优先级）
    if (_running >= maxConcurrent) {
      debugPrint('[RequestManager] queued: $key (priority=$priority, running=$_running/$maxConcurrent)');
      final completer = Completer<T>();
      _insertQueued(_QueuedItem(
        key: key,
        task: task,
        completer: completer,
        priority: priority,
      ));
      return completer.future;
    }

    // 立即执行
    return _run<T>(key, task);
  }

  /// 取消指定 key 的请求（排队中或执行中）。
  ///
  /// - 排队中：直接移除并返回 false
  /// - 执行中：尝试取消底层任务
  void cancel(String key) {
    // 先检查执行中
    final entry = _inFlight[key];
    if (entry != null && !entry.isDone) {
      entry.cancel();
      return;
    }
    // 再检查队列
    _waitQueue.removeWhere((item) {
      if (item.key == key) {
        if (!item.completer.isCompleted) {
          item.completer.completeError(
            RequestCancelledException(key),
          );
        }
        return true;
      }
      return false;
    });
  }

  /// 限并发（不去重）。
  ///
  /// 每个调用都会生成唯一 key，不会合并相同请求。
  /// 仅控制并发数：超过 [maxConcurrent] 则排队。
  Future<T> throttle<T>(Future<T> Function() task) {
    final key = '_throttle_${++_seq}';
    return _executeNoDedup<T>(key, task);
  }

  /// 当前等待队列长度
  int get pendingCount => _waitQueue.length;

  /// 当前执行中请求数
  int get inFlightCount => _running;

  // ── 内部方法 ──

  int _seq = 0;

  /// 按优先级插入队列（优先级高的在前，同优先级先进先出）
  void _insertQueued(_QueuedItem item) {
    var idx = 0;
    for (final q in _waitQueue) {
      if (item.priority <= q.priority) {
        idx++;
      } else {
        break;
      }
    }
    _waitQueue.insert(idx, item);
  }

  /// 无去重、仅限并发的执行
  Future<T> _executeNoDedup<T>(String key, Future<T> Function() task) {
    if (_running >= maxConcurrent) {
      debugPrint('[RequestManager] throttled: $key (running=$_running/$maxConcurrent)');
      final completer = Completer<T>();
      _insertQueued(_QueuedItem(
        key: key,
        task: task,
        completer: completer,
      ));
      return completer.future;
    }
    return _run<T>(key, task);
  }

  Future<T> _run<T>(String key, Future<T> Function() task) {
    _running++;
    final completer = Completer<T>();
    final cancelToken = _CancelToken();
    final entry = _Entry(
      key: key,
      completer: completer,
      cancelToken: cancelToken,
      startedAt: DateTime.now(),
    );
    _inFlight[key] = entry;

    debugPrint('[RequestManager] executing: $key (running=$_running/$maxConcurrent)');

    // 执行任务，捕获取消异常
    cancelToken.wrap(task).then(
      (result) {
        _onComplete(key, entry);
        if (!completer.isCompleted) {
          completer.complete(result);
        }
      },
      onError: (e) {
        _onComplete(key, entry);
        if (!completer.isCompleted) {
          completer.completeError(e);
        }
      },
    );

    return completer.future;
  }

  /// 请求完成（成功或失败）后的清理
  void _onComplete(String key, _Entry entry) {
    _running--;
    _inFlight.remove(key);
    debugPrint('[RequestManager] completed: $key (running=$_running/$maxConcurrent, queue=${_waitQueue.length})');

    // 处理等待队列中的下一个请求
    _drainQueue();
  }

  /// 从等待队列中取出下一个请求执行
  void _drainQueue() {
    while (_running < maxConcurrent && _waitQueue.isNotEmpty) {
      final queued = _waitQueue.removeAt(0);

      // 如果该 key 已经有在途请求，把队列项链到已有的 completer 上
      if (_inFlight.containsKey(queued.key)) {
        _chainToInFlight(queued.key, queued.completer);
        continue;
      }

      // 执行排队请求
      _run<dynamic>(queued.key, queued.task as Future<dynamic> Function()).then(
        (v) { if (!queued.completer.isCompleted) queued.completer.complete(v); },
        onError: (e) { if (!queued.completer.isCompleted) queued.completer.completeError(e); },
      );
    }
  }

  /// 将等待中的 completer 链到已有 in-flight 请求的结果上
  void _chainToInFlight(String key, Completer<dynamic> waiter) {
    final existing = _inFlight[key];
    if (existing == null || waiter.isCompleted) return;
    existing.completer.future.then(
      (v) { if (!waiter.isCompleted) waiter.complete(v); },
      onError: (e) { if (!waiter.isCompleted) waiter.completeError(e); },
    );
  }

  bool _isFresh(_Entry entry) {
    return DateTime.now().difference(entry.startedAt) < ttl;
  }
}

// ── 内部类型 ──

class _Entry {
  final String key;
  final Completer completer;
  final _CancelToken cancelToken;
  final DateTime startedAt;
  bool isDone = false;

  _Entry({
    required this.key,
    required this.completer,
    required this.cancelToken,
    required this.startedAt,
  });

  void cancel() {
    if (!isDone && !completer.isCompleted) {
      cancelToken.cancel();
      if (!completer.isCompleted) {
        completer.completeError(RequestCancelledException(key));
      }
      isDone = true;
    }
  }
}

class _QueuedItem {
  final String key;
  final Function task;
  final Completer completer;
  final int priority;

  _QueuedItem({
    required this.key,
    required this.task,
    required this.completer,
    this.priority = 0,
  });
}

/// 可取消的 Future 包装
class _CancelToken {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;

  /// 包装 task，在执行过程中检查取消状态
  Future<T> wrap<T>(Future<T> Function() task) async {
    if (_cancelled) throw RequestCancelledException('cancelled');
    try {
      final result = await task();
      if (_cancelled) throw RequestCancelledException('cancelled');
      return result;
    } catch (e) {
      if (_cancelled) throw RequestCancelledException('cancelled');
      rethrow;
    }
  }
}

/// 请求被取消的异常
class RequestCancelledException implements Exception {
  final String key;
  RequestCancelledException(this.key);
  @override
  String toString() => 'Request cancelled: $key';
}