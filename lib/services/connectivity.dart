import 'connectivity_stub.dart'
    if (dart.library.js_interop) 'connectivity_web.dart'
    as impl;

/// Whether the device has a connection, as far as the browser knows
/// (`navigator.onLine` and its `online`/`offline` events). The browser can
/// say "online" with no real internet (a Wi-Fi login page, a virtual network
/// adapter), never the other way round: "offline" is certain. Builds other
/// than the web always report online.
abstract class Connectivity {
  bool get isOnline;

  /// Fires with the new value whenever it changes.
  Stream<bool> get changes;

  /// The device's own: the browser on the web, always online elsewhere.
  static Connectivity device() => impl.deviceConnectivity();
}
