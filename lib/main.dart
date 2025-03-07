import 'package:flutter/material.dart';
import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'package:amplify_authenticator/amplify_authenticator.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:amplify_storage_s3/amplify_storage_s3.dart';
import 'package:amplify_api/amplify_api.dart';
import 'amplifyconfiguration.dart';
import 'FileManager.dart';
import 'DataAnalysis.dart';

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
      safePrint("❌ Amplify 配置失败: $e");
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
  bool _isLoading = true;
  int _selectedPage = 0; // 0 = Files, 1 = Memos

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
    });
  }

  Future<void> _fetchFiles() async {
    final files = await fileManager.listFiles();
    setState(() {
      _files = files;
      _isLoading = false;
    });
  }

  /// **退出登录**
  Future<void> _signOut() async {
    try {
      await Amplify.Auth.signOut();
      safePrint("✅ 用户已登出");
    } on AuthException catch (e) {
      safePrint("❌ 登出失败: ${e.message}");
    }
  }

  void _showDeleteDialog(BuildContext context, String filePath) {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext ctx) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,  // ✅ 解决 Overflow 问题
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "删除文件",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              const Text("Delete File?"),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context), // 取消按钮
                    child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context); // 先关闭弹窗
                      fileManager.deleteFile(context, filePath, _fetchFiles); // 执行删除
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                    child: const Text("Delete"),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
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
          // 页面切换按钮
          ToggleButtons(
            isSelected: [_selectedPage == 0, _selectedPage == 1],
            onPressed: (index) {
              setState(() {
                _selectedPage = index;
              });
            },
            borderRadius: BorderRadius.circular(8),
            children: const [
              Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text("Files")),
              Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text("Memos")),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: _selectedPage == 0 ? _buildFilesPage() : _buildMemosPage(),
          ),
        ],
      ),
      floatingActionButton: _selectedPage == 0
          ? FloatingActionButton(
            onPressed: () => fileManager.uploadFile(context, _fetchFiles),
            child: const Icon(Icons.add),
          )
          : null,
    );
  }

  Widget _buildFilesPage() {
    return _isLoading
        ? const Center(child: CircularProgressIndicator())
        : _files.isEmpty
        ? const Center(child: Text("No files uploaded"))
        : Padding(
      padding: const EdgeInsets.all(8.0),
      child: GridView.builder(
        itemCount: _files.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemBuilder: (context, index) {
          final file = _files[index];
          return GestureDetector(
            onLongPress: () => _showDeleteDialog(context, file.path),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => FileDetailPage(
                  fileName: file.path.split('/').last,
                  filePath: file.path,
                ),
              ),
            ),
            child: Card(
              elevation: 3,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.insert_drive_file, size: 50, color: Colors.blue),
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(
                      file.path.split('/').last,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMemosPage() {
    return const Center(child: Text("No memos yet"));
  }
}
