import 'dart:convert';
import 'package:amplify_flutter/amplify_flutter.dart';

class RekognitionService {
  final String apiName = "chatbotAPI"; // ✅ Amplify API Gateway 配置的名称
  final String bucketName = "autoethnography-appa497d-dev"; // ✅ S3 bucket 配置的名称

  /// **调用 AWS Rekognition 识别 S3 图片文字**
  Future<String?> detectTextFromS3(String filePath) async {
    try {
      safePrint("Print File Path: $filePath");
      final Map<String, dynamic> requestBody = {
        "Image": {
          "S3Object": {
            "Bucket": bucketName, // 你的 S3 存储桶名称
            "Name": filePath
          }
        }
      };

      final RestOperation request = Amplify.API.post(
        "/detectText", // ✅ REST API 路径（在 API Gateway 配置）
        apiName: apiName, // ✅ 指定 API Gateway 名称
        body: HttpPayload.json(requestBody),
      );

      final AWSHttpResponse response = await request.response; // ✅ 使用 RestResponse
      // ✅ 检查 HTTP 状态码
      safePrint("Status Code: ${response.statusCode}");
      if (response.statusCode != 200) {
        safePrint("❌ AWS Rekognition API 调用失败: ${response.statusCode}");
        return null;
      }

      // ✅ 先将 `Stream<List<int>>` 转换为 `List<int>`
      final List<int> responseBytes = await response.body.expand((x) => x).toList();

      // ✅ 解析 JSON 响应
      final Map<String, dynamic> responseMessage = jsonDecode(utf8.decode(responseBytes));
      safePrint("Response body: $responseMessage");
      if (responseMessage.isNotEmpty && responseMessage.containsKey('detected_texts')) {
          safePrint("✅ Collecting Texts!");
          List<dynamic> detectedTexts = responseMessage['detected_texts'];
          // 直接返回拼接后的文本
          return detectedTexts.join(" ");
      }
      return null;
    } catch (e) {
      safePrint("❌ AWS Rekognition 识别失败: $e");
      return null;
    }
  }
}
