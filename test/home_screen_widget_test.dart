import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:objectdetector/main.dart';
import 'package:objectdetector/object_recognition_app.dart';
import 'package:objectdetector/voice_interaction_screen.dart';

// Mocking ObjectRecognitionApp and VoiceInteractionScreen to avoid camera initialization
class MockObjectRecognitionApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Object Recognition Mock')),
      body: Center(child: Text('Mock Object Detection Screen')),
    );
  }
}

class MockVoiceInteractionScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Voice Interaction Mock')),
      body: Center(child: Text('Mock Voice Command Screen')),
    );
  }
}

void main() {
  testWidgets('HomeScreen has buttons and navigates to screens', (WidgetTester tester) async {
    // Override the original routes with mock screens to avoid camera issues
    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(),
      routes: {
        '/object_detection': (context) => MockObjectRecognitionApp(),
        '/voice_command': (context) => MockVoiceInteractionScreen(),
      },
    ));

    // Verify the HomeScreen displays the buttons
    expect(find.text('Object Detection'), findsOneWidget);
    expect(find.text('Voice Command'), findsOneWidget);

    // Tap the 'Object Detection' button
    await tester.tap(find.text('Object Detection'));
    await tester.pumpAndSettle(); // Wait for the navigation to complete

    // Verify that we navigated to the MockObjectRecognitionApp screen
    expect(find.text('Mock Object Detection Screen'), findsOneWidget);

    // Go back to HomeScreen
    await tester.pageBack();
    await tester.pumpAndSettle();

    // Tap the 'Voice Command' button
    await tester.tap(find.text('Voice Command'));
    await tester.pumpAndSettle(); // Wait for the navigation to complete

    // Verify that we navigated to the MockVoiceInteractionScreen
    expect(find.text('Mock Voice Command Screen'), findsOneWidget);
  });
}
