import 'api_client.dart';

class PushDeviceService {
  static final PushDeviceService _instance = PushDeviceService._();
  factory PushDeviceService() => _instance;
  PushDeviceService._();

  static const appStateForeground = 'foreground';
  static const appStateBackground = 'background';
  static const appStateUnknown = 'unknown';

  final ApiClient _api = ApiClient();

  Future<ApiResponse> registerDevice({
    required String deviceId,
    String platform = 'android',
    String provider = 'aliyun',
    String? manufacturer,
    String? model,
    String? appVersion,
  }) {
    final body = <String, dynamic>{
      'device_id': deviceId,
      'platform': platform,
      'provider': provider,
      if (manufacturer != null) 'manufacturer': manufacturer,
      if (model != null) 'model': model,
      if (appVersion != null) 'app_version': appVersion,
    };
    return _api.post('/push/devices/register', data: body);
  }

  Future<ApiResponse> unregisterDevice(String deviceId) {
    return _api.post('/push/devices/unregister', data: {
      'device_id': deviceId,
      'provider': 'aliyun',
    });
  }

  Future<ApiResponse> updateDeviceState({
    required String deviceId,
    required String appState,
    String provider = 'aliyun',
  }) {
    return _api.post('/push/devices/state', data: {
      'device_id': deviceId,
      'provider': provider,
      'app_state': appState,
    });
  }

  Future<ApiResponse> status() {
    return _api.get('/push/devices/status');
  }
}
