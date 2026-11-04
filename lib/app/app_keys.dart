import 'package:flutter/material.dart';

/// App-wide hooks used for notifications that may arrive while the reader is
/// showing any route.
final appScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
final appNavigatorKey = GlobalKey<NavigatorState>();
