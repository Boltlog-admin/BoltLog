import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:async';

class ConnectivityService {
  final Connectivity _connectivity = Connectivity();
  StreamController<bool> _connectionController = StreamController<bool>.broadcast();
  
  Stream<bool> get connectionStream => _connectionController.stream;
  bool _isConnected = true;

  ConnectivityService() {
    _init();
  }

  Future<void> _init() async {
    // Check initial connectivity
    final result = await _connectivity.checkConnectivity();
    _isConnected = result != ConnectivityResult.none;
    _connectionController.add(_isConnected);

    // Listen for connectivity changes
    _connectivity.onConnectivityChanged.listen((List<ConnectivityResult> results) {
      final result = results.isNotEmpty ? results.first : ConnectivityResult.none;
      final wasConnected = _isConnected;
      _isConnected = result != ConnectivityResult.none;
      
      // Only emit if status changed
      if (wasConnected != _isConnected) {
        _connectionController.add(_isConnected);
      }
    });
  }

  Future<bool> isConnected() async {
    final result = await _connectivity.checkConnectivity();
    _isConnected = result != ConnectivityResult.none;
    return _isConnected;
  }

  bool get currentStatus => _isConnected;

  void dispose() {
    _connectionController.close();
  }
}
