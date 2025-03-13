import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:http/http.dart' as http; // ✅ 确保 http 包被导入
import 'DataAnalysis.dart';

class MemoDetailPage extends StatefulWidget {
  final String filePath;

  const MemoDetailPage({super.key, required this.filePath});

  @override
  _MemoDetailPageState createState() => _MemoDetailPageState();
}

class _MemoDetailPageState extends State<MemoDetailPage> {
  String memoContent = "Loading...";
  String? backupFilePath; // ✅ 用于存储原文件备份路径
  String? backupFileUrl; // ✅ 用于存储原文件备份路径
  String? backupFileName; // ✅ 用于存储原文件备份路径

  @override
  void initState() {
    super.initState();
    _loadMemo();
    _fetchBackupFileInfo();
  }

  Future<void> _loadMemo() async {
    try {
      final result = await Amplify.Storage.getUrl(
        path: StoragePath.fromString(widget.filePath),
      ).result;

      if (result.url.toString().isEmpty) {
        throw Exception("S3 URL is empty.");
      }

      final response = await http.get(Uri.parse(result.url.toString()));

      if (response.statusCode == 200) {
        setState(() {
          memoContent = utf8.decode(response.bodyBytes);
        });
      } else {
        throw Exception("Failed to fetch memo: ${response.statusCode}");
      }
    } catch (e) {
      safePrint("❌ Failed to load memo: $e");
      setState(() {
        memoContent = "Error loading memo.";
      });
    }
  }

  Future<void> _fetchBackupFileInfo() async {
    try {
      final metadataResult = await Amplify.Storage.getProperties(
        path: StoragePath.fromString(widget.filePath),
      ).result;

      Map<String, String>? metadata = metadataResult.storageItem.metadata;
      if (metadata.containsKey("backup_file")) {
        String? backupPath = metadata["backup_file"];

        if (backupPath != null) {
          String fileName = backupPath.split('/').last;
          String? fileUrl;

          try {
            final result = await Amplify.Storage.getUrl(
              path: StoragePath.fromString(backupPath),
            ).result;
            fileUrl = result.url.toString();
          } catch (e) {
            safePrint("❌ File Url not found in the given path: $e");
          }

          // ✅ 在这里更新状态，确保所有数据已获取后再调用 setState()
          setState(() {
            backupFilePath = backupPath;
            backupFileName = fileName;
            backupFileUrl = fileUrl;
          });
        }
      } else {
        safePrint("⚠️ No backup file found");
      }
    } catch (e) {
      safePrint("❌ Backup file fetch failure: $e");
    }
  }

  /// **📌 跳转到原文件详情页**
  void _viewOriginalFile() {
    if (backupFilePath != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => FilePreviewPage(filePath: backupFilePath!, fileName: backupFileName!, fileUrl: backupFileUrl!),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No backup file found.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Memo Detail")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Text(memoContent),
              ),
            ),
            const SizedBox(height: 20),
            if (backupFilePath != null) // ✅ 仅当有备份文件时显示按钮
              ElevatedButton(
                onPressed: _viewOriginalFile,
                child: const Text("View Original File"),
              ),
          ],
        ),
      ),
    );
  }
}
