import 'dart:async';
import 'package:simple_recorder/app/log.dart';

class EventBus {
  static const String kBottomNavigationBarClicked = "BottomNavigationBarClicked";
  static EventBus? _instance;

  static EventBus get instance {
    _instance ??= EventBus();
    return _instance!;
  }

  final Map<String, StreamController> _streams = {};

  void emit<T>(String name, T data) {
    if (!_streams.containsKey(name)) {
      _streams[name] = StreamController.broadcast();
    }
    Log.d("Emit Event：$name\r\n$data");
    _streams[name]!.add(data);
  }

  StreamSubscription<dynamic> listen(String name, Function(dynamic)? onData) {
    if (!_streams.containsKey(name)) {
      _streams[name] = StreamController.broadcast();
    }
    return _streams[name]!.stream.listen(onData);
  }
}
