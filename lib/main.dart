import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:fake_strava/tracking/services/tracking_background_service.dart';

import 'package:fake_strava/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Object? bootstrapError;
  if (!kIsWeb) {
    try {
      await Firebase.initializeApp();
      await TrackingBackgroundService().initialize();
    } catch (error) {
      bootstrapError = error;
    }
  }
  runApp(FakeStravaApp(bootstrapError: bootstrapError));
}

