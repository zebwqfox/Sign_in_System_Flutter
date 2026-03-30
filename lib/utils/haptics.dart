import 'package:vibration/vibration.dart';

Future<void> shortPulse({int ms = 25}) async {
  final has = await Vibration.hasVibrator();
  if (has == true) {
    await Vibration.vibrate(duration: ms);
  }
}
