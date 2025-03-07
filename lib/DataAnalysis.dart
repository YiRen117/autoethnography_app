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
  bool startChat = false;
  bool isRetrying = false;
  bool isErrorState = false;
  bool showDetectedTextBox = false;
  int followUpCount = 0; // ✅ 计数 Follow-Up 次数

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
      messages.removeLast();
      showDetectedTextBox = true;
      _editableController.text = extractedText ?? "No text detected";
    });
  }

  void _confirmText() async {
    setState(() {
      _userReply(_editableController.text);
      showDetectedTextBox = false; // ✅ 文字确认后隐藏文本框
    });

    _botReply("Generating question...");
    String question = await openAIService.initialGeneration(_editableController.text);

    setState(() {
      messages.removeLast();
      if (question.contains("Error") || question.contains("Failed")) {
        // ❌ 生成问题失败
        messages.add({
          "role": "bot",
          "content": question,
          "retry": true
        });
        isErrorState = true; // ✅ 进入错误状态
      } else {
        messages.add({
          "role": "bot",
          "content": question,
          "retry": true,
          "userText": _editableController.text
        });
        isErrorState = false;
      }
      startChat = true;
    });
  }

  void _retryGeneration(int index) async {
    setState(() {
      isRetrying = true;
    });

    String? userText = messages[index]["userText"];
    if (userText == null) return;

    String newQuestion = await openAIService.regenerate(userText);

    setState(() {
      messages[index]["content"] = newQuestion;
      isRetrying = false;
    });
  }

  void _followUpGeneration() async {
    if (followUpCount > 2) return; // ✅ 限制 Follow-Up 最多 2 次（最后一次用户回答后输入框消失）

    String userAnswer = _userInputController.text.trim();
    if (userAnswer.isEmpty) return;

    _userReply(userAnswer);
    _botReply("Generating follow-up question...");

    String followUpQuestion = await openAIService.followUpGeneration(userAnswer);

    setState(() {
      messages.removeLast();
      followUpCount++;

      if (followUpQuestion.contains("Error") || followUpQuestion.contains("Failed")) {
        messages.add({"role": "bot", "content": followUpQuestion, "retry": true});
      } else {
        messages.add({
          "role": "bot",
          "content": followUpQuestion,
          "retry": true
        });
      }
    });
  }

  void _restartChat() {
    setState(() {
      messages.clear();
      startChat = false;
      isErrorState = false;
      showDetectedTextBox = false;
      followUpCount = 0;
      _simulateFileSend();
    });
  }


  void _botReply(String text) {
    setState(() {
      messages.add({"role": "bot", "content": text});
    });
  }

  void _userReply(String text) {
    setState(() {
      messages.add({"role": "user", "content": text});
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
              itemCount: messages.length + (showDetectedTextBox ? 1 : 0), // ✅ 计算消息总数
              itemBuilder: (context, index) {
                if (showDetectedTextBox && index == messages.length) {
                  // ✅ 插入可编辑文本框（出现在用户文件消息的下方）
                  return Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          width: MediaQuery.of(context).size.width * 0.9, // ✅ 占满宽度
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey),
                          ),
                          child: TextField(
                            controller: _editableController,
                            maxLines: null,
                            textAlign: TextAlign.center, // ✅ 居中文本
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        ElevatedButton(
                          onPressed: _confirmText,
                          child: const Text("Confirm"),
                        ),
                      ],
                    ),
                  );
                }

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
                    child:IntrinsicWidth(
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.75, // ✅ 限制最大宽度为屏幕 75%
                        ),
                        decoration: BoxDecoration(
                          color: isUser ? Colors.blue[100] : Colors.grey[300],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: isEditable
                            ? Row(// ✅ 让 Row 仅占用必要空间
                          children: [
                            Flexible(
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
                              onPressed: () => _confirmText(),
                            ),
                          ],
                        )
                            : Row(
                          children: [
                            Flexible( // ✅ 避免 Text 溢出，同时保证消息框可以缩小
                              child: Text(
                                message["content"]!,
                                style: const TextStyle(fontSize: 16),
                                softWrap: true,
                              ),
                            ),
                            if (message["retry"] == true)
                              IconButton(
                                icon: const Icon(Icons.refresh, color: Colors.blue),
                                onPressed: () => _retryGeneration(index),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          if (startChat && !isErrorState)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: MediaQuery.of(context).size.width * 0.75,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.grey),
                      color: Colors.white,
                    ),
                    child: TextField(
                      controller: _userInputController,
                      decoration: const InputDecoration(
                        hintText: "Type your answer...",
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: Icon(Icons.send, color: isRetrying ? Colors.grey : Colors.blue),
                    onPressed: isRetrying ? null : () {}, // ✅ 这里调用 follow-up 逻辑
                  ),
                ],
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