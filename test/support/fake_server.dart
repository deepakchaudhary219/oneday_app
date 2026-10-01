import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// A scripted server: each request is answered by [handler], and every request is recorded.
class FakeServer implements HttpClientAdapter {
  FakeServer(this.handler);

  final Future<(int, Object?)> Function(RequestOptions) handler;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final (status, body) = await handler(options);
    if (status == 0) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'offline',
      );
    }
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Map<String, Object> issued(String access, String refresh) => {
  'token': access,
  'refreshToken': refresh,
  'expiresInSeconds': 900,
  'verified': true,
};
