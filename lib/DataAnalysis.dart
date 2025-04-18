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
  int followUpCount = 0;
  bool isUserInputEmpty = true;
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
    _scrollController.dispose();
    super.dispose();
  }

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

  void _scrollToBottomAfterBuild() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  Future<void> _getUserInfo() async {
    final user = await Amplify.Auth.getCurrentUser();
    setState(() {
      userSub = user.userId;
      fileManager = FileManager(userSub!);
    });
    _loadChatHistory();
  }

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

  Future<void> _saveChatHistory() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    hasChatHistory = true;
    final String chatData = jsonEncode(messages);
    final rawDataJson = jsonEncode({"content": rawData});
    await prefs.setString('chat_history_${widget.filePath}', chatData);
    await prefs.setBool('startChat_${widget.filePath}', startChat);
    await prefs.setBool('isRetrying_${widget.filePath}', isRetrying);
    await prefs.setBool('isErrorState_${widget.filePath}', isErrorState);
    //await prefs.setBool('isMemoed_${widget.filePath}', isMemoed);
    await prefs.setBool('isTextRead_${widget.filePath}', isTextRead);
    await prefs.setBool('endOfChat_${widget.filePath}', endOfChat);
    await prefs.setInt('followUpCount_${widget.filePath}', followUpCount);
    await prefs.setString('rawData_${widget.filePath}', rawDataJson);

    _scrollToBottomAfterBuild();
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
        final String? rawDataJson = prefs.getString('rawData_${widget.filePath}');
        if (rawDataJson != null) {
          rawData = jsonDecode(rawDataJson)["content"];
        }

        final lastMessage = messages.last;
        if (lastMessage["role"] == "bot" && lastMessage["type"] == "generate") {
          lastMessage["showRefresh"] = true;
          _restoreLastMessage(lastMessage);
        }
      });
      _scrollToBottomAfterBuild();
    } else {
      hasChatHistory = false;
    }

    if (!hasChatHistory) {
      _simulateFileSend();
    }
  }

  Future<void> _restoreLastMessage(Map<String, dynamic> lastMessage) async {
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
      safePrint("❌ Failed to get file URL: $e");
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
      bool isEmpty = await _isFileEmpty(widget.filePath);
      if (widget.fileName.startsWith("TypedEntry_") && isEmpty) {
        isEntryMode = true;
        setState(() {
          messages.add({
            "role": "bot",
            "content": "Please type your message below to begin.",
            "type": "setup"
          });
        });
      } else {
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
    _scrollToBottomAfterBuild();
  }

  Future<bool> _isFileEmpty(String filePath) async {
    try {
      final files = await fileManager.listFiles(true);

      for (var file in files) {
        if (file.path == filePath) {
          return false;
        }
      }
      return true;
    } catch (e) {
      safePrint("❌ Failed to check file existence: $e");
      return true;
    }
  }

  void _handleEntryInput() async {
    FocusScope.of(context).unfocus();
    String userText = _userInputController.text.trim();

    if (userText.isEmpty) return;
    await fileManager.writeEntryToS3(widget.fileName, userText);

    setState(() {
      messages.add({"role": "user", "content": userText, "type": "setup"});
      _userInputController.clear();
      _updateSendButtonState();
      rawData = userText;
      hasWrittenToFile = true;
    });
    _scrollToBottomAfterBuild();
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
    FocusScope.of(context).unfocus();
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

    final Stopwatch stopwatch = Stopwatch()..start();
    String response = await openAIService.initialGeneration(rawData!);
    stopwatch.stop();
    if (!(response.contains("Error") || response.contains("Failed"))) {
      safePrint("⏱️ Time taken for question generation: "
          "${(stopwatch.elapsedMilliseconds / 1000).toStringAsFixed(2)} s");
    }

    _handleAIResponse(response, rawData!);
    startChat = true;
  }

  void retryError() async {
    if (!isErrorState || messages.isEmpty) return;

    String requestType = messages.last["requestType"] ?? "initial";
    String userText = messages.last["userText"] ?? "";

    if (userText == "") {
      _restoreLastMessage(messages.last);
      userText = messages.last["userText"];
    }

    String response;
    final Stopwatch stopwatch;
    switch (requestType) {
      case "follow_up":
        stopwatch = Stopwatch()..start();
        response = await openAIService.followUpGeneration(userText);
        break;
      case "regenerate":
        stopwatch = Stopwatch()..start();
        response = await openAIService.regenerate(userText);
        break;
      case "generate_initial":
      default:
        stopwatch = Stopwatch()..start();
        response = await openAIService.initialGeneration(userText);
        break;
    }
    stopwatch.stop();
    if (!(response.contains("Error") || response.contains("Failed"))) {
      safePrint("⏱️ Time taken for question generation: "
          "${(stopwatch.elapsedMilliseconds / 1000).toStringAsFixed(2)} s");
    }

    _handleAIResponse(response, userText);
  }

  void _regeneration(int index) async {
    FocusScope.of(context).unfocus();
    setState(() {
      isRetrying = true;
    });

    String userText = messages[index]["userText"] ?? "";

    messages.removeLast();
    _botReply("Generating question...", "generate");
    if (userText == "") {
      _restoreLastMessage(messages.last);
      userText = messages.last["userText"];
    }

    final Stopwatch stopwatch = Stopwatch()..start();
    String response = await openAIService.regenerate(userText);
    stopwatch.stop();
    if (!(response.contains("Error") || response.contains("Failed"))) {
      safePrint("⏱️ Time taken for question generation: "
          "${(stopwatch.elapsedMilliseconds / 1000).toStringAsFixed(2)} s");
    }

    _scrollToBottomAfterBuild();
    _handleAIResponse(response, userText);
    setState(() {
      isRetrying = false;
    });
  }

  void _followUpGeneration() async {
    FocusScope.of(context).unfocus();
    String userAnswer = _userInputController.text.trim();

    for (int i = 0; i < messages.length; i++) {
      if (messages[i]["role"] == "bot" && messages[i]["retry"] == true) {
        messages[i]["retry"] = false;
      }
    }

    _userReply(userAnswer, "answer");
    _userInputController.clear();
    _updateSendButtonState();
    followUpCount++;

    if (followUpCount > 2){
      endOfChat = true;
      return;
    }
    _botReply("Generating question...", "generate");

    final Stopwatch stopwatch = Stopwatch()..start();
    String response = await openAIService.followUpGeneration(userAnswer);
    stopwatch.stop();
    if (!(response.contains("Error") || response.contains("Failed"))) {
      safePrint("⏱️ Time taken for question generation: "
          "${(stopwatch.elapsedMilliseconds / 1000).toStringAsFixed(2)} s");
    }

    _handleAIResponse(response, userAnswer);
  }

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
    _scrollToBottomAfterBuild();
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
      prefs.remove('chat_history_${widget.filePath}');
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
        TextEditingController memoNameController = TextEditingController();

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
                  _saveMemoToS3(memoName);
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

    String memoContent = "";
    for (int i = 0; i < questions.length; i++) {
      memoContent += "**Q: ${questions[i]}**\n";
      memoContent += "A: ${i < answers.length ? answers[i] : "(No answer)"}\n\n";
    }

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
    _scrollToBottomAfterBuild();
    _saveChatHistory();
  }

  void _userReply(String text, String type) {
    setState(() {
      messages.add({"role": "user", "content": text, "type": type});
    });
    _scrollToBottomAfterBuild();
    _saveChatHistory();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Chatbot"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: "Restart Chat",
            onPressed: _restartChat,
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
                          const SizedBox(height: 8),
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
                              maxWidth: MediaQuery.of(context).size.width * 0.75,
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
                                if (message["showRefresh"]==true)
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

                    if (message["retry"] == true)
                      Padding(
                        padding: const EdgeInsets.only(top: 4, left: 6),
                        child: RichText(
                          text: TextSpan(
                            style: const TextStyle(fontSize: 14, color: Colors.black),
                            children: [
                              TextSpan(text: (message["type"]=="error") ? "Click to " : "Need a different question? Click to "),
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
                  onPressed: isUserInputEmpty ? null : _handleEntryInput,
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

  void _determineFileType() {
    String extension = widget.fileName.split('.').last.toLowerCase();
    if (["jpg", "jpeg", "png"].contains(extension)) {
      isTextFile = false;
      isLoading = false;
    } else if (["txt", "docx"].contains(extension)) {
      isTextFile = true;
      _fetchTextFile();
    }
  }

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
        ? const Center(child: CircularProgressIndicator(color: Colors.blue,))
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