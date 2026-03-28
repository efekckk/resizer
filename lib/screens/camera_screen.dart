import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../models/warp_config.dart';
import '../painters/warp_painter.dart';
import '../services/warp_engine.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  // Camera
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  int _cameraIndex = 0;

  // Pose detection
  final PoseDetector _poseDetector = PoseDetector(
    options: PoseDetectorOptions(model: PoseDetectionModel.base),
  );

  // Warp state
  double _kg = 20.0;
  bool _isProcessing = false;
  ui.Image? _warpedFrame;
  ui.Vertices? _warpedVertices;
  Timer? _captureTimer;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        setState(() => _errorMessage = 'Kamera bulunamadi');
        return;
      }

      // Prefer front camera
      _cameraIndex = _cameras.indexWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
      );
      if (_cameraIndex < 0) _cameraIndex = 0;

      await _startCamera();
    } catch (e) {
      setState(() => _errorMessage = 'Kamera baslatilamadi: $e');
    }
  }

  Future<void> _startCamera() async {
    _captureTimer?.cancel();
    await _controller?.dispose();

    final camera = _cameras[_cameraIndex];
    _controller = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: false,
    );

    await _controller!.initialize();
    if (!mounted) return;
    setState(() => _errorMessage = null);

    // Start periodic capture loop.
    _captureTimer = Timer.periodic(
      const Duration(milliseconds: 800),
      (_) => _captureAndProcess(),
    );
  }

  // ── Capture → Detect → Warp pipeline ──────────────────────────────

  Future<void> _captureAndProcess() async {
    if (_isProcessing) return;
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (_kg < 1) {
      // No warp needed at 0 kg – just show preview.
      if (_warpedFrame != null) {
        _warpedFrame?.dispose();
        setState(() {
          _warpedFrame = null;
          _warpedVertices = null;
        });
      }
      return;
    }

    _isProcessing = true;

    try {
      // 1. Capture a still frame (properly oriented JPEG).
      final xFile = await _controller!.takePicture();
      final filePath = xFile.path;

      // 2. Decode JPEG into a dart:ui Image.
      final bytes = await File(filePath).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frameInfo = await codec.getNextFrame();
      final image = frameInfo.image;

      // 3. Run pose detection (offline ML Kit).
      final inputImage = InputImage.fromFilePath(filePath);
      final poses = await _poseDetector.processImage(inputImage);

      // 4. Build warp mesh.
      final config = WarpConfig(kg: _kg);
      ui.Vertices vertices;

      if (poses.isNotEmpty) {
        final landmarks = poses.first.landmarks.values.toList();
        vertices = WarpEngine.createWarpedMesh(
          imageWidth: image.width.toDouble(),
          imageHeight: image.height.toDouble(),
          landmarks: landmarks,
          config: config,
        );
      } else {
        vertices = WarpEngine.createIdentityMesh(
          imageWidth: image.width.toDouble(),
          imageHeight: image.height.toDouble(),
        );
      }

      // 5. Update UI.
      final oldFrame = _warpedFrame;
      if (mounted) {
        setState(() {
          _warpedFrame = image;
          _warpedVertices = vertices;
        });
      }
      oldFrame?.dispose();

      // Clean up temp file.
      try {
        await File(filePath).delete();
      } catch (_) {}
    } catch (e) {
      debugPrint('Capture error: $e');
    } finally {
      _isProcessing = false;
    }
  }

  // ── Camera helpers ─────────────────────────────────────────────────

  void _toggleCamera() {
    if (_cameras.length < 2) return;
    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    _warpedFrame?.dispose();
    _warpedFrame = null;
    _warpedVertices = null;
    _startCamera();
  }

  bool get _isFrontCamera =>
      _cameras.isNotEmpty &&
      _cameras[_cameraIndex].lensDirection == CameraLensDirection.front;

  // ── Lifecycle ──────────────────────────────────────────────────────

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      _captureTimer?.cancel();
      _controller?.dispose();
      _controller = null;
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _captureTimer?.cancel();
    _controller?.dispose();
    _poseDetector.close();
    _warpedFrame?.dispose();
    super.dispose();
  }

  // ── UI ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: _buildCameraView()),
            _buildControls(),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraView() {
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _errorMessage!,
            style: const TextStyle(color: Colors.red, fontSize: 16),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Live camera preview (visible when no warped frame).
          FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: controller.value.previewSize?.height ?? 1,
              height: controller.value.previewSize?.width ?? 1,
              child: CameraPreview(controller),
            ),
          ),
          // Warped overlay.
          if (_warpedFrame != null && _warpedVertices != null)
            Positioned.fill(
              child: CustomPaint(
                painter: WarpPainter(
                  image: _warpedFrame!,
                  vertices: _warpedVertices!,
                  mirrorHorizontally: _isFrontCamera,
                ),
              ),
            ),
          // Processing indicator.
          if (_isProcessing && _warpedFrame == null)
            const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }

  Widget _buildControls() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xDD000000),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Preset buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _presetButton(10),
              _presetButton(20),
              _presetButton(30),
              _presetButton(50),
            ],
          ),
          const SizedBox(height: 8),
          // Slider
          Row(
            children: [
              const Text('0',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
              Expanded(
                child: Slider(
                  value: _kg,
                  min: 0,
                  max: 60,
                  divisions: 60,
                  label: '+${_kg.round()} kg',
                  onChanged: (v) => setState(() => _kg = v),
                ),
              ),
              const Text('60',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
            ],
          ),
          Text(
            '+${_kg.round()} kg',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          // Camera flip
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_cameras.length > 1)
                IconButton(
                  onPressed: _toggleCamera,
                  icon: const Icon(Icons.flip_camera_ios,
                      color: Colors.white, size: 32),
                  tooltip: 'Kamera degistir',
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _presetButton(int kg) {
    final selected = _kg.round() == kg;
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: selected ? Colors.blue : Colors.grey[850],
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      onPressed: () => setState(() => _kg = kg.toDouble()),
      child: Text('+$kg kg', style: const TextStyle(fontSize: 14)),
    );
  }
}
