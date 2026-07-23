/// 发送失败详情
///
/// 表示一条业务消息已经进入终态失败，不应继续重试。
library;

/// 可靠发送的终态失败信息。
class SendFailure {
  final String clientMsgId;
  final int status;
  final String? code;
  final bool retryable;
  final String message;

  const SendFailure({
    required this.clientMsgId,
    required this.status,
    this.code,
    required this.retryable,
    required this.message,
  });

  @override
  String toString() =>
      'SendFailure(clientMsgId: $clientMsgId, status: $status, code: $code, retryable: $retryable)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SendFailure &&
          other.clientMsgId == clientMsgId &&
          other.status == status &&
          other.code == code &&
          other.retryable == retryable &&
          other.message == message;

  @override
  int get hashCode => Object.hash(
        clientMsgId,
        status,
        code,
        retryable,
        message,
      );
}
