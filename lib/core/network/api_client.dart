import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

import 'api_error.dart';
import 'token_store.dart';

/// The one HTTP client. It owns the session: it attaches the access token, refreshes it when it expires
/// (exactly once, however many requests notice at the same time), makes every POST safe to retry, and turns
/// every failure into an [ApiError].
class ApiClient {
  ApiClient({
    required String baseUrl,
    required this.tokens,
    Dio? dio,
    DateTime Function()? clock,
    this.retryDelays = const [
      Duration(milliseconds: 400),
      Duration(milliseconds: 1200),
    ],
  }) : _clock = clock ?? DateTime.now,
       _dio = dio ?? Dio() {
    _dio.options
      ..baseUrl = baseUrl
      ..connectTimeout = const Duration(seconds: 10)
      ..receiveTimeout = const Duration(seconds: 20)
      ..contentType = 'application/json'
      ..responseType = ResponseType.json;
    _dio.interceptors.add(
      InterceptorsWrapper(onRequest: _attachAuth, onError: _refreshOn401),
    );
  }

  final TokenStore tokens;
  final List<Duration> retryDelays;
  final DateTime Function() _clock;
  final Dio _dio;
  final _signedOut = StreamController<void>.broadcast();
  static const _uuid = Uuid();

  /// Fires when the session can't be recovered (refresh rejected): the app returns to sign-in.
  Stream<void> get signedOut => _signedOut.stream;

  Future<Tokens?>? _refreshing;

  /// Tests point the refresh call at a fake server.
  static HttpClientAdapter? refreshAdapterForTests;

  Future<dynamic> get(String path, {Map<String, Object?>? query}) => _send(
    () => _dio.get<dynamic>(path, queryParameters: _clean(query)),
    retryable: true,
  );

  /// [idempotencyKey]: pass one to make a user action safe to repeat (for example a resend after a crash); otherwise
  /// one is generated per call and reused across this call's own retries.
  Future<dynamic> post(
    String path, {
    Object? body,
    String? idempotencyKey,
    bool authenticated = true,
  }) {
    final key = idempotencyKey ?? _uuid.v4();
    return _send(
      () => _dio.post<dynamic>(
        path,
        data: body,
        options: Options(
          headers: {'Idempotency-Key': key},
          extra: {'anonymous': !authenticated},
        ),
      ),
      retryable:
          true, // safe: the server replays the first response for the same key
    );
  }

  Future<dynamic> put(
    String path, {
    Object? body,
    Map<String, String>? headers,
  }) => _send(
    () => _dio.put<dynamic>(
      path,
      data: body,
      options: Options(headers: headers),
    ),
    retryable: true,
  );

  Future<dynamic> patch(String path, {Object? body}) =>
      _send(() => _dio.patch<dynamic>(path, data: body), retryable: false);

  Future<dynamic> delete(String path, {Map<String, Object?>? query}) => _send(
    () => _dio.delete<dynamic>(path, queryParameters: _clean(query)),
    retryable: true,
  );

  Future<dynamic> _send(
    Future<Response<dynamic>> Function() call, {
    required bool retryable,
  }) async {
    for (var attempt = 0; ; attempt++) {
      try {
        final response = await call();
        return response.data;
      } on DioException catch (e) {
        final error = _toApiError(e);
        if (error.isNetwork && retryable && attempt < retryDelays.length) {
          await Future<void>.delayed(
            retryDelays[attempt] * (0.75 + math.Random().nextDouble() * 0.5),
          );
          continue;
        }
        throw error;
      }
    }
  }

  Future<void> _attachAuth(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (options.extra['anonymous'] != true) {
      final current = await tokens.read();
      if (current != null) {
        options.headers['Authorization'] = 'Bearer ${current.access}';
      }
    }
    handler.next(options);
  }

  Future<void> _refreshOn401(
    DioException e,
    ErrorInterceptorHandler handler,
  ) async {
    final options = e.requestOptions;
    final authorised = options.headers.containsKey('Authorization');
    if (e.response?.statusCode != 401 ||
        !authorised ||
        options.extra['retried'] == true) {
      return handler.next(e);
    }
    final refreshed = await _refreshOnce();
    if (refreshed == null) {
      return handler.next(e);
    }
    options.headers['Authorization'] = 'Bearer ${refreshed.access}';
    options.extra['retried'] = true;
    try {
      handler.resolve(await _dio.fetch<dynamic>(options));
    } on DioException catch (retryError) {
      handler.next(retryError);
    }
  }

  /// Single flight: concurrent 401s share one refresh. Two parallel refreshes would present the same rotating
  /// token twice, which the server treats as theft and ends the session for everyone.
  Future<Tokens?> _refreshOnce() =>
      _refreshing ??= _refresh().whenComplete(() => _refreshing = null);

  Future<Tokens?> _refresh() async {
    final current = await tokens.read();
    if (current == null) return null;
    try {
      final refresher = Dio(
        BaseOptions(
          baseUrl: _dio.options.baseUrl,
          contentType: 'application/json',
        ),
      );
      if (refreshAdapterForTests != null) {
        refresher.httpClientAdapter = refreshAdapterForTests!;
      }
      final response = await refresher.post<Map<String, dynamic>>(
        '/auth/refresh',
        data: {'refreshToken': current.refresh},
      );
      final next = Tokens.fromIssued(response.data!, _clock());
      await tokens.write(next);
      return next;
    } on DioException catch (e) {
      if (e.response != null) {
        // Rejected (expired, revoked, or reused): this session is over.
        await tokens.clear();
        _signedOut.add(null);
      }
      return null;
    }
  }

  ApiError _toApiError(DioException e) {
    final response = e.response;
    if (response == null) return const ApiError.network();
    return ApiError.fromProblem(response.statusCode ?? 0, response.data);
  }

  static Map<String, Object?>? _clean(Map<String, Object?>? query) =>
      query == null
      ? null
      : {
          for (final e in query.entries)
            if (e.value != null) e.key: e.value,
        };

  /// Adopts tokens from a sign-in or re-issue response.
  Future<Tokens> adopt(Map<String, dynamic> issuedToken) async {
    final current = issuedToken['refreshToken'] == null
        ? await tokens.read()
        : null;
    final t = Tokens.fromIssued(
      issuedToken,
      _clock(),
      keepRefresh: current?.refresh,
    );
    await tokens.write(t);
    return t;
  }

  void dispose() {
    _signedOut.close();
    _dio.close();
  }
}
