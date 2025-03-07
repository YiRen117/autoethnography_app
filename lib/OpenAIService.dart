import 'dart:convert';
import 'package:amplify_flutter/amplify_flutter.dart';

class OpenAIService {
  final String apiName = "chatbotAPI"; // ✅ Amplify API Gateway 名称

  /// **生成 Reflective Question**
  Future<String> initialGeneration(String userText) async {
    return _generateQuestion(userText, "generate_initial");
  }

  /// **重新生成 Reflective Question**
  Future<String> regenerate(String userText) async {
    return _generateQuestion(userText, "regenerate");
  }

  /// **生成 Follow-Up Question**
  Future<String> followUpGeneration(String userAnswer) async {
    return _generateQuestion(userAnswer, "follow_up");
  }

  /// **通用 API 请求逻辑**
  Future<String> _generateQuestion(String userText, String requestType) async {
    try {
      final Map<String, dynamic> requestBody = {
        "text": userText,
        "request_type": requestType
      };

      final RestOperation request = Amplify.API.post(
        "/generateQuestion", // ✅ REST API Gateway 路径
        apiName: apiName,
        body: HttpPayload.json(requestBody),
      );

      final AWSHttpResponse response = await request.response;

      safePrint("Status Code: ${response.statusCode}");
      if (response.statusCode != 200) {
        return "Failed to generate a reflective question. Please try again.";
      }

      // ✅ 解析 API 返回的 JSON 数据
      final List<int> responseBytes = await response.body.expand((x) => x).toList();
      final Map<String, dynamic> responseData = jsonDecode(utf8.decode(responseBytes));
      return responseData["message"] ?? "No response from AI service.";
    } catch (e) {
      return "Error connecting to AI service.";
    }
  }
}

