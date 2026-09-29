import 'dart:math';

import 'package:flutter/foundation.dart';

/// 一条 MCP 会话（Streamable HTTP，Mcp-Session-Id 标识）。
class McpSession {
  McpSession({
    required this.id,
    required this.clientName,
    required this.clientVersion,
    required this.protocolVersion,
    required this.createdAt,
  })  : lastSeenAt = createdAt,
        allowedTools = <String>{};

  final String id;
  final String clientName;
  final String clientVersion;
  final String protocolVersion;
  final DateTime createdAt;
  DateTime lastSeenAt;

  /// 「本次会话内允许」的确认白名单（工具名）。
  final Set<String> allowedTools;

  String get clientLabel {
    final name = clientName.isEmpty ? 'unknown' : clientName;
    if (clientVersion.isEmpty) return name;
    return '$name $clientVersion';
  }

  bool isIdleBeyond(Duration maxIdle) =>
      DateTime.now().difference(lastSeenAt) > maxIdle;
}

/// 会话存储：创建、查找、心跳与闲置回收（计划 §2.2 / §4）。
///
/// 会话仅存在于内存中；服务关闭后全部失效。
class McpSessionStore extends ChangeNotifier {
  static const Duration idleTimeout = Duration(minutes: 60);

  final Random _random = Random.secure();
  final Map<String, McpSession> _sessions = {};

  List<McpSession> get sessions => List.unmodifiable(_sessions.values);
  int get activeCount => _sessions.length;

  McpSession create({
    required String clientName,
    required String clientVersion,
    required String protocolVersion,
  }) {
    String id;
    do {
      id = _generateId();
    } while (_sessions.containsKey(id));
    final session = McpSession(
      id: id,
      clientName: clientName,
      clientVersion: clientVersion,
      protocolVersion: protocolVersion,
      createdAt: DateTime.now(),
    );
    _sessions[id] = session;
    notifyListeners();
    return session;
  }

  McpSession? find(String? id) => id == null ? null : _sessions[id];

  void touch(String id) {
    final session = _sessions[id];
    if (session == null) return;
    session.lastSeenAt = DateTime.now();
  }

  /// 返回被终止的会话（未找到返回 null）。
  McpSession? terminate(String id) {
    final session = _sessions.remove(id);
    if (session != null) notifyListeners();
    return session;
  }

  /// 回收闲置会话，返回回收数量。
  int sweepIdle() {
    final stale = _sessions.values
        .where((session) => session.isIdleBeyond(idleTimeout))
        .map((session) => session.id)
        .toList();
    for (final id in stale) {
      _sessions.remove(id);
    }
    if (stale.isNotEmpty) notifyListeners();
    return stale.length;
  }

  void clearAll() {
    if (_sessions.isEmpty) return;
    _sessions.clear();
    notifyListeners();
  }

  String _generateId() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    const hex = '0123456789abcdef';
    return bytes.map((byte) => hex[byte >> 4] + hex[byte & 15]).join();
  }
}
