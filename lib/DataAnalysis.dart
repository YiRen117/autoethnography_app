import 'package:flutter/material.dart';
import 'RekognitionService.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'OpenAIService.dart';


class FileDetailPage extends StatefulWidget {
  final String fileName;
  final String filePath;

  const FileDetailPage({super.key, required this.fileName, required this.filePath});

  @override
  _FileDetailPageState createState() => _FileDetailPageState();
}

class _FileDetailPageState extends State<FileDetailPage> {
  List<Map<String, dynamic>> messages = [];
  TextEditingController _editableController = TextEditingController();
  TextEditingController _userInputController = TextEditingController();
  final RekognitionService rekognitionService = RekognitionService();
  final OpenAIService openAIService = OpenAIService();
  String? fileUrl;

  @override
  void initState() {
    super.initState();
    _fetchFileUrl();
    _simulateFileSend();
  }

  Future<void> _fetchFileUrl() async {
    try {
      final result = await Amplify.Storage.getUrl(
        path: StoragePath.fromString(widget.filePath),
      ).result;
      setState(() {
        fileUrl = result.url.toString();
      });
    } catch (e) {
      safePrint("❌ 获取文件 URL 失败: $e");
    }
  }

  void _simulateFileSend() {
    setState(() {
      messages.add({
        "role": "user",
        "content": "📂 ${widget.fileName}",
        "isFile": true
      });
      _botReply("Reading file...");
      _detectText();
    });
  }

  Future<void> _detectText() async {
    String? extractedText = await rekognitionService.detectTextFromS3(widget.filePath);
    safePrint("Extracted text: $extractedText");
    setState(() {
      messages.removeLast(); // 移除"Reading file..."
      messages.add({
        "role": "bot",
        "content": extractedText ?? "No text detected",
        "editable": true
      });
      _editableController.text = extractedText ?? "No text detected";
    });
  }

  void _confirmText(int index) async {
    setState(() {
      messages[index]["content"] = _editableController.text;
      messages[index]["editable"] = false;
    });

    // 发送用户确认的文本给 OpenAI API
    String question = await openAIService.generateReflectiveQuestion(_editableController.text);

    setState(() {
      messages.add({"role": "bot", "content": question, "retry": true});
    });
  }

  void _retryGeneratingQuestion(int index) async {
    String? userText = messages[index]["userText"];
    if (userText == null) return;

    // 重新请求新的问题
    String newQuestion = await openAIService.regenerateReflectiveQuestion(userText);

    setState(() {
      messages[index]["content"] = newQuestion;
    });
  }

  void _botReply(String text) {
    setState(() {
      messages.add({"role": "bot", "content": text});
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Chatbot")),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: messages.length,
              itemBuilder: (context, index) {
                final message = messages[index];
                final isUser = message["role"] == "user";
                final isEditable = message["editable"] ?? false;

                return GestureDetector(
                  onTap: () {
                    if (message["isFile"] == true) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => FilePreviewPage(fileName: widget.fileName, fileUrl: fileUrl!),
                        ),
                      );
                    }
                  },
                  child: Align(
                    alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(
                        color: isUser ? Colors.blue[100] : Colors.grey[300],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: isEditable
                          ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _editableController,
                              maxLines: null,
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.check, color: Colors.green),
                            onPressed: () => _confirmText(index),
                          ),
                        ],
                      )
                          : Row(
                        children: [
                          Expanded(
                            child: Text(
                              message["content"]!,
                              style: const TextStyle(fontSize: 16),
                            ),
                          ),
                          if (message["retry"] == true)
                            IconButton(
                              icon: const Icon(Icons.refresh, color: Colors.blue),
                              onPressed: () => _retryGeneratingQuestion(index),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _userInputController,
              decoration: const InputDecoration(
                hintText: "Type your answer...",
                border: OutlineInputBorder(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class FilePreviewPage extends StatelessWidget {
  final String fileUrl;
  final String fileName;

  const FilePreviewPage({super.key, required this.fileName, required this.fileUrl});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("$fileName")),
      body: Center(
        child: fileUrl.isNotEmpty
            ? Image.network(fileUrl, width: double.infinity, fit: BoxFit.fitWidth)
            : const CircularProgressIndicator(),
      ),
    );
  }
}