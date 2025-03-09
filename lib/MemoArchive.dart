import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:http/http.dart' as http; // ✅ 确保 http 包被导入

class MemoDetailPage extends StatefulWidget {
  final String filePath;

  const MemoDetailPage({super.key, required this.filePath});

  @override
  _MemoDetailPageState createState() => _MemoDetailPageState();
}

class _MemoDetailPageState extends State<MemoDetailPage> {
  String memoContent = "Loading...";

  @override
  void initState() {
    super.initState();
    _loadMemo();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Memo Detail")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(child: Text(memoContent)),
      ),
    );
  }
}
