#!/bin/bash
# Download official OpenCV Zoo face models (YuNet detector & SFace recognizer)
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODELS_DIR="$SCRIPT_DIR/models"
mkdir -p "$MODELS_DIR"

echo "Downloading YuNet face detection ONNX model (227 KB)..."
curl -L -o "$MODELS_DIR/face_detection_yunet_2023mar.onnx" \
  "https://media.githubusercontent.com/media/opencv/opencv_zoo/main/models/face_detection_yunet/face_detection_yunet_2023mar.onnx"

echo "Downloading SFace face recognition ONNX model (37 MB)..."
curl -L -o "$MODELS_DIR/face_recognition_sface_2021dec.onnx" \
  "https://huggingface.co/opencv/opencv_zoo/resolve/main/models/face_recognition_sface/face_recognition_sface_2021dec.onnx"

echo "✅ OpenCV Face models downloaded successfully to $MODELS_DIR"
ls -lh "$MODELS_DIR"
