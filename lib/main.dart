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
import 'package:google_fonts/google_fonts.dart';
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

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
        theme: ThemeData(
          primaryColor: Colors.blue,
          colorScheme: ColorScheme.light(
            primary: Colors.blue
          ),
          textTheme: GoogleFonts.latoTextTheme(),
        ),
        navigatorKey: navigatorKey,
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
  String _sortFileOption = "name";
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

    SharedPreferences prefs = await SharedPreferences.getInstance();
    Set<String> viewedFiles = prefs.getStringList("viewedFiles")?.toSet() ?? {};

    setState(() {
      final newFilePaths = files.map((file) => file.path).toSet();

      _newFiles = newFilePaths.difference(viewedFiles);

      _files = files;
      _isFileLoading = false;
      _sortItems(_files, _sortFileOption);
    });
  }

  void _sortItems(List<StorageItem> items, String sortOption) {
    if (items.isEmpty) return;
    else {
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
            return bTime.compareTo(aTime);
          });
        }
      });
    }
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

    final Stopwatch stopwatch = Stopwatch()..start();
    while (!success && retryCount < maxRetries) {
      try {
        safePrint("🔍 Requesting themes for $filePath (Attempt ${retryCount + 1})...");

        OpenAIService openAIService = OpenAIService();
        List<String> themes = await openAIService.analyzeMemoThemes(filePath);

        if (themes.isNotEmpty) {
          stopwatch.stop();
          safePrint("⏱️ Time taken for theme generation: "
              "${(stopwatch.elapsedMilliseconds / 1000).toStringAsFixed(2)} s");
          final prefs = await SharedPreferences.getInstance();
          await prefs.setStringList("memoThemes_$filePath", themes);

          _loadMemoThemes(filePath);
          safePrint("✅ Themes saved for $filePath");
          success = true;
        } else {
          safePrint("⚠️ API returned empty themes for $filePath, retrying...");
        }
      } catch (e) {
        safePrint("❌ Error analyzing memo themes for $filePath: $e");
      }
      if (!success) {
        retryCount++;
        await Future.delayed(const Duration(seconds: 2));
      }
    }
    if (!success) {
      safePrint(
          "❌ Failed to analyze themes for $filePath after $maxRetries attempts.");
    }
  }


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
            mainAxisSize: MainAxisSize.min,
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
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                        "Cancel", style: TextStyle(color: Colors.black87)),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      Navigator.pop(context);
                      fileManager.deleteFile(context, filePath,
                          isMemo ? _fetchMemos : _fetchFiles);
                      SharedPreferences prefs = await SharedPreferences
                          .getInstance();
                      if (isMemo) {
                        Set<String> viewedMemos = prefs.getStringList(
                            "viewedMemos")?.toSet() ?? {};
                        if (viewedMemos.contains(filePath)) {
                          viewedMemos.remove(filePath);
                          await prefs.setStringList(
                          "viewedMemos", viewedMemos.toList());
                        }
                      }
                      else {
                        Set<String> viewedFiles = prefs.getStringList(
                            "viewedFiles")?.toSet() ?? {};
                        if (viewedFiles.contains(filePath)) {
                          viewedFiles.remove(filePath);
                          await prefs.setStringList(
                          "viewedFiles", viewedFiles.toList());
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange),
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

  void _showTextEntryDialog() {
    TextEditingController textController = TextEditingController();

    showDialog(
      context: navigatorKey.currentContext!,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text("Create New Entry"),
          content: TextField(
            controller: textController,
            decoration: const InputDecoration(
              hintText: "Enter entry name",
              border: OutlineInputBorder(),
            ),
            maxLength: 30,
          ),
          actions: [
            TextButton(
              onPressed: () {
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                }
              },
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () async {
                String entryName = textController.text.trim();
                if (entryName.isNotEmpty) {
                  if (dialogContext.mounted) {
                    Navigator.pop(dialogContext);
                  }

                  String fileName = "TypedEntry_$entryName.txt";
                  String folderPath = "uploads/$_userSub/";
                  String uniqueFileName = await fileManager.generateUniqueFileName(folderPath, fileName);
                  String filePath = "uploads/$_userSub/$uniqueFileName";

                  Future.delayed(Duration.zero, () {
                    if (navigatorKey.currentContext!.mounted) {
                      Navigator.push(
                        navigatorKey.currentContext!,
                        MaterialPageRoute(
                          builder: (context) => FileDetailPage(
                            fileName: uniqueFileName,
                            filePath: filePath,
                          ),
                        ),
                      ).then((_) => _fetchFiles());
                    }
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
      List<List<String>> parsedThemes = storedThemes.map((themeText) {
        List<String> parts = themeText.split(" - ");
        String theme = parts.isNotEmpty ? parts[0].replaceAll("**", "").trim() : "Unknown";
        String description = parts.length > 1 ? parts[1].trim() : "";
        return [theme, description];
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


  bool showFileOptions = false;
  bool isImage(String fileName) {
    final imageExtensions = ['jpg', 'jpeg', 'png', 'gif', 'webp'];
    return imageExtensions.contains(fileName
        .split('.')
        .last
        .toLowerCase());
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Home"),
          actions: [
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: _signOut,
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(50),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(10),
              ),
              child: TabBar(
                onTap: (index) {
                  if (index == 0) {
                    _fetchFiles();
                  } else if (index == 1) {
                    _fetchMemos();
                  }
                },
                indicator: UnderlineTabIndicator(
                  borderSide: BorderSide(color: Colors.blue),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                labelColor: Colors.blue,
                unselectedLabelColor: Colors.black,
                tabs: const [
                  Tab(text: "Files"),
                  Tab(text: "Memos"),
                ],
              ),
            ),
          ),
        ),
        body: TabBarView(
          children: [
            _buildFilesPage(),
            _buildMemosPage(),
          ],
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
        floatingActionButton: SizedBox(
          width: MediaQuery.of(context).size.width * 0.6,
          height: 50,
          child: ElevatedButton(
            onPressed: () => _showUploadOptions(context),
            style: ElevatedButton.styleFrom(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              backgroundColor: Colors.blue,
            ),
            child: const Text(
              "Upload Data",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }

  void _showUploadOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildUploadButton(
                "Image (.jpg, .jpeg, .png)",
                Icons.image,
                    () {
                  Navigator.pop(context);
                  fileManager.uploadImage(_fetchFiles);
                },
              ),
              _buildUploadButton(
                "Document (.txt, .docx)",
                Icons.description,
                    () {
                  Navigator.pop(context);
                  fileManager.uploadDocument(_fetchFiles);
                },
              ),
              _buildUploadButton(
                "Create Entry",
                Icons.edit,
                    () {
                  Navigator.pop(context);
                  _showTextEntryDialog();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildUploadButton(String label, IconData icon, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: SizedBox(
        width: double.infinity,
        height: 50,
        child: ElevatedButton.icon(
          onPressed: onTap,
          icon: Icon(icon, size: 24),
          label: Text(
            label,
            style: const TextStyle(fontSize: 16),
          ),
          style: ElevatedButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
            elevation: 2,
            side: BorderSide(color: Colors.grey.shade300),
          ),
        ),
      ),
    );
  }


  Widget _buildFilesPage() {
    return _isFileLoading
        ? const Center(child: CircularProgressIndicator(color: Colors.blue))
        : _files.isEmpty
        ? Column(
          children: [
            const SizedBox(height: 280),
            const Center(
              child: Text(
                "Upload your first file for analysis",
                style: TextStyle(fontSize: 18, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        )
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
                crossAxisCount: 3,
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
                      _newFiles.remove(file.path);
                    });

                    SharedPreferences prefs = await SharedPreferences
                        .getInstance();
                    Set<String> viewedFiles = prefs.getStringList("viewedFiles")
                        ?.toSet() ?? {};
                    viewedFiles.add(file.path);
                    await prefs.setStringList(
                        "viewedFiles", viewedFiles.toList());

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
                      SizedBox.expand(
                        child: Card(
                          elevation: 3,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
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

                      if (isNewFile)
                        Positioned(
                          top: 6,
                          right: 6,
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: const BoxDecoration(
                              color: Colors.orange,
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
        ? const Center(child: CircularProgressIndicator(color: Colors.blue))
        : _memos.isEmpty
        ? Column(
          children: [
            const SizedBox(height: 280),
            const Center(
              child: Text(
                "No memos yet",
                style: TextStyle(fontSize: 18, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        )
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
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                      text: TextSpan(
                                        style: const TextStyle(fontSize: 14, color: Colors.black),
                                        children: [
                                          TextSpan(
                                            text: "${themeData[0]}: ",
                                            style: const TextStyle(fontWeight: FontWeight.bold),
                                          ),
                                          TextSpan(text: themeData[1]),
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

                    if (isNewMemo)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: const BoxDecoration(
                            color: Colors.orange,
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
      ],
    );
  }

}
