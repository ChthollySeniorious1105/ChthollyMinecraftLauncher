import 'dart:io';

/// True under `flutter test`.
bool isFlutterTest() => Platform.environment.containsKey('FLUTTER_TEST');
