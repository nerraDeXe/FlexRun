import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  
  group('Firebase Connection Tests', () {
    setUpAll(() async {
      // Initialize Firebase for testing
      await Firebase.initializeApp();
    });

    test('Firebase Core initializes', () async {
      expect(Firebase.apps.isNotEmpty, true);
      print('✓ Firebase Core initialized successfully');
    });

    test('Firebase Auth is available', () {
      final auth = FirebaseAuth.instance;
      expect(auth, isNotNull);
      print('✓ Firebase Auth instance created');
    });

    test('Cloud Firestore is available', () {
      final firestore = FirebaseFirestore.instance;
      expect(firestore, isNotNull);
      print('✓ Cloud Firestore instance created');
    });

    test('Firestore database connection', () async {
      try {
        final firestore = FirebaseFirestore.instance;
        // Try a test read from a non-existent collection (shouldn't fail, just return empty)
        final result = await firestore
            .collection('_test_connection')
            .limit(1)
            .get()
            .timeout(const Duration(seconds: 10));
        print('✓ Firestore connection successful');
        print('  Documents retrieved: ${result.docs.length}');
      } catch (e) {
        print('✗ Firestore connection failed: $e');
        rethrow;
      }
    });
  });
}
