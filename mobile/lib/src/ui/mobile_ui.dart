import 'package:flutter/material.dart';

import '../services/daemon_client.dart';
import '../shell/app_snapshot.dart';
import 'main_tabs_page.dart';
import 'mobile_connection_error_page.dart';
import 'mobile_loading_page.dart';

class MobileUi extends StatefulWidget {
  const MobileUi({super.key});

  @override
  State<MobileUi> createState() => _MobileUiState();
}

class _MobileUiState extends State<MobileUi> {
  late final DaemonClient _client;
  late Future<AppSnapshot> _snapshot;

  @override
  void initState() {
    super.initState();
    _client = DaemonClient(
      baseUri: Uri.parse('http://127.0.0.1:4317'),
      tokenStore: MemoryTokenStore(),
    );
    _snapshot = AppSnapshot.load(_client);
  }

  void _refresh() => setState(() => _snapshot = AppSnapshot.load(_client));

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppSnapshot>(
      future: _snapshot,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const MobileLoadingPage();
        }
        if (snapshot.hasError) {
          return MobileConnectionErrorPage(
            error: snapshot.error.toString(),
            onRetry: _refresh,
          );
        }
        return MainTabsPage(data: snapshot.requireData, client: _client);
      },
    );
  }
}
