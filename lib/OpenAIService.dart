import 'dart:convert';
import 'package:amplify_flutter/amplify_flutter.dart';

class OpenAIService {
  final String apiName = "chatbotAPI";
  final String bucketName = "autoethnography-appa497d-dev";

  Future<String> initialGeneration(String userText) async {
    return _generateQuestion(userText, "generate_initial");
  }

  Future<String> regenerate(String userText) async {
    return _generateQuestion(userText, "regenerate");
  }

  Future<String> followUpGeneration(String userAnswer) async {
    return _generateQuestion(userAnswer, "follow_up");
  }

  Future<String> _generateQuestion(String userText, String requestType) async {
    try {
      final Map<String, dynamic> requestBody = {
        "text": userText,
        "request_type": requestType
      };

      final RestOperation request = Amplify.API.post(
        "/generateQuestion",
        apiName: apiName,
        body: HttpPayload.json(requestBody),
      );

      final AWSHttpResponse response = await request.response;

      if (response.statusCode != 200) {
        return "Failed to generate a reflective question. Please try again. "
            "Status Code: ${response.statusCode}";
      }

      final List<int> responseBytes = await response.body.expand((x) => x).toList();
      final Map<String, dynamic> responseData = jsonDecode(utf8.decode(responseBytes));
      safePrint("✅Question: ${responseData["message"]}");
      return responseData["message"] ?? "No response from AI service.";
    } catch (e) {
      safePrint("Error connecting to AI service. $e");
      return "Error connecting to AI service.";
    }
  }

  Future<List<String>> analyzeMemoThemes(String fileKey) async {
    try {
      final Map<String, dynamic> requestBody = {
        "bucket": bucketName,
        "file_key": fileKey
      };

      final RestOperation request = Amplify.API.post(
        "/themes",
        apiName: apiName,
        body: HttpPayload.json(requestBody),
      );

      final AWSHttpResponse response = await request.response.timeout(Duration(seconds: 60));

      if (response.statusCode != 200) {
        return ["Failed to analyze memo themes."];
      }

      final List<int> responseBytes = await response.body.expand((x) => x).toList();
      final Map<String, dynamic> responseData = jsonDecode(utf8.decode(responseBytes));

      return List<String>.from(responseData["themes"] ?? []);
    } catch (e) {
      safePrint("Error connecting to AI service: $e");
      return [];
    }
  }

}

