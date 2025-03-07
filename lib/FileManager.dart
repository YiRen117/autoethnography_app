import 'dart:io';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:amplify_storage_s3/amplify_storage_s3.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';

class FileManager {
  final ImagePicker _picker = ImagePicker();
  final String userSub;

  FileManager(this.userSub);

  /// **列出 S3 中的文件**
  Future<List<StorageItem>> listFiles() async {
    try {
      final result = await Amplify.Storage.list(
        path: StoragePath.fromString("uploads/$userSub/"),
        options: const StorageListOptions(
          pageSize: 50,
          pluginOptions: S3ListPluginOptions(
            excludeSubPaths: true,
            delimiter: '/',
          ),
        ),
      ).result;
      return result.items;
    } catch (e) {
      safePrint("❌ 获取文件失败: $e");
      return [];
    }
  }

  /// **上传文件到 S3**
  Future<void> uploadFile(BuildContext context, Function refreshFiles) async {
    try {
      final pickedFile = await _picker.pickImage(source: ImageSource.gallery);
      if (pickedFile == null) return;

      File file = File(pickedFile.path);
      String key = "uploads/$userSub/${file.path.split('/').last}";

      await Amplify.Storage.uploadFile(
        localFile: AWSFile.fromPath(file.path),
        path: StoragePath.fromString(key),
      ).result;

      safePrint("✅ 文件上传成功: $key");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("✅ 文件上传成功")),
      );

      refreshFiles();
    } catch (e) {
      safePrint("❌ 上传失败: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("❌ 上传失败: $e")),
      );
    }
  }

  /// **删除 S3 中的文件**
  Future<void> deleteFile(BuildContext context, String key, Function refreshFiles) async {
    try {
      await Amplify.Storage.remove(
        path: StoragePath.fromString(key),
      ).result;

      safePrint("✅ 文件删除成功: $key");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("✅ 文件删除成功: ${key.split('/').last}")),
      );

      refreshFiles();
    } catch (e) {
      safePrint("❌ 删除失败: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("❌ 删除失败: $e")),
      );
    }
  }
}
