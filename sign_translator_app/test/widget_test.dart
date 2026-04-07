// This is a basic Flutter widget test for Sign Language Translator.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:camera/camera.dart';
import 'package:sign_translator_app/main.dart';
import 'package:sign_translator_app/screens/camera_screen.dart';

void main() {
  testWidgets('App builds CameraScreen smoke test', (WidgetTester tester) async {
    // Mock cameras for test
    final mockCameras = <CameraDescription>[];

    // Build our app and trigger a frame.
    await tester.pumpWidget(MyApp(cameras: mockCameras));

    // Verify app builds without crashing
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(CameraScreen), findsOneWidget);
  });
}

