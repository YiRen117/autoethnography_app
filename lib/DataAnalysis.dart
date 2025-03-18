import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'TextDetection.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'OpenAIService.dart';
import 'FileManager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

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
  String? fileUrl, userSub, rawData;
  bool startChat = false;
  bool isRetrying = false;
  bool isErrorState = false;
  bool isTextRead = false;
  bool showDetectedTextBox = false;
  bool hasChatHistory = false;
  //bool isMemoed = false;
  bool endOfChat = false;
  int followUpCount = 0; // ✅ Follow-Up 次数
  bool isUserInputEmpty = true; // ✅ 监听 TextField，控制发送按钮状态
  final ScrollController _scrollController = ScrollController();
  bool isEntryMode = false;
  bool hasWrittenToFile = false;

  @override
  void initState() {
    super.initState();
    _getUserInfo();
    _fetchFileUrl();
    _userInputController.addListener(_updateSendButtonState);
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
    _loadChatHistory();
  }


  /// **📄 读取文本文件**
  Future<void> _readTextFile() async {
    try {
      final result = await Amplify.Storage.getUrl(
        path: StoragePath.fromString(widget.filePath),
      ).result;

      final response = await http.get(Uri.parse(result.url.toString()));
      String textContent = utf8.decode(response.bodyBytes);
      setState(() {
        rawData = textContent;
        isTextRead = true;
      });
    } catch (e) {
      safePrint("❌ Failed to load text file: $e");
      _botReply("❌ Failed to read text file.", "error");
    }
  }

  /// **保存聊天记录到本地**
  Future<void> _saveChatHistory() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    hasChatHistory = true;
    final String chatData = jsonEncode(messages); // ✅ 转换为 JSON 格式
    await prefs.setString('chat_history_${widget.filePath}', chatData);
    await prefs.setBool('startChat_${widget.filePath}', startChat);
    await prefs.setBool('isRetrying_${widget.filePath}', isRetrying);
    await prefs.setBool('isErrorState_${widget.filePath}', isErrorState);
    //await prefs.setBool('isMemoed_${widget.filePath}', isMemoed);
    await prefs.setBool('isTextRead_${widget.filePath}', isTextRead);
    await prefs.setBool('endOfChat_${widget.filePath}', endOfChat);
    await prefs.setInt('followUpCount_${widget.filePath}', followUpCount);
    await prefs.setString('rawData_${widget.filePath}', rawData!);

    Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
  }

  Future<void> _loadChatHistory() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? chatData = prefs.getString('chat_history_${widget.filePath}');
    final bool hasFirstQuestion = prefs.getBool('startChat_${widget.filePath}') ?? false;

    if (chatData != null && hasFirstQuestion) {
      hasChatHistory = true;
      setState(() {
        messages = List<Map<String, dynamic>>.from(jsonDecode(chatData));
        startChat = prefs.getBool('startChat_${widget.filePath}') ?? false;
        isRetrying = prefs.getBool('isRetrying_${widget.filePath}') ?? false;
        isErrorState = prefs.getBool('isErrorState_${widget.filePath}') ?? false;
        //isMemoed = prefs.getBool('isMemoed_${widget.filePath}') ?? false;
        isTextRead = prefs.getBool('isTextRead_${widget.filePath}') ?? false;
        endOfChat = prefs.getBool('endOfChat_${widget.filePath}') ?? false;
        followUpCount = prefs.getInt('followUpCount_${widget.filePath}') ?? 0;
        rawData = prefs.getString('rawData_${widget.filePath}');

        final lastMessage = messages.last;
        if (lastMessage["role"] == "bot" && lastMessage["type"] == "generate") {
          _restoreLastMessage(lastMessage);
        }
      });
      Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
    } else {
      hasChatHistory = false;
    }

    if (!hasChatHistory) {
      _simulateFileSend();
    }
  }

  Future<void> _restoreLastMessage(Map<String, dynamic> lastMessage) async {
    lastMessage["showRefresh"] = true; // ✅ 添加刷新按钮标记
    if (lastMessage["userText"] == null || lastMessage["userText"] == "") {
      String? latestUserMessage;
      for (int i = messages.length - 1; i >= 0; i--) {
        if (messages[i]["role"] == "user") {
          if (messages[i]["type"] == "answer") {
            latestUserMessage = messages[i]["content"];
          } else {
            latestUserMessage = rawData;
          }
          break;
        }
      }
      lastMessage["userText"] = latestUserMessage ?? rawData;
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

  void _simulateFileSend () async {
    if (hasChatHistory) {
      return;
    }

    String fileExtension = widget.fileName.split('.').last.toLowerCase();

    if (["jpg", "jpeg", "png"].contains(fileExtension)) {
      setState(() {
        messages.add({
          "role": "user",
          "content": "📂 ${widget.fileName}",
          "isFile": true,
          "type": "setup"
        });
        _botReply("Reading file...", "setup");
        _detectText();
      });
    } else if (["txt", "docx"].contains(fileExtension)) {
      // ✅ 文档文件：检查是否是 Typed Entry
      bool isEmpty = await _isFileEmpty(widget.filePath);
      if (widget.fileName.startsWith("TypedEntry_") && isEmpty) {
        // ✅ 这是一个新的 Entry，等待用户输入
        isEntryMode = true;
        setState(() {
          messages.add({
            "role": "bot",
            "content": "Please type your message below to begin.",
            "type": "setup"
          });
        });
      } else {
        // ✅ 这是普通文档，读取文本
        setState(() {
          messages.add({
            "role": "user",
            "content": "📂 ${widget.fileName}",
            "isFile": true,
            "type": "setup"
          });
          _readTextFile();
        });
      }
    } else {
      _botReply("❌ Unsupported file type", "error");
    }
  }

  Future<bool> _isFileEmpty(String filePath) async {
    try {
      final files = await fileManager.listFiles(true);

      // ✅ 遍历文件列表，检查 `filePath` 是否存在
      for (var file in files) {
        if (file.path == filePath) {
          return false; // ✅ 文件存在，不是空的
        }
      }
      return true; // ✅ 文件不存在，视为空
    } catch (e) {
      safePrint("❌ Failed to check file existence: $e");
      return true; // ✅ 发生异常时，假设文件为空
    }
  }

  void _handleEntryInput() async {
    FocusScope.of(context).unfocus(); // ✅ 关闭键盘
    String userText = _userInputController.text.trim();

    if (userText.isEmpty) return; // ✅ 避免上传空文本
    await fileManager.writeEntryToS3(widget.fileName, userText);

    setState(() {
      messages.add({"role": "user", "content": userText, "type": "setup"});
      _userInputController.clear();
      _updateSendButtonState();
      rawData = userText;
      hasWrittenToFile = true;
    });
  }

  Future<void> _detectText() async {
    String? extractedText = await textDetection.detectTextFromS3(widget.filePath);
    setState(() {
      messages.removeLast();
      showDetectedTextBox = true;
      _editableController.text = extractedText ?? "No text detected";
      rawData = extractedText;
    });
  }

  void _confirmText() async {
    FocusScope.of(context).unfocus(); // ✅ 收起键盘
    if(isTextRead){
      setState(() {
        isTextRead = false;
      });
    }
    else if(showDetectedTextBox) {
      setState(() {
        _userReply(_editableController.text, "setup");
        showDetectedTextBox = false;
      });
    }
    else if(isEntryMode) {
      setState(() {
        hasWrittenToFile = false;
        isEntryMode = false;
      });
    }

    _botReply("Generating question...", "generate");
    String response = await openAIService.initialGeneration(rawData!);
    _handleAIResponse(response, rawData!);
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

    String userText = messages[index]["userText"] ?? "";
    safePrint("Retrying with user text: $userText");

    messages.removeLast();
    _botReply("Generating question...", "generate");
    if (userText == "") {
      safePrint("❌ Regeneration failure: No user text found.");
      return;
    }

    String response = await openAIService.regenerate(userText);
    _handleAIResponse(response, _editableController.text);
    setState(() {
      isRetrying = false;
    });
  }

  void _followUpGeneration() async {
    FocusScope.of(context).unfocus(); // ✅ 收起键盘
    String userAnswer = _userInputController.text.trim();

    for (int i = 0; i < messages.length; i++) {
      if (messages[i]["role"] == "bot" && messages[i]["retry"] == true) {
        messages[i]["retry"] = false;
      }
    }

    _userReply(userAnswer, "answer");
    _userInputController.clear();
    _updateSendButtonState();
    followUpCount++; // ✅ 只有当用户实际发送回答时，才增加计数

    if (followUpCount > 2){
      endOfChat = true;
      return;
    }
    _botReply("Generating question...", "generate");

    String response = await openAIService.followUpGeneration(userAnswer);
    _handleAIResponse(response, userAnswer);
  }

  /// **处理 AI API 响应的通用逻辑**
  void _handleAIResponse(String response, String userText) {
    setState(() {
      messages.removeLast();

      if (response.contains("Error") || response.contains("Failed")) {
        messages.add({
          "role": "bot",
          "content": response,
          "retry": true,
          "type": "error"
        });
        isErrorState = true;
      } else {
        messages.add({
          "role": "bot",
          "content": response,
          "retry": true,
          "userText": userText,
          "type": "question"
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
      //isMemoed = false;
      isTextRead = false;
      endOfChat = false;
      _userInputController.clear();
      isUserInputEmpty = true;
      rawData = "";
      _simulateFileSend();
    });

    SharedPreferences.getInstance().then((prefs) {
      prefs.remove('chat_history_${widget.filePath}'); // ✅ 清空本地存储
      prefs.remove('startChat_${widget.filePath}');
      prefs.remove('isRetrying_${widget.filePath}');
      prefs.remove('isErrorState_${widget.filePath}');
      //prefs.remove('isMemoed_${widget.filePath}');
      prefs.remove('isTextRead_${widget.filePath}');
      prefs.remove('endOfChat_${widget.filePath}');
      prefs.remove('followUpCount_${widget.filePath}');
      prefs.remove('rawData_${widget.filePath}');
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
    List<String> questions = [];
    List<String> answers = [];

    for (int i = 0; i < messages.length; i++) {
      if (messages[i]["role"] == "bot" && messages[i]["type"] == "question") {
        questions.add(messages[i]["content"]);
      }
      else if (messages[i]["role"] == "user" && messages[i]["type"] == "answer") {
        answers.add(messages[i]["content"]);
      }
    }

    // ✅ 格式化 memo 内容
    String memoContent = "";
    for (int i = 0; i < questions.length; i++) {
      memoContent += "**Q: ${questions[i]}**\n";
      memoContent += "A: ${i < answers.length ? answers[i] : "(No answer)"}\n\n";
    }

    // ✅ 存入 S3
    fileManager.saveMemoToS3(memoName, userSub!, memoContent, widget.filePath);
    //isMemoed = true;
    _saveChatHistory();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Memo saved. You can find it in the Memo page."),
        duration: Duration(seconds: 3),
      ),
    );
  }

  void _updateSendButtonState() {
    setState(() {
      isUserInputEmpty = _userInputController.text.trim().isEmpty;
    });
  }

  void _botReply(String text, String type) {
    setState(() {
      messages.add({"role": "bot", "content": text, "type": type});
    });
    Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
    _saveChatHistory();
  }

  void _userReply(String text, String type) {
    setState(() {
      messages.add({"role": "user", "content": text, "type": type});
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
              itemCount: messages.length + ((showDetectedTextBox || isTextRead || hasWrittenToFile) ? 1 : 0),
              itemBuilder: (context, index) {
                if (!startChat) {
                  if (showDetectedTextBox && index == messages.length){
                    return Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Column(
                        children: [
                          const Text(
                            "Text detected from the image",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8), // ✅ 添加一点间距
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
                            child: const Text("Start Reflection"),
                          ),
                        ],
                      ),
                    );
                  }
                  else if (isTextRead && index == messages.length) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Column(
                        children: [
                          const SizedBox(height: 10),
                          ElevatedButton(
                            onPressed: () => rawData=="" ? null : _confirmText(),
                            child: const Text("Start Reflection"),
                          ),
                        ],
                      ),
                    );
                  }
                  else if (isEntryMode && hasWrittenToFile && index == messages.length) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Column(
                        children: [
                          const SizedBox(height: 10),
                          ElevatedButton(
                            onPressed: () => rawData == "" ? null : _confirmText(),
                            child: const Text("Start Reflection"),
                          ),
                        ],
                      ),
                    );
                  }
                }

                final message = messages[index];
                final isUser = message["role"] == "user";
                final isEditable = message["editable"] ?? false;

                return Column(
                  crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: () {
                        if (message["isFile"] == true) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => FilePreviewPage(fileName: widget.fileName, filePath: widget.filePath, fileUrl: fileUrl!),
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
                                ? Row(
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
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: Text(
                                    message["content"]!,
                                    style: const TextStyle(fontSize: 16),
                                    softWrap: true,
                                  ),
                                ),
                                if (message["showRefresh"]==true) // ✅ 仅 "Generating question..." 时显示 refresh icon
                                  Padding(
                                    padding: const EdgeInsets.only(left: 6),
                                    child: IconButton(
                                      icon: const Icon(Icons.refresh, color: Colors.blue),
                                      onPressed: () => _regeneration(index),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),

                    if (message["retry"] == true) // ✅ 显示 retry 超链接
                      Padding(
                        padding: const EdgeInsets.only(top: 4, left: 6),
                        child: RichText(
                          text: TextSpan(
                            style: const TextStyle(fontSize: 14, color: Colors.black),
                            children: [
                              const TextSpan(text: "Need a different question? Click to "),
                              TextSpan(
                                text: "regenerate",
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Colors.blue,
                                  decoration: TextDecoration.underline,
                                ),
                                recognizer: TapGestureRecognizer()..onTap = () => _regeneration(index),
                              ),
                              const TextSpan(text: "."),
                            ],
                          ),
                        ),
                      ),
                  ]
                );
              },
            ),
          ),

          if (!startChat && isEntryMode && !hasWrittenToFile)
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
                        hintText: "Type your entry...",
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                  icon: Icon(Icons.send, color: isUserInputEmpty ? Colors.grey : Colors.blue),
                  onPressed: isUserInputEmpty ? null : _handleEntryInput, // ✅ 绑定 `_handleEntryInput()`
                  ),
                ],
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
              padding: const EdgeInsets.only(bottom: 40.0),
              child: Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical:8, horizontal: 16),
                    child: Text(
                      "Three reflection questions are used up.\nTap to save this chat to Memo.",
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  ElevatedButton(
                    onPressed: _showMemoDialog,
                    child: const Text("Save to Memo"),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class FilePreviewPage extends StatefulWidget {
  final String fileUrl;
  final String fileName;
  final String filePath;

  const FilePreviewPage({
    super.key,
    required this.fileName,
    required this.fileUrl,
    required this.filePath,
  });

  @override
  _FilePreviewPageState createState() => _FilePreviewPageState();
}

class _FilePreviewPageState extends State<FilePreviewPage> {
  String? fileContent;
  bool isLoading = true;
  bool isTextFile = false;

  @override
  void initState() {
    super.initState();
    _determineFileType();
  }

  /// **判断文件类型**
  void _determineFileType() {
    String extension = widget.fileName.split('.').last.toLowerCase();
    if (["jpg", "jpeg", "png"].contains(extension)) {
      isTextFile = false; // ✅ 图片文件
      isLoading = false;
    } else if (["txt", "docx"].contains(extension)) {
      isTextFile = true; // ✅ 文本文件
      _fetchTextFile();  // ✅ 读取文本
    }
  }

  /// **从 S3 读取文本文件**
  Future<void> _fetchTextFile() async {
    try {
      final result = await Amplify.Storage.getUrl(
        path: StoragePath.fromString(widget.filePath),
      ).result;

      final response = await http.get(Uri.parse(result.url.toString()));
      setState(() {
        fileContent = utf8.decode(response.bodyBytes);
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        fileContent = "❌ Failed to load text file.";
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.fileName)),
      body: isLoading
        ? const Center(child: CircularProgressIndicator())
        : isTextFile
        ? SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            fileContent ?? "No content",
            style: const TextStyle(fontSize: 16),
          ),
        )
        : Center(
        child: Image.network(
          widget.fileUrl,
          width: double.infinity,
          fit: BoxFit.fitWidth,
        ),
      ),
    );
  }
}