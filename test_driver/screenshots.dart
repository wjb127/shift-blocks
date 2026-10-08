import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() => integrationDriver(
  onScreenshot: (name, bytes, [args]) async {
    final d = Directory('store-assets/screenshots')
      ..createSync(recursive: true);
    File('${d.path}/$name.png').writeAsBytesSync(bytes);
    return true;
  },
);
