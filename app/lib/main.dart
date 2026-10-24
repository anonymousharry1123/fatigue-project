import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart';

import 'src/app.dart';
import 'src/app_controller.dart';
import 'src/firebase_services.dart';
import 'src/theme_controller.dart';
import 'src/raw_heart_rate_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final themeController = ThemeController();
  final firebaseInitialization = FirebaseRuntime.initialize();
  await themeController.load();
  final firebase = await firebaseInitialization;
  runApp(
    TonyoApp(
      themeController: themeController,
      controller: AppController(
        rawHeartRateStore:
            !kIsWeb &&
                {
                  TargetPlatform.iOS,
                  TargetPlatform.android,
                  TargetPlatform.macOS,
                }.contains(defaultTargetPlatform)
            ? SqliteRawHeartRateStore()
            : null,
        heartRateCloudStore: firebase?.heartRateCloudStore,
        accountAuth: firebase?.auth,
        cloudRepository: firebase?.repository,
        prepDataSource: firebase?.prepSource,
        energyModelMetadataWriter: firebase?.energyModelMetadataWriter,
      ),
    ),
  );
}
