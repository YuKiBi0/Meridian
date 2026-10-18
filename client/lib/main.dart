import 'package:flutter/widgets.dart';

import 'core/connection.dart';
import 'core/countdown.dart';
import 'settings.dart';
import 'ui/app.dart';
import 'ui/l10n.dart';
import 'window/window_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await Settings.load();
  final window = WindowController();
  await window.init(Strings.of(settings.lang).appName);
  runApp(MeridianApp(
    settings: settings,
    connection: ServerConnection(Countdown()),
    window: window,
  ));
}
