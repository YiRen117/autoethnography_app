import 'dart:convert';
import 'package:amplify_flutter/amplify_flutter.dart';

class OpenAIService {
  final String apiName = "chatbotAPI"; // ✅ Amplify API Gateway 名称

  /// **生成 Reflective Question**
  Future<String> generateReflectiveQuestion(String userText) async {
    try {
      final Map<String, dynamic> requestBody = {
        "text": userText,
        "request_type": "generate_initial"
      };

      final RestOperation request = Amplify.API.post(
        "/generateQuestion", // ✅ REST API Gateway 路径
        apiName: apiName, // ✅ 指定 API Gateway 名称
        body: HttpPayload.json(requestBody),
      );

      final AWSHttpResponse response = await request.response;

      safePrint("Status Code: ${response.statusCode}");
      if (response.statusCode != 200) {
        safePrint("❌ OpenAI API 调用失败: ${response.statusCode}");
        return "Failed to generate a reflective question. Please try again.";
      }

      // ✅ 解析 API 返回的 JSON 数据
      final List<int> responseBytes = await response.body.expand((x) => x).toList();
      final Map<String, dynamic> responseData = jsonDecode(utf8.decode(responseBytes));
      safePrint("Response body: $responseData");

      return responseData["message"] ?? "No response from AI service.";
    } catch (e) {
      safePrint("❌ OpenAI 请求错误: $e");
      return "Error connecting to AI service.";
    }
  }

  /// **重新生成 Reflective Question**
  Future<String> regenerateReflectiveQuestion(String userText) async {
    try {
      final Map<String, dynamic> requestBody = {
        "text": userText,
        "request_type": "regenerate"
      };

      final RestOperation request = Amplify.API.post(
        "/generateQuestion", // ✅ REST API Gateway 路径
        apiName: apiName, // ✅ 指定 API Gateway 名称
        body: HttpPayload.json(requestBody),
      );

      final AWSHttpResponse response = await request.response;

      safePrint("Status Code: ${response.statusCode}");
      if (response.statusCode != 200) {
        safePrint("❌ OpenAI API 调用失败: ${response.statusCode}");
        return "Failed to regenerate a question. Please try again.";
      }

      // ✅ 解析 API 返回的 JSON 数据
      final List<int> responseBytes = await response.body.expand((x) => x).toList();
      final Map<String, dynamic> responseData = jsonDecode(utf8.decode(responseBytes));
      safePrint("Response body: $responseData");

      return responseData["message"] ?? "No response from AI service.";
    } catch (e) {
      safePrint("❌ OpenAI 请求错误: $e");
      return "Error connecting to AI service.";
    }
  }
}
