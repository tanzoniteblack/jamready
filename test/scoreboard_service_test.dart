import 'dart:async';
import 'dart:convert';

import 'package:async/src/stream_sink_transformer.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:roller_derby_jam_timer/models/scoreboard_state.dart';
import 'package:roller_derby_jam_timer/services/scoreboard_service.dart';

class FakeWebSocketSink implements WebSocketSink {
  final List<dynamic> sent = [];
  final Completer<void> _done = Completer<void>();
  int? closeCode;
  String? closeReason;

  @override
  void add(dynamic data) {
    sent.add(data);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future addStream(Stream stream) async {
    await for (final data in stream) {
      add(data);
    }
  }

  @override
  Future close([int? closeCode, String? closeReason]) {
    this.closeCode = closeCode;
    this.closeReason = closeReason;
    if (!_done.isCompleted) {
      _done.complete();
    }
    return Future.value();
  }

  @override
  Future get done => _done.future;
}

class TestWebSocketChannel implements WebSocketChannel {
  TestWebSocketChannel({
    required StreamController<dynamic> incoming,
    required FakeWebSocketSink sink,
    Future<void>? ready,
  })  : _incoming = incoming,
        _sink = sink,
        _ready = ready ?? Future.value();

  final StreamController<dynamic> _incoming;
  final FakeWebSocketSink _sink;
  final Future<void> _ready;

  @override
  Stream get stream => _incoming.stream;

  @override
  WebSocketSink get sink => _sink;

  @override
  Future<void> get ready => _ready;

  @override
  String? get protocol => null;

  @override
  int? get closeCode => _sink.closeCode;

  @override
  String? get closeReason => _sink.closeReason;

  @override
  StreamChannel<S> cast<S>() {
    // TODO: implement cast
    throw UnimplementedError();
  }

  @override
  StreamChannel<dynamic> changeSink(StreamSink<dynamic> Function(StreamSink<dynamic>) change) {
    // TODO: implement changeSink
    throw UnimplementedError();
  }

  @override
  StreamChannel<dynamic> changeStream(Stream<dynamic> Function(Stream<dynamic>) change) {
    // TODO: implement changeStream
    throw UnimplementedError();
  }

  @override
  void pipe(StreamChannel<dynamic> other) {
    // TODO: implement pipe
  }

  @override
  StreamChannel<S> transform<S>(StreamChannelTransformer<S, dynamic> transformer) {
    // TODO: implement transform
    throw UnimplementedError();
  }

  @override
  StreamChannel<dynamic> transformSink(StreamSinkTransformer<dynamic, dynamic> transformer) {
    // TODO: implement transformSink
    throw UnimplementedError();
  }

  @override
  StreamChannel<dynamic> transformStream(StreamTransformer<dynamic, dynamic> transformer) {
    // TODO: implement transformStream
    throw UnimplementedError();
  }
}

void main() {
  test('connect registers paths and starts heartbeat', () {
    fakeAsync((async) {
      final state = ScoreboardState();
      final incoming = StreamController<dynamic>();
      final sink = FakeWebSocketSink();
      final channel = TestWebSocketChannel(
        incoming: incoming,
        sink: sink,
        ready: Future.value(),
      );

      final service = ScoreboardService(
        state,
        channelFactory: (uri) => channel,
      );

      unawaited(service.connect('http://example.com'));
      async.flushMicrotasks();

      expect(service.isConnected, isTrue);
      expect(state.connectionStatus, 'Connected');

      final registerMessage = sink.sent
          .map((message) => jsonDecode(message as String))
          .firstWhere((message) => message['action'] == 'Register');
      expect(registerMessage['paths'], isA<List<dynamic>>());

      async.elapse(const Duration(seconds: 30));
      async.flushMicrotasks();

      final hasPing = sink.sent
          .map((message) => jsonDecode(message as String))
          .any((message) => message['action'] == 'Ping');
      expect(hasPing, isTrue);

      incoming.close();
    });
  });

  test('updates state from incoming messages', () {
    fakeAsync((async) {
      final state = ScoreboardState();
      final incoming = StreamController<dynamic>();
      final sink = FakeWebSocketSink();
      final channel = TestWebSocketChannel(
        incoming: incoming,
        sink: sink,
        ready: Future.value(),
      );

      final service = ScoreboardService(
        state,
        channelFactory: (uri) => channel,
      );

      unawaited(service.connect('http://example.com'));
      async.flushMicrotasks();

      incoming.add(
        jsonEncode({
          'updates': {
            'ScoreBoard.CurrentGame.Team(1).Score': 5,
          },
        }),
      );
      async.flushMicrotasks();

      expect(state.team1.score, 5);

      incoming.close();
    });
  });

  test('reconnects with backoff and skips after manual disconnect', () {
    fakeAsync((async) {
      final state = ScoreboardState();
      final channels = <TestWebSocketChannel>[];
      StreamController<dynamic>? firstIncoming;

      final service = ScoreboardService(
        state,
        channelFactory: (uri) {
          final incoming = StreamController<dynamic>();
          final sink = FakeWebSocketSink();
          final channel = TestWebSocketChannel(
            incoming: incoming,
            sink: sink,
            ready: Future.value(),
          );
          channels.add(channel);
          firstIncoming ??= incoming;
          return channel;
        },
      );

      unawaited(service.connect('http://example.com'));
      async.flushMicrotasks();

      expect(channels.length, 1);

      firstIncoming!.close();
      async.flushMicrotasks();

      expect(state.connectionStatus.startsWith('Reconnecting in '), isTrue);

      async.elapse(const Duration(seconds: 2));
      async.flushMicrotasks();

      expect(channels.length, 2);

      service.disconnect();
      async.flushMicrotasks();

      async.elapse(const Duration(seconds: 10));
      async.flushMicrotasks();

      expect(channels.length, 2);
    });
  });
}
