import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:async';

class InterviewScreen extends StatefulWidget {
  final String roomUrl;
  final String token;
  final String role;

  const InterviewScreen({
    super.key,
    required this.roomUrl,
    required this.token,
    required this.role,
  });

  @override
  State<InterviewScreen> createState() => _InterviewScreenState();
}

class _InterviewScreenState extends State<InterviewScreen> {
  // Room
  Room? room;
  Participant? agentParticipant;

  // TTS and STT
  FlutterTts? flutterTts;
  late stt.SpeechToText speech;
  bool isSpeaking = false;
  bool isListening = false;
  String recognizedText = '';

  // UI State
  String currentQuestion = "";
  String currentFeedback = "";
  String finalFeedback = "";
  bool isConnecting = true;
  bool isMicEnabled = true;
  bool isCameraEnabled = true;
  bool isInterviewEnded = false;
  bool isProcessing = false;

  // Conversation
  List<Map<String, dynamic>> messages = [];
  int interactionCount = 0;

  EventsListener<RoomEvent>? roomListener;
  Timer? _silenceTimer;

  static final String backendUrl = dotenv.env['BACKEND_URL']!;

  @override
  void initState() {
    super.initState();
    _initializeTTS();
    _initializeSTT();
    _connectToRoom();
  }

  Future<void> _initializeTTS() async {
    flutterTts = FlutterTts();
    await flutterTts!.setLanguage("en-US");
    await flutterTts!.setSpeechRate(0.5);
    await flutterTts!.setVolume(1.0);
    await flutterTts!.setPitch(1.0);

    flutterTts!.setCompletionHandler(() {
      if (mounted) {
        setState(() => isSpeaking = false);
        // Auto-start listening after AI finishes speaking
        if (!isInterviewEnded && isMicEnabled) {
          _startListening();
        }
      }
    });

    flutterTts!.setErrorHandler((msg) {
      debugPrint("TTS Error: $msg");
      if (mounted) setState(() => isSpeaking = false);
    });
  }

  Future<void> _initializeSTT() async {
    speech = stt.SpeechToText();
    bool available = await speech.initialize(
      onError: (error) => debugPrint('STT Error: $error'),
      onStatus: (status) => debugPrint('STT Status: $status'),
    );

    if (!available) {
      debugPrint('Speech recognition not available');
    }
  }

  Future<void> _speakText(String text) async {
    if (flutterTts == null || text.isEmpty) return;

    try {
      setState(() => isSpeaking = true);
      await flutterTts!.speak(text);
    } catch (e) {
      debugPrint("Error speaking: $e");
      if (mounted) setState(() => isSpeaking = false);
    }
  }

  Future<void> _stopSpeaking() async {
    if (flutterTts != null) {
      await flutterTts!.stop();
      if (mounted) setState(() => isSpeaking = false);
    }
  }

  Future<void> _startListening() async {
    if (isListening || isSpeaking || isProcessing) return;

    if (!await speech.initialize()) {
      _showErrorSnackBar("Speech recognition not available");
      return;
    }

    setState(() {
      isListening = true;
      recognizedText = '';
    });

    speech.listen(
      onResult: (result) {
        setState(() {
          recognizedText = result.recognizedWords;
        });

        // Reset silence timer
        _silenceTimer?.cancel();
        _silenceTimer = Timer(const Duration(seconds: 2), () {
          if (isListening && recognizedText.isNotEmpty) {
            _stopListening();
            _submitResponse();
          }
        });
      },
      listenFor: const Duration(seconds: 60),
      pauseFor: const Duration(seconds: 2),
      partialResults: true,
      cancelOnError: true,
    );
  }

  Future<void> _stopListening() async {
    _silenceTimer?.cancel();
    if (isListening) {
      await speech.stop();
      if (mounted) setState(() => isListening = false);
    }
  }

  Future<void> _submitResponse() async {
    if (recognizedText.trim().isEmpty || isProcessing) return;

    final response = recognizedText.trim();
    setState(() {
      isProcessing = true;
      messages.add({
        'type': 'user',
        'content': response,
        'timestamp': DateTime.now().toIso8601String(),
      });
      recognizedText = '';
    });

    try {
      // Send response to backend
      final result = await http
          .post(
            Uri.parse("$backendUrl/api/agent/response"),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({
              "roomName": room?.name,
              "response": response,
            }),
          )
          .timeout(const Duration(seconds: 20));

      if (result.statusCode == 200) {
        final data = jsonDecode(result.body);
        final feedback = data['feedback'] ?? '';
        final nextQuestion = data['nextQuestion'] ?? '';
        final quality = data['quality'] ?? 'unknown';

        setState(() {
          interactionCount++;

          if (feedback.isNotEmpty) {
            currentFeedback = feedback;
            messages.add({
              'type': 'feedback',
              'content': feedback,
              'timestamp': DateTime.now().toIso8601String(),
            });
          }

          if (nextQuestion.isNotEmpty) {
            currentQuestion = nextQuestion;
            messages.add({
              'type': 'question',
              'content': nextQuestion,
              'timestamp': DateTime.now().toIso8601String(),
            });
          }
        });

        // Speak feedback and question
        if (feedback.isNotEmpty) {
          await _speakText(feedback);
          await Future.delayed(const Duration(milliseconds: 500));
        }
        if (nextQuestion.isNotEmpty) {
          await _speakText(nextQuestion);
        }
      }
    } catch (e) {
      debugPrint("Error submitting response: $e");
      _showErrorSnackBar("Failed to process response");
    } finally {
      if (mounted) setState(() => isProcessing = false);
    }
  }

  Future<void> _connectToRoom() async {
    try {
      room = Room(
        roomOptions: const RoomOptions(
          adaptiveStream: true,
          dynacast: true,
          defaultAudioCaptureOptions: AudioCaptureOptions(
            echoCancellation: true,
            noiseSuppression: true,
            autoGainControl: true,
          ),
        ),
      );

      _setupRoomListeners();

      await room!.connect(
        widget.roomUrl,
        widget.token,
        connectOptions: const ConnectOptions(autoSubscribe: true),
      );

      await room!.localParticipant?.setCameraEnabled(true);
      await room!.localParticipant?.setMicrophoneEnabled(true);

      setState(() => isConnecting = false);

      await _notifyUserReady();

      // Get first question
      await Future.delayed(const Duration(seconds: 2));
      await _fetchFirstQuestion();
    } catch (e) {
      debugPrint("Error connecting: $e");
      if (mounted) {
        setState(() => isConnecting = false);
        _showErrorSnackBar("Failed to connect: $e");
      }
    }
  }

  void _setupRoomListeners() {
    roomListener = room!.createListener();

    roomListener!.on<DataReceivedEvent>((event) {
      try {
        final message = utf8.decode(event.data);
        final messageData = jsonDecode(message);
        _handleAgentMessage(messageData);
      } catch (e) {
        debugPrint("Error parsing message: $e");
      }
    });

    roomListener!.on<ParticipantConnectedEvent>((event) {
      if (event.participant.identity.contains("agent")) {
        setState(() => agentParticipant = event.participant);
      }
    });

    roomListener!.on<ParticipantDisconnectedEvent>((event) {
      if (event.participant == agentParticipant) {
        setState(() => agentParticipant = null);
      }
    });
  }

  void _handleAgentMessage(Map<String, dynamic> data) {
    final type = data['type'] ?? '';
    final content = data['content'] ?? '';

    if (content.isEmpty) return;

    setState(() {
      switch (type) {
        case 'question':
          currentQuestion = content;
          messages.add({
            'type': 'question',
            'content': content,
            'timestamp': DateTime.now().toIso8601String(),
          });
          _speakText(content);
          break;

        case 'feedback':
          currentFeedback = content;
          messages.add({
            'type': 'feedback',
            'content': content,
            'timestamp': DateTime.now().toIso8601String(),
          });
          _speakText(content);
          break;

        case 'final':
          finalFeedback = content;
          _showFeedbackDialog();
          break;
      }
    });
  }

  Future<void> _notifyUserReady() async {
    try {
      await http
          .post(
            Uri.parse("$backendUrl/api/interview/ready"),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({
              "roomName": room!.name,
              "participantIdentity": room!.localParticipant?.identity,
            }),
          )
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint("Failed to notify backend: $e");
    }
  }

  Future<void> _fetchFirstQuestion() async {
    try {
      final response = await http
          .post(
            Uri.parse("$backendUrl/api/agent/question"),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({"roomName": room?.name}),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final question = data['question'] ?? '';

        if (question.isNotEmpty) {
          setState(() {
            currentQuestion = question;
            messages.add({
              'type': 'question',
              'content': question,
              'timestamp': DateTime.now().toIso8601String(),
            });
          });

          await _speakText(question);
        }
      }
    } catch (e) {
      debugPrint("Error fetching first question: $e");
    }
  }

  void _toggleMicrophone() async {
    if (room?.localParticipant != null) {
      await room!.localParticipant!.setMicrophoneEnabled(!isMicEnabled);
      setState(() => isMicEnabled = !isMicEnabled);

      if (!isMicEnabled && isListening) {
        await _stopListening();
      }
    }
  }

  void _toggleCamera() async {
    if (room?.localParticipant != null) {
      await room!.localParticipant!.setCameraEnabled(!isCameraEnabled);
      setState(() => isCameraEnabled = !isCameraEnabled);
    }
  }

  void _endInterview() async {
    if (isInterviewEnded) return;

    final shouldEnd = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("End Interview?"),
        content: const Text("You'll receive comprehensive feedback."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("End Interview"),
          ),
        ],
      ),
    );

    if (shouldEnd != true) return;

    await _stopSpeaking();
    await _stopListening();

    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text("Generating feedback..."),
            ],
          ),
        ),
      );
    }

    try {
      final feedback = await _getFinalFeedback();
      setState(() {
        finalFeedback = feedback;
        isInterviewEnded = true;
      });

      await room?.disconnect();

      if (mounted) {
        Navigator.pop(context);
        _showFeedbackDialog();
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        _showErrorSnackBar("Failed to get feedback: $e");
      }
    }
  }

  Future<String> _getFinalFeedback() async {
    try {
      final response = await http
          .post(
            Uri.parse("$backendUrl/api/agent/final-feedback"),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({
              "roomName": room?.name,
              "participantIdentity": room?.localParticipant?.identity,
            }),
          )
          .timeout(const Duration(seconds: 60));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['feedback'] ?? "No feedback available";
      }
      throw Exception("Server error");
    } catch (e) {
      throw Exception("Failed to get feedback: $e");
    }
  }

  void _showFeedbackDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 28),
            SizedBox(width: 8),
            Text("Interview Complete!"),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Role: ${widget.role}",
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Interactions: $interactionCount",
                      style: TextStyle(color: Colors.grey[700]),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                "AI Feedback:",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Text(
                  finalFeedback,
                  style: const TextStyle(fontSize: 14, height: 1.5),
                ),
              ),
            ],
          ),
        ),
        actions: [
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            icon: const Icon(Icons.home),
            label: const Text("Back to Home"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoWidget() {
    final localParticipant = room?.localParticipant;
    if (localParticipant == null) {
      return const Center(
        child: Text("No video", style: TextStyle(color: Colors.white)),
      );
    }

    final videoTrack = localParticipant.videoTrackPublications
        .where((track) => track.track != null)
        .map((track) => track.track as VideoTrack)
        .firstOrNull;

    if (videoTrack == null || !isCameraEnabled) {
      return Center(
        child: Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            color: Colors.grey[800],
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.person, size: 60, color: Colors.white),
        ),
      );
    }

    return VideoTrackRenderer(videoTrack, fit: VideoViewFit.cover);
  }

  void _showErrorSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (!isInterviewEnded) {
          final shouldExit = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text("Exit Interview?"),
              content: const Text("Your progress will be lost."),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  child: const Text("Exit"),
                ),
              ],
            ),
          );
          return shouldExit ?? false;
        }
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text("Interview - ${widget.role}"),
          backgroundColor: Colors.indigo,
          foregroundColor: Colors.white,
          automaticallyImplyLeading: false,
          actions: [
            if (!isConnecting && isSpeaking)
              IconButton(
                icon: const Icon(Icons.volume_up),
                onPressed: _stopSpeaking,
                tooltip: "Stop AI Voice",
              ),
          ],
        ),
        body: isConnecting
            ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text("Connecting...", style: TextStyle(fontSize: 16)),
                  ],
                ),
              )
            : Column(
                children: [
                  // Video Feed
                  Expanded(
                    flex: 3,
                    child: Container(
                      color: Colors.black,
                      child: Stack(
                        children: [
                          _buildVideoWidget(),

                          // AI Status
                          if (agentParticipant != null)
                            Positioned(
                              top: 16,
                              left: 16,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      isSpeaking ? Colors.orange : Colors.green,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.circle,
                                        color: Colors.white, size: 8),
                                    const SizedBox(width: 6),
                                    Text(
                                      isSpeaking ? "AI Speaking" : "AI Ready",
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                          // Listening Indicator
                          if (isListening)
                            Positioned(
                              top: 16,
                              right: 16,
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.red.withOpacity(0.9),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.mic,
                                        color: Colors.white, size: 20),
                                    SizedBox(width: 8),
                                    Text(
                                      "Listening...",
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                          // Processing Indicator
                          if (isProcessing)
                            Positioned(
                              bottom: 16,
                              left: 0,
                              right: 0,
                              child: Center(
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.withOpacity(0.9),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                  Colors.white),
                                        ),
                                      ),
                                      SizedBox(width: 8),
                                      Text(
                                        "Processing your response...",
                                        style: TextStyle(color: Colors.white),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),

                  // Current Question
                  if (currentQuestion.isNotEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      color: Colors.indigo[50],
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.psychology,
                                  color: Colors.indigo[700], size: 20),
                              const SizedBox(width: 8),
                              Text(
                                "Current Question:",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: Colors.indigo[700],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            currentQuestion,
                            style: const TextStyle(fontSize: 16, height: 1.4),
                          ),
                        ],
                      ),
                    ),

                  // Recognized Text (Live Transcription)
                  if (recognizedText.isNotEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      color: Colors.amber[50],
                      child: Row(
                        children: [
                          const Icon(Icons.hearing,
                              color: Colors.amber, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              recognizedText,
                              style: const TextStyle(
                                fontStyle: FontStyle.italic,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Latest Feedback
                  if (currentFeedback.isNotEmpty && !isListening)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      color: Colors.green[50],
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.feedback,
                              color: Colors.green[700], size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              currentFeedback,
                              style: TextStyle(
                                color: Colors.green[900],
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Controls
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 4,
                          offset: const Offset(0, -2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        // Microphone Toggle
                        _buildControlButton(
                          icon: isMicEnabled ? Icons.mic : Icons.mic_off,
                          label: isMicEnabled ? "Mute" : "Unmute",
                          color: isMicEnabled ? Colors.blue : Colors.red,
                          onPressed: _toggleMicrophone,
                        ),

                        // Camera Toggle
                        _buildControlButton(
                          icon: isCameraEnabled
                              ? Icons.videocam
                              : Icons.videocam_off,
                          label: "Camera",
                          color: isCameraEnabled ? Colors.blue : Colors.red,
                          onPressed: _toggleCamera,
                        ),

                        // Manual Listen Button
                        if (!isListening && !isSpeaking && !isProcessing)
                          _buildControlButton(
                            icon: Icons.record_voice_over,
                            label: "Speak",
                            color: Colors.green,
                            onPressed: _startListening,
                          ),

                        // Stop Listening
                        if (isListening)
                          _buildControlButton(
                            icon: Icons.stop,
                            label: "Stop",
                            color: Colors.orange,
                            onPressed: () {
                              _stopListening();
                              if (recognizedText.isNotEmpty) {
                                _submitResponse();
                              }
                            },
                          ),

                        // End Interview
                        ElevatedButton.icon(
                          onPressed: _endInterview,
                          icon: const Icon(Icons.call_end, size: 20),
                          label: const Text("End"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: onPressed,
          icon: Icon(icon),
          iconSize: 32,
          color: color,
        ),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: Colors.grey[600]),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _silenceTimer?.cancel();
    _stopSpeaking();
    _stopListening();
    flutterTts?.stop();
    speech.stop();
    roomListener?.dispose();
    room?.disconnect();
    room?.dispose();
    super.dispose();
  }
}
