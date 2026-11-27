import 'dart:async';

import 'package:projectsais/services/connectivity.dart';

/// A connection a test switches on and off.
class FakeConnectivity implements Connectivity {
  FakeConnectivity({bool online = true}) : _online = online;

  bool _online;
  final _changes = StreamController<bool>.broadcast(sync: true);

  @override
  bool get isOnline => _online;

  @override
  Stream<bool> get changes => _changes.stream;

  void set(bool online) {
    if (online == _online) return;
    _online = online;
    _changes.add(online);
  }
}
