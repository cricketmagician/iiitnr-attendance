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

echo "Downloading MiniFASNetV2 photo/screen check ONNX model (1.7 MB)..."
# Apache-2.0, github.com/yakhyo/face-anti-spoofing (ONNX port of Minivision Silent-Face-Anti-Spoofing).
# Checksum is the one published by the uniface library for this file.
curl -L -o "$MODELS_DIR/MiniFASNetV2.onnx" \
  "https://github.com/yakhyo/face-anti-spoofing/releases/download/weights/MiniFASNetV2.onnx"
EXPECTED="b32929adc2d9c34b9486f8c4c7bc97c1b69bc0ea9befefc380e4faae4e463907"
ACTUAL="$( (sha256sum "$MODELS_DIR/MiniFASNetV2.onnx" 2>/dev/null || shasum -a 256 "$MODELS_DIR/MiniFASNetV2.onnx") | cut -d' ' -f1)"
if [ "$ACTUAL" != "$EXPECTED" ]; then
  echo "❌ MiniFASNetV2.onnx checksum mismatch ($ACTUAL); removing it"
  rm -f "$MODELS_DIR/MiniFASNetV2.onnx"
  exit 1
fi

echo "✅ OpenCV Face models downloaded successfully to $MODELS_DIR"
ls -lh "$MODELS_DIR"
