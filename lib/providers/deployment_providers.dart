import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nonto/models/deployment.dart';
import 'package:nonto/providers/auth_notifier.dart';
import 'package:nonto/services/api/deployment_service.dart';

final deploymentWebProvider = Provider<bool>((ref) => kIsWeb);
final deploymentSessionProvider =
    Provider<({String? token, String? userId})>((ref) {
  final auth = ref.watch(authProvider);
  return (
    token: auth.isLoggedIn ? auth.token : null,
    userId: auth.user?.id.toString()
  );
});
final deploymentServiceProvider =
    Provider.autoDispose<DeploymentService>((ref) {
  ref.watch(deploymentSessionProvider);
  final service = DeploymentService(
      readToken: () => ref.read(deploymentSessionProvider).token);
  ref.onDispose(service.dispose);
  return service;
});
final deploymentCapabilitiesProvider =
    FutureProvider.autoDispose<DeploymentCapabilities>((ref) {
  final session = ref.watch(deploymentSessionProvider);
  if (!ref.watch(deploymentWebProvider) || session.token == null) {
    return const DeploymentCapabilities(
        enabled: false, canDeploy: false, canConfigure: false);
  }
  return ref.watch(deploymentServiceProvider).capabilities();
});
