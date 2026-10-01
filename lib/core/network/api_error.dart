/// Every failure the app shows comes through here. The backend answers errors as RFC 9457 problem details with
/// a stable [code]; the app switches on [code] and shows [detail], which is written for people.
class ApiError implements Exception {
  const ApiError({
    required this.status,
    required this.code,
    required this.detail,
    this.requestId,
    this.extras = const {},
  });

  /// Couldn't reach the server (offline, timeout, DNS). Safe to offer "Try again".
  const ApiError.network([
    this.detail =
        'You seem to be offline. Check your connection and try again.',
  ]) : status = 0,
       code = 'NETWORK',
       requestId = null,
       extras = const {};

  final int status;
  final String code;
  final String detail;

  /// Quote this to support: it finds the exact server logs.
  final String? requestId;

  /// Extra machine-readable fields, e.g. `tone` on EMPATHY_CHECK, `missing` on DEVICE_LIST_MISMATCH.
  final Map<String, Object?> extras;

  bool get isNetwork => code == 'NETWORK';

  bool get isUnauthorized => status == 401;

  factory ApiError.fromProblem(int status, Object? body) {
    if (body is Map) {
      final known = {
        'type',
        'title',
        'status',
        'detail',
        'instance',
        'code',
        'requestId',
      };
      return ApiError(
        status: status,
        code: (body['code'] as String?) ?? 'HTTP_$status',
        detail:
            (body['detail'] as String?) ??
            'Something went wrong. Please try again.',
        requestId: body['requestId'] as String?,
        extras: {
          for (final e in body.entries)
            if (!known.contains(e.key)) e.key.toString(): e.value,
        },
      );
    }
    return ApiError(
      status: status,
      code: 'HTTP_$status',
      detail: 'Something went wrong. Please try again.',
    );
  }

  @override
  String toString() =>
      'ApiError($status $code: $detail${requestId == null ? '' : ' [$requestId]'})';
}
