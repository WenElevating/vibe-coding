import 'package:flutter/material.dart';

import 'core/theme/theme.dart' as theme;
import 'mobile_ui_frame.dart';

class MobileLoadingPage extends StatelessWidget {
  const MobileLoadingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: MobileUiFrame(
        child: Center(
          child: CircularProgressIndicator(color: theme.purple),
        ),
      ),
    );
  }
}
