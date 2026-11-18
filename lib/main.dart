import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'screens/quiz_screen.dart';
import 'screens/sign_in_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Object? initError;
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } catch (e) {
    initError = e;
  }
  runApp(ScienceSignalApp(initError: initError));
}

class ScienceSignalApp extends StatelessWidget {
  const ScienceSignalApp({super.key, this.initError});
  final Object? initError;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Science Signal',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      home: initError != null ? _InitErrorScreen(error: initError!) : const _AuthGate(),
    );
  }
}

class _InitErrorScreen extends StatelessWidget {
  const _InitErrorScreen({required this.error});
  final Object error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Firebase is not configured')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Text('Firebase failed to initialise.\n\n$error\n\n'
            'Run "flutterfire configure" at the project root and rebuild.'),
      ),
    );
  }
}

class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final user = snap.data;
        if (user == null) return const SignInScreen();
        // Keyed by UID: a different user always gets a brand-new controller,
        // so an old user's late response can never land on the new screen.
        return QuizScreen(key: ValueKey(user.uid), user: user);
      },
    );
  }
}
