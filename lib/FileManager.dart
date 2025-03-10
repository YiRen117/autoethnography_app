import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:amplify_storage_s3/amplify_storage_s3.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

class FileManager {
  final ImagePicker _imagePicker = ImagePicker();
  final String userSub;

  FileManager(this.userSub);

  /// **列出 S3 中的文件**
  Future<List<StorageItem>> listFiles(bool listFile) async {
    String path = listFile ? "uploads/$userSub/" : "memos/$userSub/";
    try {
      final result = await Amplify.Storage.list(
        path: StoragePath.fromString(path),
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

  Future<String> _generateUniqueFileName(String folderPath, String fileName) async {
    String fileBase = fileName.substring(0, fileName.lastIndexOf('.'));
    String extension = fileName.substring(fileName.lastIndexOf('.'));
    String newFileName = fileName;
    int counter = 1;

    // ✅ 先 `await` 获取 `result`
    final result = await Amplify.Storage.list(
      path: StoragePath.fromString(folderPath),
      options: const StorageListOptions(
        pageSize: 100,
        pluginOptions: S3ListPluginOptions(
          excludeSubPaths: true,
          delimiter: '/',
        ),
      ),
    ).result;

    List<StorageItem> existingFiles = result.items; // ✅ 现在 `items` 可用

    while (existingFiles.any((file) => file.path.split('/').last == newFileName)) {
      newFileName = "$fileBase ($counter)$extension";
      counter++;
    }

    return newFileName;
  }

  /// **📷 选择 & 上传图片**
  Future<void> uploadImage(BuildContext context, Function refreshFiles) async {
    try {
      final pickedFile = await _imagePicker.pickImage(source: ImageSource.gallery);
      if (pickedFile == null) return;

      File file = File(pickedFile.path);
      await _uploadFileToS3(context, file, refreshFiles);
    } catch (e) {
      safePrint("❌ Image upload failed: $e");
    }
  }

  /// **📄 选择 & 上传文档**
  Future<void> uploadDocument(BuildContext context, Function refreshFiles) async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['txt', 'docx'],
      );
      if (result == null) return;

      File file = File(result.files.single.path!);
      await _uploadFileToS3(context, file, refreshFiles);
    } catch (e) {
      safePrint("❌ Document upload failed: $e");
    }
  }

  /// **🔥 统一上传文件到 S3**
  Future<void> _uploadFileToS3(BuildContext context, File file, Function refreshFiles) async {
    try {
      String fileExtension = file.path.split('.').last.toLowerCase();
      List<String> allowedExtensions = ['jpg', 'jpeg', 'png', 'txt', 'docx'];

      // ✅ 检查文件格式
      if (!allowedExtensions.contains(fileExtension)) {
        safePrint("❌ Unsupported file type");
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("❌ Unsupported file type: $fileExtension")),
        );
        return;
      }

      String folderPath = "uploads/$userSub/";
      String originalFileName = file.path.split('/').last;

      // ✅ 生成不重复的文件名
      String uniqueFileName = await _generateUniqueFileName(folderPath, originalFileName);

      String key = "$folderPath$uniqueFileName";

      await Amplify.Storage.uploadFile(
        localFile: AWSFile.fromPath(file.path),
        path: StoragePath.fromString(key),
      ).result;

      safePrint("✅ File uploaded: $key");
      refreshFiles(); // ✅ 上传成功后刷新列表
    } catch (e) {
      safePrint("❌ Upload failed: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("❌ Upload Failure: $e")),
      );
    }
  }

  /// **删除 S3 中的文件**
  Future<void> deleteFile(BuildContext context, String key, Function refreshFiles) async {
    try {
      await Amplify.Storage.remove(
        path: StoragePath.fromString(key),
      ).result;

      // **删除本机 `SharedPreferences` 中的缓存**
      await _deleteLocalPrefs(key);

      safePrint("✅ 文件删除成功: $key");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("✅ File Deleted: ${key.split('/').last}")),
      );

      refreshFiles();
    } catch (e) {
      safePrint("❌ 删除失败: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("❌ Delete Failure: $e")),
      );
    }
  }

  Future<void> _deleteLocalPrefs(String filePath) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys(); // ✅ 获取所有 `prefs` 的 key

      // ✅ 找出所有以 `filePath` 结尾的 key
      final keysToRemove = keys.where((key) => key.endsWith(filePath)).toList();

      // ✅ 逐个删除
      for (String key in keysToRemove) {
        await prefs.remove(key);
      }
      safePrint("✅ All related prefs for $filePath removed.");
    } catch (e) {
      safePrint("❌ Failed to delete local prefs: $e");
    }
  }

  Future<void> saveMemoToS3(String memoName, String userId, String memoContent) async {
    try {
      String folderPath = "memos/$userId/";
      String uniqueMemoName = await _generateUniqueFileName(folderPath, "$memoName.txt");
      String filePath = "$folderPath$uniqueMemoName";

      // ✅ 上传到 S3
      await Amplify.Storage.uploadData(
        path: StoragePath.fromString(filePath),
        data: StorageDataPayload.string(
            memoContent,
            contentType: 'text/plain'), // ✅ 需要 StorageDataPayload 类型
      ).result;

      safePrint("✅ Memo saved: $memoName");
    } catch (e) {
      safePrint("❌ Memo upload failed: $e");
    }
  }

  /// **📝 下载 Memo 文件**
  Future<String?> downloadMemoFromS3(BuildContext context, String filePath) async {
    try {
      // ✅ 获取 S3 文件 URL
      final result = await Amplify.Storage.getUrl(
        path: StoragePath.fromString(filePath),
      ).result;

      final url = result.url.toString();
      safePrint("📥 Download URL: $url");

      // ✅ 直接用 `http.get()` 获取文件内容
      final response = await http.get(Uri.parse(url));

      if (response.statusCode != 200) {
        throw Exception("HTTP ${response.statusCode}: ${response.body}");
      }

      // ✅ 获取本地存储路径
      final Directory dir = await getApplicationDocumentsDirectory();
      final File localFile = File("${dir.path}/${filePath.split('/').last}");

      // ✅ 写入文件
      await localFile.writeAsBytes(response.bodyBytes);

      safePrint("✅ Memo 下载成功: ${localFile.path}");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("✅ Downloaded: ${localFile.path}")),
      );

      return localFile.path;
    } catch (e) {
      safePrint("❌ Memo 下载失败: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("❌ Download Failed: $e")),
      );
      return null;
    }
  }
}
