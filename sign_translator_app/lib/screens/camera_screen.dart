import 'dart:async';
import 'dart:collection';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'package:sign_translator_app/services/api_service.dart';
import 'package:sign_translator_app/utils/tts_service.dart';

class CameraScreen extends StatefulWidget {
  final List<CameraDescription> cameras;

  const CameraScreen({super.key, required this.cameras});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  static const double _confirmationThreshold = 0.72;
  static const int _historySize = 5;
  static const Duration _liveModeInterval = Duration(milliseconds: 900);
  static const Duration _commitCooldown = Duration(milliseconds: 1800);

  CameraController? controller;
  Timer? _timer;
  final Queue<_PredictionSample> _recentPredictions = Queue<_PredictionSample>();

  bool isProcessing = false;
  bool isCameraReady = false;
  bool isLiveMode = false;
  bool autoSpeak = true;

  int selectedCameraIndex = 0;
  String? cameraError;
  String statusText = 'Initializing camera';
  String translationResult = 'Waiting for sign';
  double confidence = 0.0;
  String confirmedPhrase = '';
  String lastCommittedText = '';
  String lastSpokenText = '';
  DateTime? lastCommitTime;

  @override
  void initState() {
    super.initState();
    unawaited(TTSService.init());
    _initializeCamera();
  }

  Future<void> _initializeCamera([int? cameraIndex]) async {
    if (widget.cameras.isEmpty) {
      setState(() {
        cameraError = 'No cameras available on this device.';
        statusText = 'Camera unavailable';
      });
      return;
    }

    final nextIndex = cameraIndex ?? selectedCameraIndex;
    final previousController = controller;

    setState(() {
      isCameraReady = false;
      cameraError = null;
      statusText = 'Starting camera';
      selectedCameraIndex = nextIndex;
    });

    final nextController = CameraController(
      widget.cameras[nextIndex],
      ResolutionPreset.medium,
      enableAudio: false,
    );

    try {
      await previousController?.dispose();
      controller = nextController;
      await nextController.initialize();

      if (!mounted) {
        await nextController.dispose();
        return;
      }

      setState(() {
        isCameraReady = true;
        statusText = isLiveMode ? 'Live translation running' : 'Ready to scan';
      });
    } catch (e) {
      await nextController.dispose();
      if (!mounted) {
        return;
      }
      setState(() {
        cameraError = 'Camera init failed: $e';
        statusText = 'Camera error';
      });
    }
  }

  void _toggleLiveMode(bool value) {
    if (value) {
      _timer?.cancel();
      _timer = Timer.periodic(_liveModeInterval, (_) {
        if (!isProcessing) {
          unawaited(captureAndTranslate());
        }
      });
      setState(() {
        isLiveMode = true;
        statusText = 'Live translation running';
      });
      unawaited(captureAndTranslate());
      return;
    }

    _timer?.cancel();
    setState(() {
      isLiveMode = false;
      statusText = 'Live translation paused';
    });
  }

  Future<void> _switchCamera() async {
    if (widget.cameras.length < 2) {
      return;
    }

    final nextIndex = (selectedCameraIndex + 1) % widget.cameras.length;
    await _initializeCamera(nextIndex);
  }

  void _clearPhrase() {
    setState(() {
      confirmedPhrase = '';
      lastCommittedText = '';
      lastSpokenText = '';
      lastCommitTime = null;
      _recentPredictions.clear();
      translationResult = 'Waiting for sign';
      confidence = 0.0;
      statusText = isLiveMode ? 'Live translation running' : 'Ready to scan';
    });
  }

  Future<void> _speakPhrase() async {
    if (confirmedPhrase.trim().isEmpty) {
      return;
    }
    await TTSService.speak(confirmedPhrase.trim());
  }

  bool _isUsefulPrediction(String text, double predictionConfidence) {
    if (text.isEmpty) {
      return false;
    }

    const ignoredValues = <String>{
      'No hand',
      'Error',
      'Invalid image',
      'Unknown',
      'Connection issue',
    };

    if (ignoredValues.contains(text)) {
      return false;
    }

    return predictionConfidence >= _confirmationThreshold;
  }

  void _recordPrediction(String text, double predictionConfidence) {
    if (!_isUsefulPrediction(text, predictionConfidence)) {
      return; // Don't add bad predictions, but don't clear the queue
    }

    _recentPredictions.add(
      _PredictionSample(text: text, confidence: predictionConfidence),
    );
    while (_recentPredictions.length > _historySize) {
      _recentPredictions.removeFirst();
    }
  }

  String? _getStablePrediction() {
    if (_recentPredictions.length < 3) {
      return null;
    }

    final counts = <String, int>{};
    for (final sample in _recentPredictions) {
      counts.update(sample.text, (value) => value + 1, ifAbsent: () => 1);
    }

    final bestEntry = counts.entries.reduce(
      (current, next) => current.value >= next.value ? current : next,
    );

    return bestEntry.value >= 3 ? bestEntry.key : null;
  }

  bool _shouldCommit(String stablePrediction) {
    if (stablePrediction == lastCommittedText) {
      return false;
    }

    if (lastCommitTime == null) {
      return true;
    }

    return DateTime.now().difference(lastCommitTime!) >= _commitCooldown;
  }

  void _commitPrediction(String stablePrediction) {
    if (!_shouldCommit(stablePrediction)) {
      return;
    }

    final updatedPhrase = confirmedPhrase.isEmpty
        ? stablePrediction
        : '$confirmedPhrase $stablePrediction';

    setState(() {
      confirmedPhrase = updatedPhrase;
      lastCommittedText = stablePrediction;
      lastCommitTime = DateTime.now();
      statusText = 'Confirmed: $stablePrediction';
    });

    if (autoSpeak && stablePrediction != lastSpokenText) {
      lastSpokenText = stablePrediction;
      unawaited(TTSService.speak(stablePrediction));
    }
  }

  Future<void> captureAndTranslate() async {
    final currentController = controller;
    if (currentController == null ||
        !currentController.value.isInitialized ||
        isProcessing) {
      return;
    }

    setState(() {
      isProcessing = true;
      statusText = isLiveMode ? 'Scanning sign' : 'Capturing frame';
    });

    try {
      final image = await currentController.takePicture();
      final result = await ApiService.translateSignLanguage(image.path);
      final newText = (result['text'] as String? ?? 'Unknown').trim();
      final newConfidence = (result['confidence'] as num? ?? 0.0).toDouble();
      final errorDetails = result['error'] as Object?;

      if (!mounted) {
        return;
      }

      _recordPrediction(newText, newConfidence);
      final stablePrediction = _getStablePrediction();

      setState(() {
        translationResult = newText;
        confidence = newConfidence;

        if (errorDetails != null && errorDetails.toString().isNotEmpty) {
          statusText = 'Backend warning: ${errorDetails.toString()}';
        } else if (!_isUsefulPrediction(newText, newConfidence)) {
          statusText = newText == 'No hand'
              ? 'Show one clear hand to the camera'
              : 'Low confidence, hold the pose steady';
        } else if (stablePrediction != null) {
          statusText = 'Stable sign detected: $stablePrediction';
        } else {
          statusText = 'Detecting sign';
        }
      });

      if (stablePrediction != null) {
        _commitPrediction(stablePrediction);
      }
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        translationResult = 'Capture failed';
        confidence = 0.0;
        statusText = 'Capture failed: $e';
      });
    } finally {
      if (mounted) {
        setState(() => isProcessing = false);
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sign Language Translator'),
        actions: [
          if (widget.cameras.length > 1)
            IconButton(
              onPressed: () => unawaited(_switchCamera()),
              icon: const Icon(Icons.cameraswitch_outlined),
              tooltip: 'Switch camera',
            ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (cameraError != null) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
            child: _InfoCard(
            title: 'Camera unavailable',
            subtitle: cameraError!,
            child: widget.cameras.isNotEmpty ? FilledButton(
              onPressed: () => unawaited(_initializeCamera()),
              child: const Text('Retry'),
            ) : const SizedBox.shrink(),
          ),
        ),
      );
    }

    if (controller == null || !isCameraReady) {
      return const Center(child: CircularProgressIndicator());
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 920;
        final preview = _buildPreviewCard();
        final controls = _buildControlPanel();

        if (isWide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: preview),
              const SizedBox(width: 16),
              Expanded(flex: 2, child: controls),
            ],
          );
        }

        return ListView(
          children: [
            preview,
            const SizedBox(height: 16),
            controls,
          ],
        );
      },
    );
  }

  Widget _buildPreviewCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: AspectRatio(
                aspectRatio: controller!.value.aspectRatio == 0
                    ? 4 / 3
                    : controller!.value.aspectRatio,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CameraPreview(controller!),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.5),
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    Positioned(
                      top: 16,
                      left: 16,
                      child: _LiveBadge(
                        isLiveMode: isLiveMode,
                        isProcessing: isProcessing,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              statusText,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'API: ${ApiService.baseUrl}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.black54,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlPanel() {
    return Column(
      children: [
        _InfoCard(
          title: 'Current detection',
          subtitle: translationResult,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${(confidence * 100).toStringAsFixed(1)}% confidence',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  Text(
                    _confidenceLabel(confidence),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: _confidenceColor(confidence),
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: confidence.clamp(0.0, 1.0),
                  minHeight: 12,
                  backgroundColor: const Color(0xFFD7E1E3),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    _confidenceColor(confidence),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _InfoCard(
          title: 'Confirmed phrase',
          subtitle: confirmedPhrase.isEmpty ? 'No confirmed words yet' : confirmedPhrase,
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed: isProcessing
                    ? null
                    : () => unawaited(captureAndTranslate()),
                icon: isProcessing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.camera_alt_outlined),
                label: Text(isProcessing ? 'Working' : 'Scan now'),
              ),
              OutlinedButton.icon(
                onPressed: confirmedPhrase.isEmpty
                    ? null
                    : () => unawaited(_speakPhrase()),
                icon: const Icon(Icons.volume_up_outlined),
                label: const Text('Speak phrase'),
              ),
              TextButton.icon(
                onPressed: _clearPhrase,
                icon: const Icon(Icons.clear_all_outlined),
                label: const Text('Clear'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _InfoCard(
          title: 'Live controls',
          subtitle: 'Use live mode for continuous scanning during your presentation.',
          child: Column(
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Live translation'),
                subtitle: Text(
                  isLiveMode
                      ? 'Frames are scanned automatically.'
                      : 'Manual scan mode is active.',
                ),
                value: isLiveMode,
                onChanged: _toggleLiveMode,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Auto speak confirmed words'),
                subtitle: const Text(
                  'Turn this off if you only want text output during the demo.',
                ),
                value: autoSpeak,
                onChanged: (value) => setState(() => autoSpeak = value),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Color _confidenceColor(double value) {
    if (value >= 0.75) {
      return const Color(0xFF15803D);
    }
    if (value >= 0.45) {
      return const Color(0xFFD97706);
    }
    return const Color(0xFFB91C1C);
  }

  String _confidenceLabel(double value) {
    if (value >= 0.75) {
      return 'High';
    }
    if (value >= 0.45) {
      return 'Medium';
    }
    return 'Low';
  }
}

class _PredictionSample {
  final String text;
  final double confidence;

  const _PredictionSample({
    required this.text,
    required this.confidence,
  });
}

class _LiveBadge extends StatelessWidget {
  final bool isLiveMode;
  final bool isProcessing;

  const _LiveBadge({
    required this.isLiveMode,
    required this.isProcessing,
  });

  @override
  Widget build(BuildContext context) {
    final Color backgroundColor;
    final String label;

    if (isProcessing) {
      backgroundColor = const Color(0xFFD97706);
      label = 'SCANNING';
    } else if (isLiveMode) {
      backgroundColor = const Color(0xFF15803D);
      label = 'LIVE';
    } else {
      backgroundColor = const Color(0xFF334155);
      label = 'MANUAL';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  const _InfoCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 20),
            child,
          ],
        ),
      ),
    );
  }
}
