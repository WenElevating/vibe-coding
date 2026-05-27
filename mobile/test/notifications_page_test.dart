import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_ai_cli_control/src/app/app_localization.dart';
import 'package:lan_ai_cli_control/src/ui/core/theme/theme.dart' as theme;
import 'package:lan_ai_cli_control/src/ui/features/notifications/notifications.dart';

void main() {
  testWidgets('notifications page shows empty state instead of sample notices',
      (tester) async {
    var backed = false;

    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en', 'US'),
      supportedLocales: appSupportedLocales,
      localizationsDelegates: appLocalizationsDelegates,
      theme: theme.buildAppTheme(),
      home: Scaffold(
        body: NotificationsPage(onBack: () => backed = true),
      ),
    ));

    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('No recent activity in this workspace'), findsOneWidget);
    expect(find.textContaining('Claude Code requests changes'), findsNothing);
    expect(find.text('Yesterday 14:22'), findsNothing);
    expect(find.text('10:58'), findsNothing);

    await tester.tap(find.text('Back'));

    expect(backed, isTrue);
  });
}
