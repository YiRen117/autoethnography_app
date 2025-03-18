import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:http/http.dart' as http; // ✅ 确保 http 包被导入
import 'DataAnalysis.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'OpenAIService.dart';

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
    SharedPreferences.getInstance().then((prefs) {
      prefs.remove(widget.filePath);
    });
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

  Future<void> _analyzeAndStoreThemes() async {
    try {
      safePrint("🔍 Analyzing memo themes...");

      OpenAIService openAIService = OpenAIService();
      List<String> themes = await openAIService.analyzeMemoThemes(
          widget.filePath
      );

      if (themes.isNotEmpty) {
        // ✅ 将主题存入 SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList("memoThemes_${widget.filePath}", themes);

        safePrint("✅ Themes saved: $themes");
      } else {
        safePrint("⚠️ No themes returned from OpenAI API.");
      }
    } catch (e) {
      safePrint("❌ Error analyzing memo themes: $e");
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

  List<TextSpan> _formatMemoContent(String content) {
    final List<TextSpan> spans = [];
    final RegExp pattern = RegExp(r'\*\*(.*?)\*\*'); // ✅ 匹配 **加粗内容**

    int lastMatchEnd = 0;
    final matches = pattern.allMatches(content);

    for (final match in matches) {
      // ✅ 添加普通文本
      if (match.start > lastMatchEnd) {
        spans.add(TextSpan(text: content.substring(lastMatchEnd, match.start)));
      }

      // ✅ 添加加粗问题
      spans.add(
        TextSpan(
          text: match.group(1), // **问题**
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      );

      lastMatchEnd = match.end;
    }

    // ✅ 添加剩余文本
    if (lastMatchEnd < content.length) {
      spans.add(TextSpan(text: content.substring(lastMatchEnd)));
    }

    return spans;
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
                child: RichText(
                  text: TextSpan(
                    style: const TextStyle(fontSize: 16, color: Colors.black),
                    children: _formatMemoContent(memoContent),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            if (backupFilePath != null)
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
