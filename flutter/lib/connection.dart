import 'dart:async';

import 'package:flutter/foundation.dart';

/// Stable app-facing connection phases. UI code should not infer lifecycle from
/// button colors or process fields.
enum ConnectionPhase {
  disconnected,
  preparing,
  startingCore,
  waitingForProxy,
  startingVpn,
  testingConnectivity,
  connected,
  reconnectBackoff,
  stopping,
  recovering,
  error,
}

@immutable
class ConnectionStateModel {
  const ConnectionStateModel({
    this.phase = ConnectionPhase.disconnected,
    this.message,
    this.reconnectAvailable = false,
  });

  final ConnectionPhase phase;
  final String? message;
  final bool reconnectAvailable;

  bool get busy =>
      phase != ConnectionPhase.disconnected && phase != ConnectionPhase.error;

  ConnectionStateModel copyWith({
    ConnectionPhase? phase,
    String? message,
    bool clearMessage = false,
    bool? reconnectAvailable,
  }) => ConnectionStateModel(
    phase: phase ?? this.phase,
    message: clearMessage ? null : message ?? this.message,
    reconnectAvailable: reconnectAvailable ?? this.reconnectAvailable,
  );
}

/// The lifecycle boundary between asynchronous core/native events and widgets.
class ConnectionController extends ValueNotifier<ConnectionStateModel> {
  ConnectionController() : super(const ConnectionStateModel());

  Future<void> _serial = Future.value();
  bool _disposed = false;

  Future<T> serialize<T>(Future<T> Function() action) {
    final result = _serial.then((_) => action());
    _serial = result.then<void>((_) {}, onError: (_, __) {});
    return result;
  }

  void transition(
    ConnectionPhase phase, {
    String? message,
    bool clearMessage = false,
    bool? reconnectAvailable,
  }) {
    if (_disposed) return;
    value = value.copyWith(
      phase: phase,
      message: message,
      clearMessage: clearMessage,
      reconnectAvailable: reconnectAvailable,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

@immutable
class NativeVpnState {
  const NativeVpnState(
    this.state, {
    required this.owned,
    this.error,
    this.reason,
  });
  final String state;
  final bool owned;
  final String? error;
  final String? reason;

  static NativeVpnState? from(dynamic arguments) {
    if (arguments is! Map) return null;
    final state = arguments['state'];
    if (state is! String) return null;
    return NativeVpnState(
      state,
      owned: arguments['owned'] == true,
      error: arguments['error'] is String ? arguments['error'] as String : null,
      reason: arguments['reason'] is String
          ? arguments['reason'] as String
          : null,
    );
  }
}
