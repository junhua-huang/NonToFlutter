/// 通用 API 响应解析工具 — 抽取重复的 Map/List 数据解包逻辑
class ResponseParser {
  ResponseParser._();

  /// 从 API 响应 data 中提取 List，支持 data 为 List 或 Map（通过 key 提取）
  static List<dynamic> extractList(dynamic data, String key) {
    if (data is List) return data;
    if (data is Map) {
      final value = data[key];
      if (value is List) return value;
    }
    return [];
  }

  /// 提取 List 并映射为指定类型
  static List<T> parseList<T>(
    dynamic data,
    String key,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    return extractList(data, key)
        .map((e) => fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 从 data 中提取单层 Map
  static Map<String, dynamic>? extractMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    return null;
  }

  /// 从 data 中提取 bool 字段
  static bool extractBool(dynamic data, String key, {bool fallback = false}) {
    if (data is Map) return data[key] == true;
    return fallback;
  }
}