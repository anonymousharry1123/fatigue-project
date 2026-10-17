Keep Firebase values out of git and make an Xcode Run on a device connect without --dart-define-from-file.

In app/lib/src/firebase_options.dart, stop reading Firebase settings with String.fromEnvironment. Import a new file, app/lib/src/firebase_secrets.dart, and use its string constants for the existing fields (api key, web app id, iOS app id, messaging sender id, project id, auth domain, storage bucket, iOS bundle id). Leave TonyoFirebaseOptions behavior the same: selectAppId, isAppIdValidForRuntime, isConfigured, and currentPlatform, including the separate iOS app id and the offline path when values are empty.

Commit only app/lib/src/firebase_secrets.example.dart, with those same constants set to empty strings and a short comment to copy it to firebase_secrets.dart. Add **/firebase_secrets.dart to the repo .gitignore, next to config/firebase_options.json. Do not ignore the example file.

On this machine, create app/lib/src/firebase_secrets.dart from the existing ignored config/firebase_options.json. Do not print those values, do not put them in the README, and do not stage or commit firebase_secrets.dart.

A checkout without that file must be able to compile. Document the one-time copy of the example to firebase_secrets.dart under "Default launch with Firebase" in app/README.md: empty constants stay offline; filled constants are what Xcode compiles into the app. Mention the same one-time copy in app/docs/FIREBASE_SETUP.md.

Do not add an Xcode script. Do not commit real Firebase values.