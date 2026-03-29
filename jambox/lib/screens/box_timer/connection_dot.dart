import 'package:flutter/material.dart';
import '../../models/penalty_box_state.dart';

/// Connection status indicator dot.
class ConnectionDot extends StatelessWidget {
  final PenaltyBoxState state;

  const ConnectionDot({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    Color color;
    switch (state.connectionStatus) {
      case ConnectionStatus.connected:
        color = Colors.greenAccent;
      case ConnectionStatus.connecting:
        color = Colors.amber;
      case ConnectionStatus.disconnected:
        color = Colors.white24;
    }
    return Tooltip(
      message: state.connectionMessage,
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}
