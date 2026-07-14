import 'package:flutter/material.dart';
import '/app/services/offline/connectivity_service.dart';

class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key, required this.connectivity});

  final ConnectivityService connectivity;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      initialData: connectivity.isOnline,
      stream: connectivity.onStatusChange,
      builder: (context, snapshot) {
        final online = snapshot.data ?? true;
        if (online) return const SizedBox.shrink();
        return Container(
          width: double.infinity,
          color: const Color(0xFF3B3321),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          child: const Text(
            "You're offline — changes will sync when you reconnect.",
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFFE1C16E), fontSize: 12),
          ),
        );
      },
    );
  }
}
