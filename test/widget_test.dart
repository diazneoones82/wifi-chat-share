import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_chat_share/main.dart';

void main() {
  testWidgets('shows the Wifi Chat Share shell', (tester) async {
    await tester.pumpWidget(const WifiChatShareApp());
    await tester.pump();

    expect(find.text('Wifi Chat Share'), findsWidgets);
    expect(find.text('Nearby devices'), findsOneWidget);
  });
}
