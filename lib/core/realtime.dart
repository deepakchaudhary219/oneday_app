import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

/// Something the server pushed: `{"type": "message", "data": {...}}`. Events are best-effort hints; the HTTP API
/// stays the source of truth, so screens re-fetch rather than trust an event's payload for anything but chat.
class RealtimeEvent {
  const RealtimeEvent(this.type, this.data);

  final String type;
  final Map<String, dynamic> data;

  static RealtimeEvent? tryParse(String body) {
    try {
      final json = jsonDecode(body);
      if (json is! Map || json['type'] is! String) return null;
      final data = json['data'];
      return RealtimeEvent(
        json['type'] as String,
        data is Map ? data.cast<String, dynamic>() : const {},
      );
    } on FormatException {
      return null;
    }
  }
}

/// One STOMP 1.2 frame. The app needs four: CONNECT and SUBSCRIBE out, CONNECTED and MESSAGE in.
class StompFrame {
  const StompFrame(this.command, {this.headers = const {}, this.body = ''});

  final String command;
  final Map<String, String> headers;
  final String body;

  /// A heartbeat is a bare newline, not a frame.
  static const heartbeat = '\n';

  String encode() {
    final out = StringBuffer(command)..write('\n');
    headers.forEach((key, value) => out.write('$key:$value\n'));
    out
      ..write('\n')
      ..write(body)
      ..write('\u0000');
    return out.toString();
  }

  /// Null for a heartbeat or anything that isn't a frame.
  static StompFrame? tryParse(String text) {
    var raw = text;
    final end = raw.indexOf('\u0000');
    if (end >= 0) raw = raw.substring(0, end);
    raw = raw.replaceAll('\r\n', '\n');
    while (raw.startsWith('\n')) {
      raw = raw.substring(1);
    }
    if (raw.isEmpty) return null;
    final split = raw.indexOf('\n\n');
    final head = split < 0 ? raw : raw.substring(0, split);
    final body = split < 0 ? '' : raw.substring(split + 2);
    final lines = head.split('\n');
    final headers = <String, String>{};
    for (final line in lines.skip(1)) {
      final colon = line.indexOf(':');
      // The first occurrence of a header wins (STOMP 1.2).
      if (colon > 0) {
        headers.putIfAbsent(
          line.substring(0, colon),
          () => line.substring(colon + 1),
        );
      }
    }
    return StompFrame(lines.first.trim(), headers: headers, body: body);
  }
}

/// A text socket, small enough to fake in tests.
abstract interface class SocketTransport {
  Stream<String> get incoming;

  void send(String text);

  Future<void> close();
}

typedef SocketConnector = Future<SocketTransport> Function(Uri url);

class _IoSocket implements SocketTransport {
  _IoSocket(this._socket);

  final WebSocket _socket;

  @override
  Stream<String> get incoming =>
      _socket.where((m) => m is String).cast<String>();

  @override
  void send(String text) => _socket.add(text);

  @override
  Future<void> close() => _socket.close();
}

Future<SocketTransport> connectIoSocket(Uri url) async =>
    _IoSocket(await WebSocket.connect(url.toString()));

/// The receive-only socket (STOMP at `/ws`). It authenticates with the access token on CONNECT, subscribes to
/// the one allowed destination, and reconnects with a fresh token when the socket closes (the server closes it
/// at token expiry and on sign-out). Every write stays on the HTTP API.
class RealtimeClient {
  RealtimeClient({
    required this.url,
    required this.accessToken,
    this.connector = connectIoSocket,
    this.retryDelays = const [
      Duration(seconds: 2),
      Duration(seconds: 5),
      Duration(seconds: 15),
      Duration(seconds: 30),
    ],
    this.heartbeat = const Duration(seconds: 20),
  });

  /// `ws://` or `wss://` … `/ws`.
  final Uri url;

  /// A token that is still valid, or null when signed out (the client then stops).
  final Future<String?> Function() accessToken;
  final SocketConnector connector;
  final List<Duration> retryDelays;
  final Duration heartbeat;

  static const destination = '/user/queue/events';

  final _events = StreamController<RealtimeEvent>.broadcast();
  final _connected = StreamController<void>.broadcast();
  SocketTransport? _socket;
  StreamSubscription<String>? _incoming;
  Timer? _beat;
  Timer? _retry;
  int _failures = 0;
  bool _running = false;

  Stream<RealtimeEvent> get events => _events.stream;

  /// Fires after every (re)connection: the moment to re-fetch what may have been missed.
  Stream<void> get connected => _connected.stream;

  /// From the API's base URL: `http://host:8080` becomes `ws://host:8080/ws`.
  static Uri socketUrl(String apiBaseUrl) {
    final base = Uri.parse(apiBaseUrl);
    final root = base.path.endsWith('/')
        ? base.path.substring(0, base.path.length - 1)
        : base.path;
    return base.replace(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      path: '$root/ws',
    );
  }

  void start() {
    if (_running) return;
    _running = true;
    unawaited(_open());
  }

  Future<void> stop() async {
    _running = false;
    _retry?.cancel();
    await _drop();
  }

  Future<void> dispose() async {
    await stop();
    await _events.close();
    await _connected.close();
  }

  Future<void> _open() async {
    if (!_running) return;
    try {
      final token = await accessToken();
      if (token == null) {
        _running = false; // signed out: nothing to listen for
        return;
      }
      final socket = await connector(url);
      if (!_running) {
        await socket.close();
        return;
      }
      _socket = socket;
      _incoming = socket.incoming.listen(
        _received,
        onError: (Object _) => _lost(),
        onDone: _lost,
        cancelOnError: true,
      );
      socket.send(
        StompFrame(
          'CONNECT',
          headers: {
            'accept-version': '1.2',
            'host': url.host,
            'heart-beat':
                '${heartbeat.inMilliseconds},${heartbeat.inMilliseconds}',
            'Authorization': 'Bearer $token',
          },
        ).encode(),
      );
    } catch (_) {
      // Offline, refused, or a platform without sockets: try again later, quietly.
      _lost();
    }
  }

  void _received(String text) {
    final frame = StompFrame.tryParse(text);
    if (frame == null) return;
    switch (frame.command) {
      case 'CONNECTED':
        _failures = 0;
        _socket?.send(
          const StompFrame(
            'SUBSCRIBE',
            headers: {'id': 'events', 'destination': destination},
          ).encode(),
        );
        _beat?.cancel();
        _beat = Timer.periodic(
          heartbeat,
          (_) => _socket?.send(StompFrame.heartbeat),
        );
        if (!_connected.isClosed) _connected.add(null);
      case 'MESSAGE':
        final event = RealtimeEvent.tryParse(frame.body);
        if (event != null && !_events.isClosed) _events.add(event);
      case 'ERROR':
        _lost();
    }
  }

  void _lost() {
    unawaited(_drop());
    if (!_running) return;
    final delay = retryDelays.isEmpty
        ? Duration.zero
        : retryDelays[math.min(_failures, retryDelays.length - 1)];
    _failures++;
    _retry?.cancel();
    _retry = Timer(delay, () => unawaited(_open()));
  }

  Future<void> _drop() async {
    _beat?.cancel();
    _beat = null;
    final incoming = _incoming;
    final socket = _socket;
    _incoming = null;
    _socket = null;
    await incoming?.cancel();
    try {
      await socket?.close();
    } catch (_) {
      // Already gone.
    }
  }
}
