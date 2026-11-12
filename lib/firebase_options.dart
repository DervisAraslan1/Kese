import 'package:firebase_core/firebase_core.dart';

// Identifies the Firebase project; none of this is secret. Access is decided
// by firestore.rules, not by these values.
const firebaseOptions = FirebaseOptions(
  apiKey: 'AIzaSyAHQYqlaeUZVntKj3ksvUOxK2UzLKhOgDo',
  appId: '1:785211615704:android:ea676d850cb96567506aad',
  messagingSenderId: '785211615704',
  projectId: 'kese-butce',
);

/// The project's web OAuth client, which Google sign-in issues tokens for.
const googleServerClientId =
    '785211615704-0ibo2k7qjrp05r5jp4nlnp2r5g619ogj.apps.googleusercontent.com';
