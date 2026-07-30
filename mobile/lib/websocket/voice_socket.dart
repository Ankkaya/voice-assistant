import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:web_socket_channel/status.dart' as status;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../protocol/voice_event.dart';

abstract interface class VoiceSocketClient {
  Stream<VoiceEvent> get events;
  Stream<Uint8List> get audioChunks;
  Future<void> connect(Uri uri);
  void sendEvent(Map<String, Object> event);
  void sendAudio(Uint8List data);
  Future<void> close();
}

class VoiceSocket implements VoiceSocketClient {
  final _events = StreamController<VoiceEvent>.broadcast();
  final _audio = StreamController<Uint8List>.broadcast();

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _heartbeat;
  DateTime _lastReceived = DateTime.now();

  @override
  Stream<VoiceEvent> get events => _events.stream;

  @override
  Stream<Uint8List> get audioChunks => _audio.stream;

  @override
  Future<void> connect(Uri uri) async {
    await _closeConnection();
    final channel = WebSocketChannel.connect(uri);
    _channel = channel;
    try {
      await channel.ready.timeout(const Duration(seconds: 8));
    } on Object {
      await _closeConnection();
      rethrow;
    }
    _lastReceived = DateTime.now();
    _subscription = channel.stream.listen(
      _onMessage,
      onError: _events.addError,
      onDone: () {
        if (!_events.isClosed) {
          _events.addError(const VoiceSocketClosed());
        }
      },
      cancelOnError: false,
    );
    _heartbeat = Timer.periodic(const Duration(seconds: 15), (_) {
      if (DateTime.now().difference(_lastReceived) >
          const Duration(seconds: 30)) {
        _events.addError(TimeoutException('Voice socket heartbeat timed out'));
        unawaited(_closeConnection());
        return;
      }
      sendEvent(VoiceClientEvent.ping(DateTime.now().millisecondsSinceEpoch));
    });
  }

  void _onMessage(dynamic message) {
    _lastReceived = DateTime.now();
    if (message is String) {
      try {
        final body = jsonDecode(message) as Map<String, dynamic>;
        _events.add(VoiceEvent.fromJson(body));
      } on Object catch (error, stackTrace) {
        _events.addError(error, stackTrace);
      }
      return;
    }
    if (message is Uint8List) {
      _audio.add(message);
      return;
    }
    if (message is List<int>) {
      _audio.add(Uint8List.fromList(message));
    }
  }

  @override
  void sendEvent(Map<String, Object> event) {
    final channel = _channel;
    if (channel == null) {
      throw StateError('Voice socket is not connected');
    }
    channel.sink.add(jsonEncode(event));
  }

  @override
  void sendAudio(Uint8List data) {
    final channel = _channel;
    if (channel == null) {
      throw StateError('Voice socket is not connected');
    }
    channel.sink.add(data);
  }

  @override
  Future<void> close() async {
    await _closeConnection();
    await _events.close();
    await _audio.close();
  }

  Future<void> _closeConnection() async {
    _heartbeat?.cancel();
    _heartbeat = null;
    await _subscription?.cancel();
    _subscription = null;
    final channel = _channel;
    _channel = null;
    await channel?.sink.close(status.goingAway);
  }
}

class VoiceSocketClosed implements Exception {
  const VoiceSocketClosed();

  @override
  String toString() => 'Voice socket closed';
}
