import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Step 1: Scan Guard's 3-second rotating dynamic QR code.
class QRScannerScreen extends StatefulWidget {
  final String sessionLabel;
  const QRScannerScreen({super.key, required this.sessionLabel});

  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
  );
  bool _detected = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) async {
    if (_detected) return;
    for (final barcode in capture.barcodes) {
      final code = barcode.rawValue;
      if (code != null && code.startsWith('IIITNR-ATT:')) {
        setState(() => _detected = true);
        try {
          await _controller.stop();
        } catch (_) {}
        if (!mounted) return;
        Navigator.pop(context, code);
        break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Step 1 of 2 · Scan guard QR'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on),
            onPressed: () => _controller.toggleTorch(),
          ),
          IconButton(
            icon: const Icon(Icons.flip_camera_android),
            onPressed: () => _controller.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),
          // Viewfinder overlay
          Center(
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                border: Border.all(
                  color: _detected ? Colors.greenAccent : Colors.blueAccent,
                  width: 3,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Stack(
                children: [
                  // Corner accents
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(width: 24, height: 4, color: Colors.blueAccent),
                  ),
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(width: 4, height: 24, color: Colors.blueAccent),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(width: 24, height: 4, color: Colors.blueAccent),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(width: 4, height: 24, color: Colors.blueAccent),
                  ),
                  Positioned(
                    bottom: 8,
                    left: 8,
                    child: Container(width: 24, height: 4, color: Colors.blueAccent),
                  ),
                  Positioned(
                    bottom: 8,
                    left: 8,
                    child: Container(width: 4, height: 24, color: Colors.blueAccent),
                  ),
                  Positioned(
                    bottom: 8,
                    right: 8,
                    child: Container(width: 24, height: 4, color: Colors.blueAccent),
                  ),
                  Positioned(
                    bottom: 8,
                    right: 8,
                    child: Container(width: 4, height: 24, color: Colors.blueAccent),
                  ),
                ],
              ),
            ),
          ),
          // Instruction banner at bottom
          Positioned(
            bottom: 40,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.8),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white24),
              ),
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Point at Guard’s Rotating QR Code',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 6),
                  Text(
                    'The QR rotates every 3 seconds on the Guard’s screen to guarantee physical presence.',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
