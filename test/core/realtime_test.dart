import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:oneday_app/core/realtime.dart';

/// A socket the test drives by hand.
class _FakeSocket implements SocketTransport {
  final _in = StreamController<String>();
  final sent = <String>[];
  bool closed = false;

  @override
  Stream<String> get incoming => _in.stream;

  @override
  void send(String text) => sent.add(text);

  @override
  Future<void> close() async {
    closed = true;
    if (!_in.isClosed) unawaited(_in.close());
  }

  void receive(String text) => _in.add(text);

  /// The server went away.
  void drop() => unawaited(_in.close());
}

void main() {
  test('a frame survives encoding and parsing, and a heartbeat is not a frame', () {
    const frame = StompFrame(
      'SUBSCRIBE',
      headers: {'id': 'events', 'destination': '/user/queue/events'},
    );
    final parsed = StompFrame.tryParse(frame.encode())!;
    expect(parsed.command, 'SUBSCRIBE');
    expect(parsed.headers, frame.headers);
    expect(parsed.body, isEmpty);
    expect(StompFrame.tryParse(StompFrame.heartbeat), isNull);

    final message = StompFrame.tryParse(
      'MESSAGE\r\ndestination:/user/queue/events\r\n\r\n{"type":"notice","data":{}}\u0000',
    )!;
    expect(message.command, 'MESSAGE');
    expect(message.body, '{"type":"notice","data":{}}');
  });

  test('the socket address comes from the API address', () {
    expect(
      RealtimeClient.socketUrl('http://10.0.2.2:8080').toString(),
      'ws://10.0.2.2:8080/ws',
    );
    expect(
      RealtimeClient.socketUrl('https://api.oneday.example/').toString(),
      'wss://api.oneday.example/ws',
    );
  });

  test(
    'connects with the token, subscribes once connected, and delivers pushed events',
    () async {
      final socket = _FakeSocket();
      Uri? dialled;
      final client = RealtimeClient(
        url: Uri.parse('ws://api.test/ws'),
        accessToken: () async => 't1',
        connector: (url) async {
          dialled = url;
          return socket;
        },
        heartbeat: const Duration(hours: 1),
      );
      final events = <RealtimeEvent>[];
      client.events.listen(events.add);

      client.start();
      await pumpEventQueue();
      expect(dialled.toString(), 'ws://api.test/ws');
      final connect = StompFrame.tryParse(socket.sent.single)!;
      expect(connect.command, 'CONNECT');
      expect(connect.headers['Authorization'], 'Bearer t1');

      socket.receive('CONNECTED\nversion:1.2\n\n\u0000');
      await pumpEventQueue();
      final subscribe = StompFrame.tryParse(socket.sent.last)!;
      expect(subscribe.command, 'SUBSCRIBE');
      expect(subscribe.headers['destination'], '/user/queue/events');

      socket.receive('\n');
      socket.receive(
        'MESSAGE\ndestination:/user/queue/events\ncontent-type:application/json\n\n'
        '{"type":"message","data":{"conversationId":"c1"}}\u0000',
      );
      socket.receive('MESSAGE\n\nnot json\u0000');
      await pumpEventQueue();
      expect(events.single.type, 'message');
      expect(events.single.data['conversationId'], 'c1');

      await client.dispose();
      expect(socket.closed, isTrue);
    },
  );

  test(
    'reconnects with a fresh token when the socket closes, and stops once signed out',
    () async {
      final tokens = <String?>['t1', 't2', null];
      final sockets = <_FakeSocket>[];
      final client = RealtimeClient(
        url: Uri.parse('ws://api.test/ws'),
        accessToken: () async => tokens.removeAt(0),
        connector: (_) async {
          final socket = _FakeSocket();
          sockets.add(socket);
          return socket;
        },
        retryDelays: const [Duration.zero],
        heartbeat: const Duration(hours: 1),
      );

      client.start();
      await pumpEventQueue();
      expect(sockets, hasLength(1));

      sockets[0].drop();
      await pumpEventQueue();
      expect(sockets, hasLength(2));
      expect(
        StompFrame.tryParse(sockets[1].sent.single)!.headers['Authorization'],
        'Bearer t2',
      );

      sockets[1].drop();
      await pumpEventQueue();
      expect(sockets, hasLength(2), reason: 'signed out: no token, no socket');

      await client.dispose();
    },
  );
}
