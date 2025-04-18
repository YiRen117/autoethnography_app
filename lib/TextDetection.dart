import 'dart:convert';
import 'package:amplify_flutter/amplify_flutter.dart';

class TextDetection {
  final String apiName = "chatbotAPI";
  final String bucketName = "autoethnography-appa497d-dev";

  Future<String?> detectTextFromS3(String filePath) async {
    try {
      final Map<String, dynamic> requestBody = {
        "Image": {
          "S3Object": {
            "Bucket": bucketName,
            "Name": filePath
          }
        }
      };

      final RestOperation request = Amplify.API.post(
        "/extractText",
        apiName: apiName,
        body: HttpPayload.json(requestBody),
      );

      final Stopwatch stopwatch = Stopwatch()..start();
      final AWSHttpResponse response = await request.response;
      stopwatch.stop();
      if (response.statusCode != 200) {
        safePrint("❌ AWS Extractext API Failure: ${response.statusCode}");
        return null;
      }
      safePrint("⏱️ Time taken for text extraction: "
          "${(stopwatch.elapsedMilliseconds / 1000).toStringAsFixed(2)} s");

      final List<int> responseBytes = await response.body.expand((x) => x).toList();

      final Map<String, dynamic> responseMessage = jsonDecode(utf8.decode(responseBytes));
      if (responseMessage.isNotEmpty && responseMessage.containsKey('detected_texts')) {
          safePrint("✅ Text extracted!");
          List<dynamic> detectedTexts = responseMessage['detected_texts'];
          String textString = detectedTexts.join(" ");
          safePrint("$textString");
          return textString;
      }
      return null;
    } catch (e) {
      safePrint("❌ AWS Extractext failure: $e");
      return null;
    }
  }
}
