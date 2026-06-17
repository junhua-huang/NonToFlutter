import 'dart:async';
import 'package:flutter/foundation.dart';

/// 请求管理器：去重 + 限并发 + 优先级 + TTL 缓存 + 可取消 + 超时
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

  /// 当前在管的请求（key → _Entry），包括执行中和 TTL 缓存中的
  final Map<String, _Entry<dynamic>> _inFlight = {};

  /// 等待队列（按优先级排序，高优先级在前）
  final List<_QueuedItem<dynamic>> _waitQueue = [];

  /// 递增序列号，用于 throttle 生成唯一 key
  int _seq = 0;

  RequestManager({
    this.maxConcurrent = 4,
    this.ttl = const Duration(seconds: 30),
  });

  // ── 公开 API ──

  /// 执行一个可去重的请求。
  ///
  /// - 如果 [key] 已有相同请求在执行中，直接复用其结果（等待同一个 Future）
  /// - 如果 [key] 最近在 [ttl] 内已完成，直接返回缓存结果
  /// - 如果当前并发数已满，排队等待
  /// - [priority] 高优先级请求排在队列前面（默认 0，值越大越优先）
  /// - [timeout] 超时后自动取消该请求
  ///
  /// [task] 返回 Future\<T\>，可以是任何类型。
  /// [key] 建议格式：`"METHOD:path"`，如 `"GET:/chat/conversations/2/messages"`。
  Future<T> execute<T>({
    required String key,
    required Future<T> Function() task,
    int priority = 0,
    bool bypassManager = false,
    Duration? timeout,
  }) {
    // 绕开管理器：直接执行，不占槽位、不去重
    if (bypassManager) return task();

    // 去重：如果有相同的 key 在执行中或 TTL 缓存中，复用结果
    final existing = _inFlight[key];
    if (existing != null) {
      if (existing.isDone) {
        // 已完成 → TTL 缓存命中或过期
        if (_isFresh(existing)) {
          debugPrint('[RequestManager] cache hit: $key');
          // 不能直接 as Future<T>，因为 _Entry<dynamic> 的 completer.future
          // 是 Future<dynamic>，Dart 泛型不变（invariant）导致强转失败。
          // 改用 then 回调转发结果，保证类型安全。
          return existing.completer.future.then((v) => v as T);
        }
        // 缓存已过期，移除后重新执行
        _inFlight.remove(key);
      } else {
        // 执行中 → 去重复用
        debugPrint('[RequestManager] dedup hit: $key');
        return existing.completer.future.then((v) => v as T);
      }
    }

    // 并发限制：如果当前并发已满，入队等待（按优先级）
    if (_running >= maxConcurrent) {
      debugPrint('[RequestManager] queued: $key (priority=$priority, running=$_running/$maxConcurrent)');
      final completer = Completer<T>();
      _insertQueued(_QueuedItem<T>(
        key: key,
        task: task,
        completer: completer,
        priority: priority,
      ));
      if (timeout != null) {
        _scheduleTimeout(key, timeout);
      }
      return completer.future;
    }

    // 立即执行
    return _run<T>(key, task, timeout: timeout);
  }

  /// 取消指定 key 的请求（排队中或执行中）。
  ///
  /// - 排队中：直接移除并 completeError
  /// - 执行中：标记完成并从 _inFlight 移除，释放槽位
  void cancel(String key) {
    // 先检查执行中
    final entry = _inFlight[key];
    if (entry != null && !entry.completed) {
      debugPrint('[RequestManager] cancel in-flight: $key');
      entry.finalize(); // 标记 completed，防 _onComplete 二次处理
      _running--;
      _inFlight.remove(key);
      if (!entry.completer.isCompleted) {
        entry.completer.completeError(RequestCancelledException(key));
      }
      _drainQueue();
      return;
    }

    // 清除已完成的 TTL 缓存条目，确保下次 retry 发起新请求
    if (entry != null) {
      debugPrint('[RequestManager] cancel cache entry: $key');
      _inFlight.remove(key);
    }

    // 再检查排队队列
    _waitQueue.removeWhere((item) {
      if (item.key == key) {
        debugPrint('[RequestManager] cancel queued: $key');
        if (!item.completer.isCompleted) {
          item.completer.completeError(RequestCancelledException(key));
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
  Future<T> throttle<T>(Future<T> Function() task, {Duration? timeout}) {
    final key = '_throttle_${++_seq}';
    return _executeNoDedup<T>(key, task, timeout: timeout);
  }

  /// 当前等待队列长度
  int get pendingCount => _waitQueue.length;

  /// 当前执行中请求数
  int get inFlightCount => _running;

  // ── 内部方法 ──

  /// 按优先级插入队列（优先级高的在前，同优先级先进先出）
  void _insertQueued(_QueuedItem<dynamic> item) {
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
  Future<T> _executeNoDedup<T>(String key, Future<T> Function() task, {Duration? timeout}) {
    if (_running >= maxConcurrent) {
      debugPrint('[RequestManager] throttled: $key (running=$_running/$maxConcurrent)');
      final completer = Completer<T>();
      _insertQueued(_QueuedItem<T>(
        key: key,
        task: task,
        completer: completer,
      ));
      if (timeout != null) {
        _scheduleTimeout(key, timeout);
      }
      return completer.future;
    }
    return _run<T>(key, task, timeout: timeout);
  }

  /// 立即执行一个任务
  Future<T> _run<T>(String key, Future<T> Function() task, {Duration? timeout}) {
    _running++;
    final completer = Completer<T>();
    final entry = _Entry<T>(
      key: key,
      completer: completer,
      startedAt: DateTime.now(),
    );
    _inFlight[key] = entry;

    debugPrint('[RequestManager] executing: $key (running=$_running/$maxConcurrent)');

    if (timeout != null) {
      _scheduleTimeout(key, timeout);
    }

    // 执行任务
    task().then(
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
  ///
  /// 不再立即从 _inFlight 移除，而是标记 isDone=true，
  /// 保留 entry 在 _inFlight 中作为 TTL 缓存。
  void _onComplete(String key, _Entry<dynamic> entry) {
    // 如果已经被 cancel() 处理过（entry.completed == true），直接返回
    if (entry.finalize()) return; // finalize 返回 true 表示已处理过

    _running--;
    entry.isDone = true;
    debugPrint('[RequestManager] completed: $key (running=$_running/$maxConcurrent, queue=${_waitQueue.length})');

    // 延迟清理：TTL 过期后从 _inFlight 移除
    Future.delayed(ttl, () {
      _inFlight.remove(key);
    });

    // 处理等待队列中的下一个请求
    _drainQueue();
  }

  /// 从等待队列中取出下一个请求执行
  void _drainQueue() {
    while (_running < maxConcurrent && _waitQueue.isNotEmpty) {
      final queued = _waitQueue.removeAt(0);

      // 如果该 key 已经有在途请求（执行中或 TTL 缓存），链到已有的 completer 上
      final existing = _inFlight[queued.key];
      if (existing != null) {
        _chainToInFlight(queued.key, queued.completer);
        continue;
      }

      // 执行排队请求
      _run<dynamic>(queued.key, queued.task).then(
        (v) { if (!queued.completer.isCompleted) queued.completer.complete(v); },
        onError: (e) {
          if (!queued.completer.isCompleted) {
            queued.completer.completeError(e);
          } else {
            debugPrint('[RequestManager] queued completer already completed (likely cancelled), error swallowed: $e');
          }
        },
      );
    }
  }

  /// 将等待中的 completer 链到已有 in-flight 请求的结果上
  void _chainToInFlight(String key, Completer<dynamic> waiter) {
    final existing = _inFlight[key];
    if (existing == null || waiter.isCompleted) return;
    debugPrint('[RequestManager] chain queued to in-flight: $key');
    existing.completer.future.then(
      (v) { if (!waiter.isCompleted) waiter.complete(v); },
      onError: (e) { if (!waiter.isCompleted) waiter.completeError(e); },
    );
  }

  /// 判断 TTL 缓存是否仍然新鲜
  bool _isFresh(_Entry<dynamic> entry) {
    return DateTime.now().difference(entry.startedAt) < ttl;
  }

  /// 为 key 设置超时定时器
  void _scheduleTimeout(String key, Duration timeout) {
    Future.delayed(timeout, () {
      // 只在请求仍未完成时才取消（避免已完成请求被误取消）
      final entry = _inFlight[key];
      if (entry != null && !entry.completer.isCompleted) {
        debugPrint('[RequestManager] timeout: $key (${timeout.inMilliseconds}ms)');
        cancel(key);
      }
    });
  }
}

// ── 内部类型 ──

class _Entry<T> {
  final String key;
  final Completer<T> completer;
  final DateTime startedAt;
  bool isDone = false;

  /// 防止 _onComplete 被重复调用（cancel 后防二次处理）
  bool completed = false;

  _Entry({
    required this.key,
    required this.completer,
    required this.startedAt,
  });

  /// 标记该 entry 已终结（由 cancel 或 _onComplete 调用）。
  /// 返回 true 表示此前已被终结过。
  bool finalize() {
    if (completed) return true;
    completed = true;
    return false;
  }
}

class _QueuedItem<T> {
  final String key;
  final Future<T> Function() task;
  final Completer<T> completer;
  final int priority;

  _QueuedItem({
    required this.key,
    required this.task,
    required this.completer,
    this.priority = 0,
  });
}

/// 请求被取消 / 超时的异常
class RequestCancelledException implements Exception {
  final String key;
  RequestCancelledException(this.key);
  @override
  String toString() => 'Request cancelled: $key';
}