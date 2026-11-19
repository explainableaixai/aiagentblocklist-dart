/// Base class for everything this package throws.
///
/// [status] is the HTTP status for answers from the server and null for
/// local problems (token, file name, network, JSON).
class AiAgentBlocklistException implements Exception {
  /// Creates an exception with a message and an optional HTTP status.
  const AiAgentBlocklistException(this.message, {this.status});

  /// Human readable description. Never contains the token.
  final String message;

  /// HTTP status, or null when no answer was received.
  final int? status;

  @override
  String toString() => status == null
      ? '$runtimeType: $message'
      : '$runtimeType($status): $message';
}

/// HTTP 404: the token or the file name is unknown.
class NotFoundException extends AiAgentBlocklistException {
  /// Creates a 404 exception.
  const NotFoundException(super.message) : super(status: 404);
}

/// HTTP 403: the subscription behind the token has ended or is paused.
class AccessEndedException extends AiAgentBlocklistException {
  /// Creates a 403 exception.
  const AccessEndedException(super.message) : super(status: 403);
}

/// Any other non-2xx answer.
class HttpStatusException extends AiAgentBlocklistException {
  /// Creates an exception for an unexpected status.
  const HttpStatusException(super.message, {required int super.status});
}

/// The token is missing or is not 32 letters and digits. Thrown before any request.
class TokenException extends AiAgentBlocklistException {
  /// Creates a token exception.
  const TokenException(super.message);
}
