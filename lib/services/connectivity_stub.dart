import 'connectivity.dart';

Connectivity deviceConnectivity() => const _AlwaysOnline();

class _AlwaysOnline implements Connectivity {
  const _AlwaysOnline();

  @override
  bool get isOnline => true;

  @override
  Stream<bool> get changes => const Stream.empty();
}
