import 'package:connectivity_plus/connectivity_plus.dart';

/// Emits once each time the device regains a network path.
Stream<void> connectivityRegained() async* {
  final connectivity = Connectivity();
  var online = true;
  await for (final results in connectivity.onConnectivityChanged) {
    final nowOnline = results.any(
      (result) => result != ConnectivityResult.none,
    );
    if (nowOnline && !online) yield null;
    online = nowOnline;
  }
}
