import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'connectivity.dart';

Connectivity deviceConnectivity() => _BrowserConnectivity();

class _BrowserConnectivity implements Connectivity {
  late final StreamController<bool> _changes =
      StreamController<bool>.broadcast(
        onListen: _start,
        onCancel: _stop,
      );
  JSFunction? _onOnline;
  JSFunction? _onOffline;

  @override
  bool get isOnline => web.window.navigator.onLine;

  @override
  Stream<bool> get changes => _changes.stream;

  void _start() {
    _onOnline = ((web.Event _) => _changes.add(true)).toJS;
    _onOffline = ((web.Event _) => _changes.add(false)).toJS;
    web.window.addEventListener('online', _onOnline);
    web.window.addEventListener('offline', _onOffline);
  }

  void _stop() {
    if (_onOnline != null) web.window.removeEventListener('online', _onOnline);
    if (_onOffline != null) {
      web.window.removeEventListener('offline', _onOffline);
    }
    _onOnline = null;
    _onOffline = null;
  }
}
