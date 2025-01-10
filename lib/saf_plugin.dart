import 'dart:io';
import 'package:flutter/services.dart';
import 'package:file_picker_ohos/file_picker_ohos.dart';

class SAFPlugin {
  static const platform = const MethodChannel('com.perol.dev/saf');

  static Future<String?> createFile(String name, String type) async {
    if (Platform.isOhos) {
      return await FilePicker.platform.saveFile(
        fileName: name,
        type: FileType.any
      );
    }

    final result = await platform
        .invokeMethod("createFile", {'name': name, 'mimeType': type});
    if (result != null) {
      return result;
    }
    return null;
  }

  static Future<void> writeUri(String uri, Uint8List data) async {
    if (Platform.isOhos) {
      return await FilePicker.platform.writeFile(
        uri: uri,
        bytes: data
      );
    }
    return platform.invokeMethod("writeUri", {'uri': uri, 'data': data});
  }

  static Future<Uint8List?> openFile() async {
    if (Platform.isOhos) {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ["json"],
        withData: true
      );
      if (result != null)
        return result.files.first.bytes;
      else 
        return null;
    }

    return platform.invokeMethod<Uint8List>("openFile", {'type': "application/json"});
  }
}
