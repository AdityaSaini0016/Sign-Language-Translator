import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:sign_translator_app/services/api_service.dart';
import 'dart:async'; // Required for Timer

class CameraScreen extends StatefulWidget {
  final List<CameraDescription> cameras;

  const CameraScreen({super.key, required this.cameras});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? controller;
  String translationResult = '';
  bool isProcessing = false;
  bool isCameraReady = false;
  String? cameraError;
  
  // Added for Live Mode
  Timer? _timer;
  bool isLiveMode = false;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
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

  // Toggle Live Mode
  void _toggleLiveMode() {
    setState(() {
      isLiveMode = !isLiveMode;
      if (isLiveMode) {
        _timer = Timer.periodic(const Duration(seconds: 2), (timer) {
          if (!isProcessing) captureAndTranslate();
        });
      } else {
        _timer?.cancel();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel(); // Stop timer
    controller?.dispose();
    super.dispose();
  }

  Future<void> captureAndTranslate() async {
    if (controller == null || !controller!.value.isInitialized || isProcessing) return;

    setState(() => isProcessing = true);

    try {
      final XFile image = await controller!.takePicture();
      final result = await ApiService.translateSignLanguage(image.path);
      
      // Only update if text has changed to prevent UI flicker
      if (result != translationResult) {
        setState(() => translationResult = result);
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
              child: Text(cameraError!, style: const TextStyle(color: Colors.red)),
            ),
            ElevatedButton(onPressed: _initializeCamera, child: const Text('Retry')),
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
        if (translationResult.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              translationResult,
              style: Theme.of(context).textTheme.headlineMedium,
              textAlign: TextAlign.center,
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
                  Switch(value: isLiveMode, onChanged: (value) => _toggleLiveMode()),
                ],
              ),
              ElevatedButton(
                onPressed: (isProcessing || isLiveMode) ? null : captureAndTranslate,
                child: isProcessing
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Manual Capture'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}