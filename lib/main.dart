import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'package:amplify_authenticator/amplify_authenticator.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:amplify_storage_s3/amplify_storage_s3.dart';
import 'package:amplify_api/amplify_api.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'amplifyconfiguration.dart';
import 'FileManager.dart';
import 'DataAnalysis.dart';
import 'MemoArchive.dart';
import 'OpenAIService.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
    _configureAmplify();
  }

  void _configureAmplify() async {
    try {
      await Amplify.addPlugins([
        AmplifyAuthCognito(),
        AmplifyStorageS3(),
        AmplifyAPI()
      ]);
      await Amplify.configure(amplifyconfig);
    } catch (e) {
      safePrint("❌ Amplify configuration failure: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Authenticator(
      child: MaterialApp(
        builder: Authenticator.builder(),
        home: const HomePage(),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String? _userSub;
  late FileManager fileManager;
  List<StorageItem> _files = [];
  List<StorageItem> _memos = [];
  Map<String, List<List<String>>> _memoThemes = {};
  bool _isFileLoading = true;
  bool _isMemoLoading = true;
  int _selectedPage = 0; // 0 = Files, 1 = Memos
  String _sortFileOption = "name"; // ✅ 默认按文件名排序
  String _sortMemoOption = "name";
  Set<String> _newFiles = {};
  Set<String> _newMemos = {};

  @override
  void initState() {
    super.initState();
    _getUserInfo();
  }

  Future<void> _getUserInfo() async {
    final user = await Amplify.Auth.getCurrentUser();
    setState(() {
      _userSub = user.userId;
      fileManager = FileManager(_userSub!);
      _fetchFiles();
      _fetchMemos();
    });
  }

  Future<void> _fetchFiles() async {
    final files = await fileManager.listFiles(true);

    // ✅ 获取已读文件列表
    SharedPreferences prefs = await SharedPreferences.getInstance();
    Set<String> viewedFiles = prefs.getStringList("viewedFiles")?.toSet() ?? {};

    setState(() {
      final newFilePaths = files.map((file) => file.path).toSet();

      // ✅ 只把用户没读过的文件标记为新文件
      _newFiles = newFilePaths.difference(viewedFiles);

      _files = files;
      _isFileLoading = false;
      _sortItems(_files, _sortFileOption);
    });
  }

  void _sortItems(List<StorageItem> items, String sortOption) {
    setState(() {
      if (sortOption == "name") {
        items.sort((a, b) =>
            a.path
                .split('/')
                .last
                .compareTo(b.path
                .split('/')
                .last));
      } else {
        items.sort((a, b) {
          DateTime aTime = a.lastModified ??
              DateTime.fromMillisecondsSinceEpoch(0);
          DateTime bTime = b.lastModified ??
              DateTime.fromMillisecondsSinceEpoch(0);
          return bTime.compareTo(aTime); // ✅ 按时间从新到旧排序
        });
      }
    });
  }


  Future<void> _fetchMemos() async {
    final memos = await fileManager.listFiles(false);
    SharedPreferences prefs = await SharedPreferences.getInstance();
    Set<String> viewedMemos = prefs.getStringList("viewedMemos")?.toSet() ?? {};

    setState(() {
      final newMemoPaths = memos.map((memo) => memo.path).toSet();
      _newMemos = newMemoPaths.difference(viewedMemos);
      _memos = memos;
      _isMemoLoading = false;
      _sortItems(_memos, _sortMemoOption);
    });

    await Future.wait(_memos.map((memo) => _loadMemoThemes(memo.path)));

    // ✅ 仅对 `themes 为空` 的 Memo 请求分析
    for (var memo in _memos) {
      if (_memoThemes[memo.path] == null || _memoThemes[memo.path]!.isEmpty) {
        _analyzeMemoThemesWithRetry(memo.path);
      }
    }
  }

  Future<void> _analyzeMemoThemesWithRetry(String filePath) async {
    int retryCount = 0;
    const int maxRetries = 10;
    bool success = false;

    while (!success && retryCount < maxRetries) {
      try {
        safePrint("🔍 Requesting themes for $filePath (Attempt ${retryCount + 1})...");

        OpenAIService openAIService = OpenAIService();
        List<String> themes = await openAIService.analyzeMemoThemes(filePath);

        if (themes.isNotEmpty) {
          // ✅ 成功获取 themes，存入 SharedPreferences
          final prefs = await SharedPreferences.getInstance();
          await prefs.setStringList("memoThemes_$filePath", themes);

          _loadMemoThemes(filePath);
          safePrint("✅ Themes saved for $filePath: $themes");
          success = true;
        } else {
          safePrint("⚠️ API returned empty themes for $filePath, retrying...");
        }
      } catch (e) {
        safePrint("❌ Error analyzing memo themes for $filePath: $e");
      }
      if (!success) {
        retryCount++;
        await Future.delayed(const Duration(seconds: 2)); // ✅ 等待 2 秒后重试
      }
    }
    if (!success) {
      safePrint(
          "❌ Failed to analyze themes for $filePath after $maxRetries attempts.");
    }
  }


  /// **退出登录**
  Future<void> _signOut() async {
    try {
      await Amplify.Auth.signOut();
      safePrint("✅ Logged out");
    } on AuthException catch (e) {
      safePrint("❌ Log out failure: ${e.message}");
    }
  }

  void _showDeleteDialog(BuildContext context, String filePath, bool isMemo) {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext ctx) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min, // ✅ 解决 Overflow 问题
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isMemo ? "Delete Memo?" : "Delete File?",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                isMemo ? "This will not affect the file related to this Memo."
                    : "This will not affect the Memos related to this file.",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.normal),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context), // 取消按钮
                    child: const Text(
                        "Cancel", style: TextStyle(color: Colors.black87)),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      Navigator.pop(context); // 先关闭弹窗
                      fileManager.deleteFile(context, filePath,
                          isMemo ? _fetchMemos : _fetchFiles); // 执行删除
                      SharedPreferences prefs = await SharedPreferences
                          .getInstance();
                      Set<String> viewedFiles = prefs.getStringList(
                          "viewedFiles")?.toSet() ?? {};
                      if (viewedFiles.contains(filePath)) {
                        viewedFiles.remove(filePath);
                        await prefs.setStringList(
                            "viewedFiles", viewedFiles.toList());
                      }
                    },
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red),
                    child: const Text(
                        "Delete", style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void _showTextEntryDialog(BuildContext context) {
    TextEditingController textController = TextEditingController();

    showDialog(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: const Text("Create New Entry"),
          content: TextField(
            controller: textController,
            decoration: const InputDecoration(hintText: "Enter file name"),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () async {
                String entryName = textController.text.trim();
                if (entryName.isNotEmpty) {
                  Navigator.pop(ctx);
                  // ✅ 生成 `TypedEntry_[name].txt`，但不创建文件
                  String fileName = "TypedEntry_$entryName.txt";
                  String folderPath = "uploads/$_userSub/";
                  String uniqueFileName = await fileManager
                      .generateUniqueFileName(folderPath, fileName);
                  String filePath = "uploads/$_userSub/$uniqueFileName"; // ✅ 生成上传路径

                  // ✅ 进入 `FileDetailPage`，并在退出时刷新 `File List`
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          FileDetailPage(
                            fileName: uniqueFileName,
                            filePath: filePath,
                          ),
                    ),
                  ).then((_) {
                    _fetchFiles(); // ✅ 当用户退出 Chatbot 页面时，刷新文件列表
                  });
                }
              },
              child: const Text("Create"),
            ),
          ],
        );
      },
    );
  }

  Future<void> _loadMemoThemes(String filePath) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String>? storedThemes = prefs.getStringList("memoThemes_$filePath");

    if (storedThemes != null && storedThemes.isNotEmpty) {
      // ✅ 解析 `themes`，拆分成 `List<List<String>>`
      List<List<String>> parsedThemes = storedThemes.map((themeText) {
        List<String> parts = themeText.split(" - ");
        String theme = parts.isNotEmpty ? parts[0].replaceAll("**", "").trim() : "Unknown";
        String description = parts.length > 1 ? parts[1].trim() : "";
        return [theme, description]; // ✅ 以列表存储 theme 和 description
      }).toList();

      setState(() {
        _memoThemes[filePath] = parsedThemes;
      });
    } else {
      _memoThemes[filePath] = [];
    }
  }



  String formatTimestamp(DateTime? timestamp) {
    if (timestamp == null) return "Unknown";
    return "${timestamp.year}-${timestamp.month.toString().padLeft(2, '0')}-${timestamp.day.toString().padLeft(2, '0')} "
        "${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}";
  }


  bool showFileOptions = false; // ✅ 控制按钮显示状态
  bool isImage(String fileName) {
    final imageExtensions = ['jpg', 'jpeg', 'png', 'gif', 'webp'];
    return imageExtensions.contains(fileName
        .split('.')
        .last
        .toLowerCase());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Home"),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _signOut,
          ),
        ],
      ),
      body: Column(
        children: [
          ToggleButtons(
            isSelected: [_selectedPage == 0, _selectedPage == 1],
            onPressed: (index) {
              setState(() {
                _selectedPage = index;
                if (_selectedPage == 1) {
                  _fetchMemos();
                }
              });
            },
            borderRadius: BorderRadius.circular(8),
            children: const [
              Padding(padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text("Files")),
              Padding(padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text("Memos")),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: _selectedPage == 0 ? _buildFilesPage() : _buildMemosPage(),
          ),
        ],
      ),

      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: Stack(
        alignment: Alignment.bottomCenter, // ✅ 让按钮居中
        children: [
          if (showFileOptions)
            Padding(
              padding: const EdgeInsets.only(bottom: 70), // ✅ 让选项悬浮在主按钮上方
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center, // ✅ 选项水平居中
                children: [
                  FloatingActionButton(
                    heroTag: "btnImage",
                    onPressed: () {
                      fileManager.uploadImage(context, _fetchFiles);
                      setState(() => showFileOptions = false);
                    },
                    child: const Icon(Icons.image),
                    tooltip: "Upload Image"
                  ),
                  const SizedBox(width: 10), // ✅ 按钮间隔
                  FloatingActionButton(
                    heroTag: "btnDoc",
                    onPressed: () {
                      fileManager.uploadDocument(context, _fetchFiles);
                      setState(() => showFileOptions = false);
                    },
                    child: const Icon(Icons.description),
                    tooltip: "Upload Document"
                  ),
                  const SizedBox(width: 10),
                  FloatingActionButton(
                    heroTag: "btnEntry",
                    onPressed: () => _showTextEntryDialog(context),
                    child: const Icon(Icons.edit),
                    tooltip: "New Entry"
                  ),
                ],
              ),
            ),

          FloatingActionButton(
            heroTag: "btnMain",
            onPressed: () {
              setState(() {
                showFileOptions = !showFileOptions; // ✅ 切换上传选项
              });
            },
            child: Icon(showFileOptions ? Icons.close : Icons.add),
          ),
        ],
      ),
    );
  }


  Widget _buildFilesPage() {
    return _isFileLoading
        ? const Center(child: CircularProgressIndicator())
        : _files.isEmpty
        ? const Center(child: Text("Upload your first file for analysis"))
        : Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              const Text("Sort by: ", style: TextStyle(fontSize: 16)),
              DropdownButton<String>(
                value: _sortFileOption,
                onChanged: (String? newValue) {
                  setState(() {
                    _sortFileOption = newValue!;
                    _sortItems(_files, _sortFileOption);
                  });
                },
                alignment: Alignment.center,
                items: const [
                  DropdownMenuItem(value: "name", child: Text("Name")),
                  DropdownMenuItem(value: "time", child: Text("Upload Time")),
                ],
              ),
            ],
          ),
        ),

        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: GridView.builder(
              itemCount: _files.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3, // ✅ 每行 3 个图标
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemBuilder: (context, index) {
                final file = _files[index];
                final fileName = file.path
                    .split('/')
                    .last;
                final isNewFile = _newFiles.contains(file.path);

                return GestureDetector(
                  onLongPress: () =>
                      _showDeleteDialog(context, file.path, false),
                  onTap: () async {
                    setState(() {
                      _newFiles.remove(file.path); // ✅ 移除红点
                    });

                    // ✅ 保存到 shared_preferences
                    SharedPreferences prefs = await SharedPreferences
                        .getInstance();
                    Set<String> viewedFiles = prefs.getStringList("viewedFiles")
                        ?.toSet() ?? {};
                    viewedFiles.add(file.path);
                    await prefs.setStringList(
                        "viewedFiles", viewedFiles.toList());

                    // ✅ 进入文件详情页面
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            FileDetailPage(
                              fileName: fileName,
                              filePath: file.path,
                            ),
                      ),
                    );
                  },
                  child: Stack(
                    children: [
                      SizedBox.expand( // ✅ 确保 `Card` 组件填满网格
                        child: Card(
                          elevation: 3,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            // ✅ 避免 `Column` 组件变形
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                isImage(file.path) ? Icons.image : Icons
                                    .insert_drive_file,
                                size: 50,
                                color: Colors.blue,
                              ),
                              Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Text(
                                  fileName,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontSize: 14,
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // ✅ 红点：如果是新文件，则显示
                      if (isNewFile)
                        Positioned(
                          top: 6,
                          right: 6,
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }


  Widget _buildMemosPage() {
    return _isMemoLoading
        ? const Center(child: CircularProgressIndicator())
        : _memos.isEmpty
        ? const Center(child: Text("No memos yet"))
        : Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              const Text("Sort by: ", style: TextStyle(fontSize: 16)),
              DropdownButton<String>(
                value: _sortMemoOption,
                onChanged: (String? newValue) {
                  setState(() {
                    _sortMemoOption = newValue!;
                    _sortItems(_memos, _sortMemoOption);
                  });
                },
                alignment: Alignment.center,
                items: const [
                  DropdownMenuItem(value: "name", child: Text("Name")),
                  DropdownMenuItem(value: "time", child: Text("Upload Time")),
                ],
              ),
            ],
          ),
        ),

        Expanded(
          child: ListView.builder(
            itemCount: _memos.length,
            itemBuilder: (context, index) {
              final memo = _memos[index];
              final memoName = memo.path.split('/').last;
              final isNewMemo = _newMemos.contains(memo.path);

              // ✅ 从 `_memoThemes` 读取 themes
              List<List<String>> themes = _memoThemes[memo.path] ?? [];

              return GestureDetector(
                onLongPress: () => _showDeleteDialog(context, memo.path, true),
                onTap: () async {
                  setState(() {
                    _newMemos.remove(memo.path);
                  });

                  SharedPreferences prefs = await SharedPreferences.getInstance();
                  Set<String> viewedMemos =
                      prefs.getStringList("viewedMemos")?.toSet() ?? {};
                  viewedMemos.add(memo.path);
                  await prefs.setStringList("viewedMemos", viewedMemos.toList());

                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MemoDetailPage(filePath: memo.path),
                    ),
                  );
                },
                child: Stack(
                  children: [
                    Card(
                      elevation: 3,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // ✅ 标题（1行）
                            Text(
                              memoName,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),

                            // ✅ 创建时间（1行）
                            Text(
                              "Created on: ${formatTimestamp(memo.lastModified)}",
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.grey,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 8),

                            // ✅ Themes 显示
                            if (themes.isEmpty)
                              const Text(
                                "Analyzing themes...",
                                style: TextStyle(
                                  fontSize: 14,
                                  fontStyle: FontStyle.italic,
                                  color: Colors.grey,
                                ),
                              )
                            else
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: themes.take(3).map((themeData) {
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: RichText(
                                      overflow: TextOverflow.ellipsis, // ✅ 超出部分用省略号
                                      maxLines: 1, // ✅ 只占一行
                                      text: TextSpan(
                                        style: const TextStyle(fontSize: 14, color: Colors.black),
                                        children: [
                                          TextSpan(
                                            text: "${themeData[0]}: ", // ✅ 主题加粗
                                            style: const TextStyle(fontWeight: FontWeight.bold),
                                          ),
                                          TextSpan(text: themeData[1]), // ✅ 描述正常
                                        ],
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

}
