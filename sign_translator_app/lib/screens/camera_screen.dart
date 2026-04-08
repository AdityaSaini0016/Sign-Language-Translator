import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:sign_translator_app/services/api_service.dart';
import 'dart:async';
import 'package:sign_translator_app/utils/tts_service.dart';

class CameraScreen extends StatefulWidget {
  final List<CameraDescription> cameras;

  const CameraScreen({super.key, required this.cameras});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? controller;
  String translationResult = '';
  double confidence = 0.0;

  bool isProcessing = false;
  bool isCameraReady = false;
  String? cameraError;

  Timer? _timer;
  bool isLiveMode = false;

  String lastSpokenText = ""; // 🔥 Prevent repeated speech

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    TTSService.init(); // Initialize TTS
  }

  Future<void> _initializeCamera() async {
    if (widget.cameras.isEmpty) {
      setState(() => cameraError = 'No cameras available');
      return;
    }

    controller = CameraController(
      widget.cameras[0],
      ResolutionPreset.medium,
    );

    try {
      await controller!.initialize();
      if (mounted) {
        setState(() {
          isCameraReady = true;
          cameraError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => cameraError = 'Camera init failed: $e');
      }
    }
  }

  void _toggleLiveMode() {
    setState(() {
      isLiveMode = !isLiveMode;

      if (isLiveMode) {
        _timer = Timer.periodic(const Duration(milliseconds: 700), (timer) {
          if (!isProcessing) captureAndTranslate();
        });
      } else {
        _timer?.cancel();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    controller?.dispose();
    super.dispose();
  }

  Future<void> captureAndTranslate() async {
    if (controller == null || !controller!.value.isInitialized || isProcessing) {
      return;
    }

    setState(() => isProcessing = true);

    try {
      final XFile image = await controller!.takePicture();
      final result = await ApiService.translateSignLanguage(image.path);

      final newText = result['text'];
      final newConfidence = result['confidence'];

      if (newText != translationResult) {
        setState(() {
          translationResult = newText;
          confidence = newConfidence;
        });

        // 🔥 Smart TTS (no spam + confidence filter)
        if (newText != "No hand" &&
            newText != "Error" &&
            newConfidence > 0.6 &&
            newText != lastSpokenText) {
          
          lastSpokenText = newText;
          TTSService.speak(newText);
        }
      }
    } catch (e) {
      setState(() => translationResult = 'Error: $e');
    } finally {
      setState(() => isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sign Language Translator')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (cameraError != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error, size: 64, color: Colors.red),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                cameraError!,
                style: const TextStyle(color: Colors.red),
              ),
            ),
            ElevatedButton(
              onPressed: _initializeCamera,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (controller == null || !isCameraReady) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        Expanded(child: CameraPreview(controller!)),

        // 🔥 Status Indicator
        Text(
          isProcessing ? "Processing..." : "Ready",
          style: TextStyle(
            color: isProcessing ? Colors.orange : Colors.green,
          ),
        ),

        if (translationResult.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Container(
              padding: const EdgeInsets.all(20),
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Text(
                    translationResult,
                    style: const TextStyle(
                      fontSize: 28,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "${(confidence * 100).toStringAsFixed(1)}%",
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.greenAccent,
                    ),
                  ),
                ],
              ),
            ),
          ),

        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text("Live Mode"),
                  Switch(
                    value: isLiveMode,
                    onChanged: (_) => _toggleLiveMode(),
                  ),
                ],
              ),
              ElevatedButton(
                onPressed: (isProcessing || isLiveMode)
                    ? null
                    : captureAndTranslate,
                child: isProcessing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Manual Capture'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}