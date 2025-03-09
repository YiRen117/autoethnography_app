import 'package:flutter/material.dart';
import 'TextDetection.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'OpenAIService.dart';
import 'FileManager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

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
  final TextDetection textDetection = TextDetection();
  final OpenAIService openAIService = OpenAIService();
  late FileManager fileManager;
  String? fileUrl, userSub;
  bool startChat = false;
  bool isRetrying = false;
  bool isErrorState = false;
  bool showDetectedTextBox = false;
  bool hasChatHistory = false;
  bool isMemoed = false;
  bool endOfChat = false;
  int followUpCount = 0; // ✅ Follow-Up 次数
  bool isUserInputEmpty = true; // ✅ 监听 TextField，控制发送按钮状态
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadChatHistory();
    _fetchFileUrl();
    _getUserInfo();
    _userInputController.addListener(_updateSendButtonState); // ✅ 监听输入框变化
  }

  @override
  void dispose() {
    _userInputController.dispose();
    _editableController.dispose();
    _scrollController.dispose(); // ✅ 释放 ScrollController
    super.dispose();
  }

  /// **滚动到底部**
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _getUserInfo() async {
    final user = await Amplify.Auth.getCurrentUser();
    setState(() {
      userSub = user.userId;
      fileManager = FileManager(userSub!);
    });
  }

  /// **保存聊天记录到本地**
  Future<void> _saveChatHistory() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    hasChatHistory = true;
    final String chatData = jsonEncode(messages); // ✅ 转换为 JSON 格式
    await prefs.setString('chat_history', chatData);
    await prefs.setBool('startChat', startChat);
    await prefs.setBool('isRetrying', isRetrying);
    await prefs.setBool('isErrorState', isErrorState);
    await prefs.setBool('isMemoed', isMemoed);
    await prefs.setBool('endOfChat', endOfChat);
    await prefs.setInt('followUpCount', followUpCount);
  }

  Future<void> _loadChatHistory() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? chatData = prefs.getString('chat_history');

    if (chatData != null) {
      hasChatHistory = true;
      setState(() {
        messages = List<Map<String, dynamic>>.from(jsonDecode(chatData));
        startChat = prefs.getBool('startChat') ?? false;
        isRetrying = prefs.getBool('isRetrying') ?? false;
        isErrorState = prefs.getBool('isErrorState') ?? false;
        isMemoed = prefs.getBool('isMemoed') ?? false;
        endOfChat = prefs.getBool('endOfChat') ?? false;
        followUpCount = prefs.getInt('followUpCount') ?? 0;
      });
      Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
    } else {
      hasChatHistory = false;
    }

    if (!hasChatHistory) {
      _simulateFileSend();
    }
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
    if (hasChatHistory) {
      return;
    }
    setState(() {
      messages.add({"role": "user", "content": "📂 ${widget.fileName}", "isFile": true});
      _botReply("Reading file...");
      _detectText();
    });
  }

  Future<void> _detectText() async {
    String? extractedText = await textDetection.detectTextFromS3(widget.filePath);
    setState(() {
      messages.removeLast();
      showDetectedTextBox = true;
      _editableController.text = extractedText ?? "No text detected";
    });
  }

  void _confirmText() async {
    FocusScope.of(context).unfocus(); // ✅ 收起键盘
    setState(() {
      _userReply(_editableController.text);
      showDetectedTextBox = false;
    });

    _botReply("Generating question...");
    String response = await openAIService.initialGeneration(_editableController.text);
    _handleAIResponse(response, _editableController.text);
    startChat = true;
  }

  /// **处理生成失败时的 Retry**
  void retryError() async {
    if (!isErrorState || messages.isEmpty) return;

    String requestType = messages.last["requestType"] ?? "initial";
    String userText = messages.last["userText"] ?? "";

    String response;
    switch (requestType) {
      case "follow_up":
        response = await openAIService.followUpGeneration(userText);
        break;
      case "regenerate":
        response = await openAIService.regenerate(userText);
        break;
      case "generate_initial":
      default:
        response = await openAIService.initialGeneration(userText);
        break;
    }

    _handleAIResponse(response, userText);
  }

  void _regeneration(int index) async {
    FocusScope.of(context).unfocus(); // ✅ 收起键盘
    setState(() {
      isRetrying = true;
    });

    String? userText = messages[index]["userText"];
    if (userText == null) return;

    String response = await openAIService.regenerate(userText);
    _handleAIResponse(response, _editableController.text);
    setState(() {
      isRetrying = false;
    });
  }

  void _followUpGeneration() async {
    FocusScope.of(context).unfocus(); // ✅ 收起键盘
    String userAnswer = _userInputController.text.trim();
    _userReply(userAnswer);
    _userInputController.clear();
    _updateSendButtonState();
    followUpCount++; // ✅ 只有当用户实际发送回答时，才增加计数

    if (followUpCount > 2){
      endOfChat = true;
      return;
    }
    _botReply("Generating question...");

    String response = await openAIService.followUpGeneration(userAnswer);
    _handleAIResponse(response, userAnswer);
  }

  /// **处理 AI API 响应的通用逻辑**
  void _handleAIResponse(String response, String userText) {
    setState(() {
      messages.removeLast();
      if (response.contains("Error") || response.contains("Failed")) {
        messages.add({"role": "bot", "content": response, "retry": true});
        isErrorState = true;
      } else {
        messages.add({
          "role": "bot",
          "content": response,
          "retry": true,
          "userText": userText
        });
        _saveChatHistory();
        isErrorState = false;
      }
    });
  }

  void _restartChat() {
    setState(() {
      messages.clear();
      hasChatHistory = false;
      startChat = false;
      isErrorState = false;
      isRetrying = false;
      showDetectedTextBox = false;
      followUpCount = 0;
      isMemoed = false;
      endOfChat = false;
      _userInputController.clear();
      isUserInputEmpty = true;
      _simulateFileSend();
    });

    SharedPreferences.getInstance().then((prefs) {
      prefs.remove('chat_history'); // ✅ 清空本地存储
      prefs.remove('startChat');
      prefs.remove('isRetrying');
      prefs.remove('isErrorState');
      prefs.remove('isMemoed');
      prefs.remove('endOfChat');
      prefs.remove('followUpCount');
    });
  }

  void _showMemoDialog() {
    showDialog(
      context: context,
      builder: (context) {
        TextEditingController memoNameController = TextEditingController(); // ✅ 用户输入 Memo 名称

        return AlertDialog(
          title: const Text("Save Memo"),
          content: TextField(
            controller: memoNameController,
            decoration: const InputDecoration(
              hintText: "Enter memo file name",
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () {
                String memoName = memoNameController.text.trim();
                if (memoName.isNotEmpty) {
                  _saveMemoToS3(memoName); // ✅ 存储 Memo
                  Navigator.pop(context);
                }
              },
              child: const Text("Save"),
            ),
          ],
        );
      },
    );
  }

  void _saveMemoToS3(String memoName) {
    String memoContent = messages.map((m) => "${m['role']}: ${m['content']}").join("\n");
    fileManager.saveMemoToS3(memoName, userSub!, memoContent);
    isMemoed = true;
    _saveChatHistory();
  }

  void _updateSendButtonState() {
    setState(() {
      isUserInputEmpty = _userInputController.text.trim().isEmpty;
    });
  }

  void _botReply(String text) {
    setState(() {
      messages.add({"role": "bot", "content": text});
    });
    Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
    _saveChatHistory();
  }

  void _userReply(String text) {
    setState(() {
      messages.add({"role": "user", "content": text});
    });
    Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
    _saveChatHistory();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Chatbot"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh), // ✅ Restart 按钮图标
            tooltip: "Restart Chat",
            onPressed: _restartChat, // ✅ 点击后重置聊天
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: messages.length + (showDetectedTextBox ? 1 : 0),
              itemBuilder: (context, index) {
                if (showDetectedTextBox && index == messages.length) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          width: MediaQuery.of(context).size.width * 0.9,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey),
                          ),
                          child: TextField(
                            controller: _editableController,
                            maxLines: null,
                            textAlign: TextAlign.center,
                            decoration: const InputDecoration(border: InputBorder.none),
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
                                onPressed: () {
                                  if (isErrorState) {
                                    retryError();
                                  } else {
                                    _regeneration(index);
                                  }
                                },
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

          if (startChat && !isErrorState && followUpCount <= 2)
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
                    icon: Icon(Icons.send, color: isUserInputEmpty ? Colors.grey : Colors.blue),
                    onPressed: isUserInputEmpty ? null : _followUpGeneration,
                  ),
                ],
              ),
            ),

          if (followUpCount > 2 || endOfChat)
            Padding(
              padding: const EdgeInsets.only(bottom: 40.0), // ✅ 增加与底部的间距
              child: ElevatedButton(
                onPressed: isMemoed ? null : _showMemoDialog,
                child: const Text("Memo"),
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