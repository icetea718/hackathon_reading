import 'package:file_picker/file_picker.dart';

abstract class FilePickerService {
  Future<String?> pickBookFile();
}

class SystemFilePicker implements FilePickerService {
  const SystemFilePicker();

  @override
  Future<String?> pickBookFile() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['epub', 'txt', 'pdf'],
    );
    return file?.path;
  }
}
