import 'package:permission_handler/permission_handler.dart';

Future<void> requestPermissions() async {
  await Permission.locationAlways.request();
  await Permission.notification.request();
}
