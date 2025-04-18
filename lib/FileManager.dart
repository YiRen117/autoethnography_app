import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:amplify_storage_s3/amplify_storage_s3.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'DataAnalysis.dart';
import 'main.dart';

class FileManager {
  final ImagePicker _imagePicker = ImagePicker();
  final String userSub;
  final String memoFolder = "memos/";
  final String uploadFolder = "uploads/";
  final String backupFolder = "copies/";

  FileManager(this.userSub);

  Future<List<StorageItem>> listFiles(bool listFile) async {
    String path = listFile ? "$uploadFolder$userSub/" : "$memoFolder$userSub/";
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
      safePrint("❌ Failed to list items: $e");
      return [];
    }
  }

  Future<String> generateUniqueFileName(String folderPath, String fileName) async {
    String fileBase = fileName.substring(0, fileName.lastIndexOf('.'));
    String extension = fileName.substring(fileName.lastIndexOf('.'));
    String newFileName = fileName;
    int counter = 1;

    List<StorageItem> existingFiles = await listFiles(true);

    while (existingFiles.any((file) => file.path.split('/').last == newFileName)) {
      newFileName = "$fileBase($counter)$extension";
      counter++;
    }

    return newFileName;
  }

  Future<void> uploadImage(Function refreshFiles) async {
    try {
      final pickedFile = await _imagePicker.pickImage(source: ImageSource.gallery);
      if (pickedFile == null) return;

      File file = File(pickedFile.path);

      _showUploadingDialog();

      String? uploadedFilePath = await _uploadFileToS3(navigatorKey.currentContext!, file);

      if (navigatorKey.currentContext!.mounted) {
        Navigator.pop(navigatorKey.currentContext!);
      }

      if (uploadedFilePath != null) {
        String fileName = uploadedFilePath.split('/').last;

        refreshFiles();

        Future.delayed(Duration.zero, () {
          if (navigatorKey.currentContext!.mounted) {
            Navigator.push(
              navigatorKey.currentContext!,
              MaterialPageRoute(
                builder: (context) => FileDetailPage(
                  fileName: fileName,
                  filePath: uploadedFilePath,
                ),
              ),
            ).then((_) => refreshFiles());
          }
        });
      }
    } catch (e) {
      safePrint("❌ Image upload failed: $e");

      if (navigatorKey.currentContext!.mounted) {
        Navigator.pop(navigatorKey.currentContext!);
      }
    }
  }

  Future<void> uploadDocument(Function refreshFiles) async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['txt', 'docx'],
      );
      if (result == null) return;

      File file = File(result.files.single.path!);

      _showUploadingDialog();

      String? uploadedFilePath = await _uploadFileToS3(navigatorKey.currentContext!, file);

      if (navigatorKey.currentContext!.mounted) {
        Navigator.pop(navigatorKey.currentContext!);
      }

      if (uploadedFilePath != null) {
        String fileName = uploadedFilePath.split('/').last;

        refreshFiles();

        Future.delayed(Duration.zero, () {
          if (navigatorKey.currentContext!.mounted) {
            Navigator.push(
              navigatorKey.currentContext!,
              MaterialPageRoute(
                builder: (context) => FileDetailPage(
                  fileName: fileName,
                  filePath: uploadedFilePath,
                ),
              ),
            ).then((_) => refreshFiles());
          }
        });
      }
    } catch (e) {
      safePrint("❌ Document upload failed: $e");

      if (navigatorKey.currentContext!.mounted) {
        Navigator.pop(navigatorKey.currentContext!);
      }
    }
  }


  void _showUploadingDialog() {
    showDialog(
      context: navigatorKey.currentContext!,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          content: Row(
            children: const [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Text("Uploading..."),
            ],
          ),
        );
      },
    );
  }

  Future<String?> _uploadFileToS3(BuildContext context, File file) async {
    try {
      String fileExtension = file.path.split('.').last.toLowerCase();
      List<String> allowedExtensions = ['jpg', 'jpeg', 'png', 'txt', 'docx'];

      if (!allowedExtensions.contains(fileExtension)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("❌ Unsupported file type: $fileExtension")),
        );
        return null;
      }

      String folderPath = "$uploadFolder$userSub/";
      String originalFileName = file.path.split('/').last;

      String uniqueFileName = await generateUniqueFileName(folderPath, originalFileName);
      String key = "$folderPath$uniqueFileName";

      await Amplify.Storage.uploadFile(
        localFile: AWSFile.fromPath(file.path),
        path: StoragePath.fromString(key),
      ).result;

      safePrint("✅ File uploaded: $key");
      return key;
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("❌ Upload Failure: $e")),
      );
      return null;
    }
  }


  /// **删除 S3 中的文件**
  Future<void> deleteFile(BuildContext context, String key, Function refreshFiles) async {
    try {
      await Amplify.Storage.remove(
        path: StoragePath.fromString(key),
      ).result;

      await _deleteLocalPrefs(key);

      safePrint("✅ Deleted: $key");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("✅ File Deleted: ${key.split('/').last}")),
      );

      refreshFiles();
    } catch (e) {
      safePrint("❌ Delete failure: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("❌ Delete Failure: $e")),
      );
    }
  }

  Future<void> writeEntryToS3(String fileName, String content) async {
    try {
      String folderPath = "$uploadFolder$userSub/";
      String key = "$folderPath$fileName";

      await Amplify.Storage.uploadData(
        path: StoragePath.fromString(key),
        data: StorageDataPayload.string(
            content,
            contentType: 'text/plain'),
      ).result;

      safePrint("✅ Entry saved to S3: $key");
    } catch (e) {
      safePrint("❌ Failed to save entry to S3: $e");
    }
  }

  Future<void> _deleteLocalPrefs(String filePath) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();

      final keysToRemove = keys.where((key) => key.endsWith(filePath)).toList();

      for (String key in keysToRemove) {
        await prefs.remove(key);
      }
      safePrint("✅ All related prefs for $filePath removed.");
    } catch (e) {
      safePrint("❌ Failed to delete local prefs: $e");
    }
  }

  Future<void> saveMemoToS3(String memoName, String userId, String memoContent, String originalFilePath) async {
    try {
      String folderPath = "$memoFolder$userId/";
      String uniqueMemoName = await generateUniqueFileName(folderPath, "$memoName.txt");
      String filePath = "$folderPath$uniqueMemoName";

      String? backupFilePath = await _backupOriginalFile(userId, originalFilePath);

      Map<String, String> metadata = {};
      if (backupFilePath != null) {
        metadata["backup_file"] = backupFilePath;
      }

      await Amplify.Storage.uploadData(
        path: StoragePath.fromString(filePath),
        data: StorageDataPayload.string(
            memoContent,
            contentType: 'text/plain'),
        options: StorageUploadDataOptions(metadata: metadata),
      ).result;

      safePrint("✅ Memo saved: $memoName");

    } catch (e) {
      safePrint("❌ Memo upload failure: $e");
    }
  }

  Future<String?> _backupOriginalFile(String userId, String originalFilePath) async {
    try {
      String fileName = originalFilePath.split('/').last;
      String extension = fileName.split('.').last.toLowerCase();
      String baseName = fileName.substring(0, fileName.lastIndexOf('.'));
      String backupFolderPath = "$backupFolder$userId/";

      DateTime? uploadTime = await _getFileUploadTime(originalFilePath);
      if (uploadTime == null) {
        safePrint("❌ Failed to fetch upload timestamp, skipping backup for $fileName");
        return null;
      }

      String formattedTime = DateFormat('yyyyMMdd_HHmmss').format(uploadTime);
      String backupFilePath = "$backupFolderPath${baseName}_$formattedTime.$extension";

      final listResult = await Amplify.Storage.list(
        path: StoragePath.fromString(backupFolderPath),
        options: const StorageListOptions(pageSize: 100),
      ).result;

      bool fileAlreadyBackedUp = listResult.items.any((file) => file.path == backupFilePath);

      if (fileAlreadyBackedUp) {
        safePrint("✅ Backup file exists: $backupFilePath");
        return backupFilePath;
      }

      final originalFileUrlResult = await Amplify.Storage.getUrl(
        path: StoragePath.fromString(originalFilePath),
      ).result;

      if (originalFileUrlResult.url.toString().isEmpty) {
        throw Exception("S3 URL is empty.");
      }

      final response = await http.get(Uri.parse(originalFileUrlResult.url.toString()));

      if (response.statusCode != 200) {
        throw Exception("HTTP ${response.statusCode}: ${response.body}");
      }

      List<int> fileBytes = response.bodyBytes;

      await Amplify.Storage.uploadData(
        path: StoragePath.fromString(backupFilePath),
        data: StorageDataPayload.bytes(fileBytes),
      ).result;

      safePrint("✅ Backup success: $backupFilePath");
      return backupFilePath;
    } catch (e) {
      safePrint("❌ Backup failure: $e");
      return null;
    }
  }

  Future<DateTime?> _getFileUploadTime(String filePath) async {
    try {
      final listResult = await Amplify.Storage.list(
        path: StoragePath.fromString(filePath),
        options: const StorageListOptions(pageSize: 1),
      ).result;

      if (listResult.items.isNotEmpty) {
        return listResult.items.first.lastModified;
      } else {
        return null;
      }
    } catch (e) {
      safePrint("❌ Failed to get file upload time: $e");
      return null;
    }
  }

  Future<String?> downloadMemoFromS3(BuildContext context, String filePath) async {
    try {
      final result = await Amplify.Storage.getUrl(
        path: StoragePath.fromString(filePath),
      ).result;

      final url = result.url.toString();

      final response = await http.get(Uri.parse(url));

      if (response.statusCode != 200) {
        throw Exception("HTTP ${response.statusCode}: ${response.body}");
      }

      final Directory dir = await getApplicationDocumentsDirectory();
      final File localFile = File("${dir.path}/${filePath.split('/').last}");

      await localFile.writeAsBytes(response.bodyBytes);

      safePrint("✅ Memo downloaded: ${localFile.path}");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("✅ Downloaded: ${localFile.path}")),
      );

      return localFile.path;
    } catch (e) {
      safePrint("❌ Memo download failure: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("❌ Download Failed: $e")),
      );
      return null;
    }
  }
}
