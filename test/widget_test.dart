import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_chat_pro/main.dart';

void main() {
  testWidgets('shows the Wifi Chat Pro shell', (tester) async {
    await tester.pumpWidget(const WifiChatProApp());
    await tester.pump();

    expect(find.text('Wifi Chat Pro'), findsWidgets);
    expect(find.text('Nearby devices'), findsOneWidget);
  });
}
