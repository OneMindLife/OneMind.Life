// Stub file for when Firebase is not configured.
// Generate the real firebase_options.dart by running: flutterfire configure
//
// See: https://firebase.flutter.dev/docs/cli/

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

/// Stub Firebase options when not configured.
/// Throws an error explaining how to set up Firebase.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    throw UnsupportedError(
      'Firebase is not configured. Run `flutterfire configure` to generate firebase_options.dart',
    );
  }
}
