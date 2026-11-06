import 'package:image_picker/image_picker.dart';

abstract class AvatarRepository {
  Future<Map<String, dynamic>> uploadAvatar(XFile file, {bool Function()? isSessionCurrent});
  Future<Map<String, dynamic>> useGoogleAvatar({bool Function()? isSessionCurrent});
}

