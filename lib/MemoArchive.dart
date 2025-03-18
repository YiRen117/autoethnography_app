import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'DataAnalysis.dart';

class MemoDetailPage extends StatefulWidget {
  final String filePath;

  const MemoDetailPage({super.key, required this.filePath});

  @override
  _MemoDetailPageState createState() => _MemoDetailPageState();
}

class _MemoDetailPageState extends State<MemoDetailPage> {
  String memoContent = "Loading...";
  List<List<String>> themes = []; // ✅ 存储 [Theme, Description]
  bool isThemeLoading = true;
  bool isPageLoading = true;
  String? backupFilePath, backupFileName, backupFileUrl;

  @override
  void initState() {
    super.initState();
    _loadMemo().then((_) => _loadMemoThemes());
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
          isPageLoading = false;
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

  Future<void> _loadMemoThemes() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String>? storedThemes = prefs.getStringList("memoThemes_${widget.filePath}");

    if (storedThemes != null && storedThemes.isNotEmpty) {
      List<List<String>> parsedThemes = storedThemes.map((themeText) {
        List<String> parts = themeText.split(" - ");
        String theme = parts.isNotEmpty ? parts[0].replaceAll("**", "").trim() : "Unknown";
        String description = parts.length > 1 ? parts[1].trim() : "";

        return [theme, description];
      }).toList();

      setState(() {
        themes = parsedThemes;
        isThemeLoading = false;
      });
    } else {
      setState(() {
        isThemeLoading = true;
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

  List<TextSpan> _formatMemoContent(String content) {
    final List<TextSpan> spans = [];
    final RegExp pattern = RegExp(r'\*\*(.*?)\*\*');

    int lastMatchEnd = 0;
    final matches = pattern.allMatches(content);

    for (final match in matches) {
      if (match.start > lastMatchEnd) {
        spans.add(TextSpan(text: content.substring(lastMatchEnd, match.start)));
      }

      spans.add(
        TextSpan(
          text: match.group(1),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      );

      lastMatchEnd = match.end;
    }

    if (lastMatchEnd < content.length) {
      spans.add(TextSpan(text: content.substring(lastMatchEnd)));
    }

    return spans;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Memo Detail")),
      body: isPageLoading
          ? const Center(child: CircularProgressIndicator()) // ✅ **加载中时，整页 Loading**
          : Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ✅ Memo 内容部分
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ✅ Memo 内容
                  const Text(
                    "  Q&A Memo：",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: RichText(
                      text: TextSpan(
                        style: const TextStyle(fontSize: 16, color: Colors.black),
                        children: _formatMemoContent(memoContent),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ✅ 分割线
                  const Divider(thickness: 1),

                  // ✅ Summary 标题
                  const SizedBox(height: 10),
                  const Text(
                    "  Summary:",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),

                  // ✅ 显示 Themes 或 "Analyzing themes..."
                  themes.isEmpty
                      ? const Text(
                    "Themes analyzing...",
                    style: TextStyle(
                      fontSize: 16,
                      fontStyle: FontStyle.italic,
                      color: Colors.grey,
                    ),
                  )
                      : Column(
                    children: themes.map((themeData) {
                      return Card(
                        elevation: 2,
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: RichText(
                            text: TextSpan(
                              style: const TextStyle(fontSize: 16, color: Colors.black),
                              children: [
                                TextSpan(
                                  text: "${themeData[0]}: ",
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                TextSpan(text: themeData[1]),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),

          // ✅ View Original File 按钮 (保持底部固定)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            child: ElevatedButton(
              onPressed: () {
                // TODO: 处理 View Original File
              },
              child: const Text("View Original File"),
            ),
          ),
        ],
      ),
    );
  }
}
