import 'dart:convert';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

/// Guided camera capture screen for AI face verification.
/// Shows an oval mask to guide framing, captures front-facing selfie,
/// resizes/compresses to efficient JPEG, and returns base64 string.
class CameraFaceCaptureScreen extends StatefulWidget {
  final String sessionLabel;
  const CameraFaceCaptureScreen({super.key, required this.sessionLabel});

  @override
  State<CameraFaceCaptureScreen> createState() => _CameraFaceCaptureScreenState();
}

class _CameraFaceCaptureScreenState extends State<CameraFaceCaptureScreen> {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _initializing = true;
  bool _capturing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _setupCamera();
  }

  Future<void> _setupCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        setState(() {
          _error = 'No camera found on this device.';
          _initializing = false;
        });
        return;
      }

      // Prefer front camera for selfie
      final front = _cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => _cameras.first,
      );

      _controller = CameraController(
        front,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await _controller!.initialize();
      if (!mounted) return;
      setState(() => _initializing = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Camera initialization failed: $e';
        _initializing = false;
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _captureSelfie() async {
    if (_controller == null || !_controller!.value.isInitialized || _capturing) return;

    setState(() => _capturing = true);
    try {
      final xfile = await _controller!.takePicture();
      final bytes = await File(xfile.path).readAsBytes();

      // Client-side compression & resize:
      // Resizing to max 640 width saves campus bandwidth (resulting size ~60-120KB)
      final rawImage = img.decodeImage(bytes);
      String base64Image;

      if (rawImage != null) {
        final resized = img.copyResize(rawImage, width: 640);
        final compressedJpg = img.encodeJpg(resized, quality: 80);
        base64Image = base64Encode(compressedJpg);
      } else {
        base64Image = base64Encode(bytes);
      }

      // Clean up temp file
      try {
        await File(xfile.path).delete();
      } catch (_) {}

      if (!mounted) return;
      Navigator.pop(context, base64Image);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to capture face: $e'), backgroundColor: Colors.red),
      );
      setState(() => _capturing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_initializing) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(title: const Text('Face Verification'), backgroundColor: Colors.black, foregroundColor: Colors.white),
        body: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 16),
              Text('Opening Camera...', style: TextStyle(color: Colors.white70)),
            ],
          ),
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Face Verification')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.videocam_off, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                Text(_error!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
                const SizedBox(height: 24),
                FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Go Back')),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Live Camera Preview
          Center(
            child: CameraPreview(_controller!),
          ),

          // 2. Oval Face Mask Guide
          IgnorePointer(
            child: CustomPaint(
              size: Size.infinite,
              painter: FaceGuideOverlayPainter(),
            ),
          ),

          // 3. Top Header with Instructions
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Marking ${widget.sessionLabel} Attendance',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Fit your face inside the oval and look at camera',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 4. Close Button Top Left
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: CircleAvatar(
                  backgroundColor: Colors.black45,
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
              ),
            ),
          ),

          // 5. Bottom Capture Controls
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_capturing)
                      const Column(
                        children: [
                          CircularProgressIndicator(color: Colors.white),
                          SizedBox(height: 12),
                          Text('Processing Face...', style: TextStyle(color: Colors.white)),
                        ],
                      )
                    else
                      GestureDetector(
                        onTap: _captureSelfie,
                        child: Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 4),
                            color: Colors.white24,
                          ),
                          child: const Center(
                            child: Icon(Icons.camera_alt, color: Colors.white, size: 38),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Custom painter for semi-transparent dark overlay with oval cutout
class FaceGuideOverlayPainter extends CustomPainter {
  const FaceGuideOverlayPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final backgroundPaint = Paint()..color = Colors.black.withOpacity(0.55);

    // Oval dimensions
    final ovalWidth = size.width * 0.72;
    final ovalHeight = size.height * 0.45;
    final center = Offset(size.width / 2, size.height * 0.42);
    final rect = Rect.fromCenter(center: center, width: ovalWidth, height: ovalHeight);

    // Path for overlay with cut-out
    final backgroundPath = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final ovalPath = Path()..addOval(rect);
    final combinedPath = Path.combine(PathOperation.difference, backgroundPath, ovalPath);

    canvas.drawPath(combinedPath, backgroundPaint);

    // Draw oval border guide
    final borderPaint = Paint()
      ..color = Colors.lightGreenAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    canvas.drawOval(rect, borderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
