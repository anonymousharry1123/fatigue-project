import 'package:flutter/widgets.dart';

import 'src/app.dart';
import 'src/app_controller.dart';
import 'src/firebase_services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final firebase = await FirebaseRuntime.initialize();
  runApp(
    TonyoApp(
      controller: AppController(
        accountAuth: firebase?.auth,
        cloudRepository: firebase?.repository,
      ),
    ),
  );
}
