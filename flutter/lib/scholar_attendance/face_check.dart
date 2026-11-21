import 'package:flutter/material.dart';
import 'camera_face_capture.dart';

/// Face Check handler:
/// Opens the guided camera preview, captures a live selfie with oval overlay,
/// compresses it, and returns the base64 image to be signed and verified by the server.
class FaceCheck {
  /// Opens the guided camera capture screen.
  /// Returns the base64-encoded JPEG image string, or null if cancelled/failed.
  static Future<String?> captureFace(BuildContext context, {required String sessionLabel}) async {
    return await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => CameraFaceCaptureScreen(sessionLabel: sessionLabel),
        fullscreenDialog: true,
      ),
    );
  }
}
