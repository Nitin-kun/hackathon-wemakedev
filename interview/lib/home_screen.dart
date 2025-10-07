import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:interview/interview_screen.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart' as filepicker;
import 'dart:io';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController roleController = TextEditingController();
  final TextEditingController requirementController = TextEditingController();
  final TextEditingController githubController = TextEditingController();

  File? resumeFile;
  String uploadedResumeUrl = "";
  bool isUploading = false;
  bool isGeneratingToken = false;

  // Update this to your backend URL
  static const String backendUrl = "http://192.168.1.9:7880";

  @override
  void dispose() {
    roleController.dispose();
    requirementController.dispose();
    githubController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Interview Prep-up"),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Prepare for Your Interview",
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Fill in your details to start a live AI-powered mock interview",
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: roleController,
              decoration: InputDecoration(
                labelText: "Role Applying For *",
                hintText: "e.g., Senior Flutter Developer",
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                prefixIcon: const Icon(Icons.work),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: requirementController,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: "Key Requirements *",
                hintText: "e.g., 5+ years Flutter, State Management, REST APIs",
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                prefixIcon: const Icon(Icons.checklist),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: githubController,
              decoration: InputDecoration(
                labelText: "GitHub URL (Optional)",
                hintText: "https://github.com/username",
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                prefixIcon: const Icon(Icons.code),
              ),
            ),
            const SizedBox(height: 24),
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Resume Upload *",
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: isUploading ? null : _pickResume,
                      icon: isUploading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.upload_file),
                      label: Text(
                        isUploading ? "Uploading..." : "Upload Resume",
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                      ),
                    ),
                    if (resumeFile != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12.0),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.green[50],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.green),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.check_circle,
                                color: Colors.green,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  "Selected: ${resumeFile!.path.split('/').last}",
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed:
                  (isGeneratingToken || isUploading) ? null : _startInterview,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: isGeneratingToken
                  ? const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(width: 12),
                        Text("Preparing Interview..."),
                      ],
                    )
                  : const Text(
                      "Start Live Interview",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// Pick resume file from device
  void _pickResume() async {
    try {
      final result = await filepicker.FilePicker.platform.pickFiles(
        type: filepicker.FileType.custom,
        allowedExtensions: ['pdf', 'doc', 'docx'],
      );

      if (result != null && result.files.isNotEmpty) {
        setState(() {
          resumeFile = File(result.files.single.path!);
          isUploading = true;
        });

        // Upload file to backend
        uploadedResumeUrl = await _uploadResumeFile(resumeFile!);

        setState(() {
          isUploading = false;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Resume uploaded successfully!"),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      setState(() {
        isUploading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Failed to upload resume: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Upload the picked resume to the backend and get URL
  Future<String> _uploadResumeFile(File file) async {
    try {
      final request = http.MultipartRequest(
        "POST",
        Uri.parse("$backendUrl/api/uploadResume"),
      );
      request.files.add(await http.MultipartFile.fromPath('resume', file.path));

      final response = await request.send();

      if (response.statusCode == 200) {
        final respStr = await response.stream.bytesToString();
        final data = jsonDecode(respStr);
        return data['resumeUrl'];
      } else {
        log("Failed to upload resume: ${response.statusCode}");
        throw Exception("Upload failed with status: ${response.statusCode}");
      }
    } catch (e) {
      log("Failed to upload resume: $e");
      throw Exception("Failed to upload resume: $e");
    }
  }

  void _startInterview() async {
    // Validate inputs
    if (roleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please enter the role you're applying for"),
        ),
      );
      return;
    }

    if (requirementController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter key requirements")),
      );
      return;
    }

    if (uploadedResumeUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please upload your resume first")),
      );
      return;
    }

    setState(() {
      isGeneratingToken = true;
    });

    try {
      // Fetch LiveKit token from backend
      final tokenData = await fetchLiveKitTokenFromMCP(
        role: roleController.text.trim(),
        requirements: requirementController.text.trim(),
        resumeUrl: uploadedResumeUrl,
        githubUrl: githubController.text.trim(),
      );

      setState(() {
        isGeneratingToken = false;
      });

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => InterviewScreen(
              roomUrl: tokenData['roomUrl']!,
              token: tokenData['token']!,
              role: roleController.text.trim(),
            ),
          ),
        );
      }
    } catch (e) {
      setState(() {
        isGeneratingToken = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Failed to start interview: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<Map<String, String>> fetchLiveKitTokenFromMCP({
    required String role,
    required String requirements,
    required String resumeUrl,
    String? githubUrl,
  }) async {
    const int timeoutSeconds = 30;

    try {
      log("Sending request to backend for LiveKit token...",
          name: "LiveKitAPI");

      final response = await http
          .post(
            Uri.parse("$backendUrl/api/livekit/token"),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({
              "role": role,
              "requirements": requirements,
              "resumeUrl": resumeUrl,
              "githubUrl": githubUrl ?? "",
            }),
          )
          .timeout(const Duration(seconds: timeoutSeconds));

      log("HTTP status code: ${response.statusCode}", name: "LiveKitAPI");
      log("LiveKit API response body: ${response.body}", name: "LiveKitAPI");

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        log("LiveKit token response: ${response.body}");

        // Safely extract token and roomUrl
        final token = data['token']?.toString();
        final roomUrl = (data['roomUrl'] ?? data['room'])?.toString();

        if (token == null || roomUrl == null) {
          throw Exception(
              "Invalid server response, missing token or roomUrl: $data");
        }

        log("Extracted token: $token", name: "LiveKitAPI");
        log("Extracted roomUrl: $roomUrl", name: "LiveKitAPI");

        return {
          "token": token,
          "roomUrl": roomUrl,
        };
      } else {
        throw Exception(
            "Server returned non-200 status: ${response.statusCode}");
      }
    } catch (e, stackTrace) {
      log("Failed to get LiveKit token: $e",
          name: "LiveKitAPI", stackTrace: stackTrace);
      throw Exception("Failed to get LiveKit token: $e");
    }
  }
}
