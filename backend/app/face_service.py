from __future__ import annotations

import base64
import hashlib
import json
import logging
import math
from pathlib import Path
import threading
from typing import Tuple

try:
    import cv2
    import numpy as np
    HAS_OPENCV = True
except ImportError:
    cv2 = None  # type: ignore
    np = None   # type: ignore
    HAS_OPENCV = False

logger = logging.getLogger(__name__)

# OpenCV SFace standard cosine verification threshold
# Pairs with cosine similarity >= 0.363 are considered the same person.
SFACE_COSINE_THRESHOLD = 0.363
DEFAULT_THRESHOLD = SFACE_COSINE_THRESHOLD

# Path to ONNX face models
_MODELS_DIR = Path(__file__).resolve().parent.parent / "models"
_YUNET_PATH = _MODELS_DIR / "face_detection_yunet_2023mar.onnx"
_SFACE_PATH = _MODELS_DIR / "face_recognition_sface_2021dec.onnx"
# Photo / screen check (MiniFASNet V2, Apache-2.0, github.com/yakhyo/face-anti-spoofing)
_LIVENESS_PATH = _MODELS_DIR / "MiniFASNetV2.onnx"
LIVENESS_INPUT = (80, 80)   # model input, width x height
LIVENESS_SCALE = 2.7        # crop this many face-widths around the face (as the model was trained)

_model_lock = threading.Lock()
_detector = None
_recognizer = None


def _init_models() -> tuple:
    global _detector, _recognizer
    if not HAS_OPENCV or cv2 is None:
        return None, None
    if _detector is None or _recognizer is None:
        if _YUNET_PATH.exists() and _SFACE_PATH.exists():
            try:
                _detector = cv2.FaceDetectorYN.create(
                    str(_YUNET_PATH), "", (320, 320),
                    score_threshold=0.5,
                    nms_threshold=0.3,
                    top_k=5,
                )
                _recognizer = cv2.FaceRecognizerSF.create(str(_SFACE_PATH), "")
            except Exception as e:
                print(f"[face_service] Warning: Failed to load ONNX face models: {e}")
    return _detector, _recognizer


def parse_and_validate_face_image(b64_string: str) -> bytes:
    """Validates base64 string and returns raw image bytes."""
    if not b64_string:
        raise ValueError("Image data is empty.")

    # Remove data URL prefix if present (e.g. data:image/jpeg;base64,...)
    if "," in b64_string:
        b64_string = b64_string.split(",", 1)[1]

    try:
        raw_bytes = base64.b64decode(b64_string)
    except Exception as e:
        raise ValueError(f"Invalid base64 encoding: {e}")

    if len(raw_bytes) < 500:
        raise ValueError("Image payload is too small to contain a valid face.")
    if len(raw_bytes) > 5 * 1024 * 1024:
        raise ValueError("Image payload exceeds 5MB limit.")

    return raw_bytes


class FaceServiceUnavailable(RuntimeError):
    """The face models are not installed; verification must fail closed."""


def calibrate_match_percentage(raw_cosine: float) -> int:
    """Calibrates raw SFace cosine similarity (-1.0 to 1.0) to an intuitive 0-100% match score.
    SFace standard verification threshold is cosine >= 0.363.
    Values >= 0.363 map to 70%-100% (Match).
    Values < 0.363 map to 0%-69% (Mismatch)."""
    if raw_cosine >= SFACE_COSINE_THRESHOLD:
        pct = 70 + int(((raw_cosine - SFACE_COSINE_THRESHOLD) / (1.0 - SFACE_COSINE_THRESHOLD)) * 30)
        return min(100, max(70, pct))
    else:
        pct = int(max(0.0, raw_cosine) / SFACE_COSINE_THRESHOLD * 69)
        return min(69, max(0, pct))


def generate_face_embedding(raw_bytes: bytes) -> list[float]:
    """Extracts a normalized 128-dimensional face embedding vector using OpenCV YuNet + SFace ONNX models.
    Never falls back to a hash of the bytes: that would let anyone replay the same bytes as a "face"."""
    if not HAS_OPENCV or cv2 is None or np is None:
        raise FaceServiceUnavailable("Face verification is not available on the server (OpenCV missing).")

    # Attempt to decode as image with OpenCV
    img = None
    try:
        nparr = np.frombuffer(raw_bytes, np.uint8)
        img = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
    except Exception:
        img = None

    if img is None:
        raise ValueError("The selfie is not a valid image. Please capture it again.")

    det, rec = _init_models()
    if det is None or rec is None:
        raise FaceServiceUnavailable("Face verification is not available on the server (models missing).")

    with _model_lock:
        h, w = img.shape[:2]
        det.setInputSize((w, h))
        _, faces = det.detect(img)

        if faces is None or len(faces) == 0:
            raise ValueError("No face detected in selfie. Please center your face in the oval guide and ensure good lighting.")

        # Sort faces by bounding box area (w * h) descending to pick primary face
        faces_sorted = sorted(faces, key=lambda f: f[2] * f[3], reverse=True)
        primary_face = faces_sorted[0]

        # Ensure face is large enough (at least 40x40 pixels)
        fw, fh = primary_face[2], primary_face[3]
        if fw < 40 or fh < 40:
            raise ValueError("Face is too small or too far from camera. Please hold your phone closer.")

        # Align and crop face to 112x112 canonical view
        aligned_face = rec.alignCrop(img, primary_face)

        # Extract 128-dimensional deep feature representation
        features = rec.feature(aligned_face)

        # Ensure unit L2 normalization
        vec = features.flatten().astype(float).tolist()
        norm = math.sqrt(sum(x * x for x in vec)) or 1.0
        return [x / norm for x in vec]


def cosine_similarity(v1: list[float], v2: list[float]) -> float:
    """Computes cosine similarity between two unit vectors."""
    if len(v1) != len(v2) or not v1:
        return 0.0
    dot = sum(a * b for a, b in zip(v1, v2))
    norm1 = math.sqrt(sum(a * a for a in v1)) or 1.0
    norm2 = math.sqrt(sum(b * b for b in v2)) or 1.0
    return dot / (norm1 * norm2)


def verify_face(enrolled_embedding_json: str | None, current_image_b64: str,
                threshold: float = SFACE_COSINE_THRESHOLD) -> Tuple[bool, float, str]:
    """Verifies captured selfie against the scholar's enrolled reference embedding.
    Returns: (is_match, score_float, explanation_string)."""
    if not enrolled_embedding_json:
        return False, 0.0, "Scholar has not enrolled reference face template yet."

    try:
        raw_bytes = parse_and_validate_face_image(current_image_b64)
    except ValueError as e:
        return False, 0.0, str(e)

    try:
        enrolled_vec = json.loads(enrolled_embedding_json)
        current_vec = generate_face_embedding(raw_bytes)
    except ValueError as e:
        return False, 0.0, str(e)
    except FaceServiceUnavailable:
        raise
    try:
        raw_sim = cosine_similarity(enrolled_vec, current_vec)
        calibrated_pct = calibrate_match_percentage(raw_sim)
        score = calibrated_pct / 100.0

        if raw_sim >= threshold:
            return True, score, f"Face verified successfully ({calibrated_pct}% match)"
        else:
            return False, score, f"Face mismatch ({calibrated_pct}% match)"
    except Exception as e:
        return False, 0.0, f"Face verification error: {e}"


# ---------------------------------------------------------------- liveness (photo / screen check)

_liveness_net = None
_liveness_tried = False


def _liveness_model():
    global _liveness_net, _liveness_tried
    if _liveness_net is None and not _liveness_tried and HAS_OPENCV and cv2 is not None:
        _liveness_tried = True
        if _LIVENESS_PATH.exists():
            try:
                _liveness_net = cv2.dnn.readNetFromONNX(str(_LIVENESS_PATH))
            except Exception:
                logger.exception("Could not load the liveness model")
    return _liveness_net


def _softmax(x):
    e = np.exp(x - np.max(x))
    return e / e.sum()


def liveness_score(raw_bytes: bytes) -> float | None:
    """Chance (0..1) that the selfie shows a real face and not a printed photo or a screen.
    None when the model is not installed or no face is found (the caller decides what to do)."""
    net = _liveness_model()
    if net is None or np is None:
        return None
    img = cv2.imdecode(np.frombuffer(raw_bytes, np.uint8), cv2.IMREAD_COLOR)
    if img is None:
        return None
    det, _ = _init_models()
    if det is None:
        return None
    with _model_lock:
        h, w = img.shape[:2]
        det.setInputSize((w, h))
        _, faces = det.detect(img)
        if faces is None or len(faces) == 0:
            return None
        x, y, bw, bh = [float(v) for v in max(faces, key=lambda f: f[2] * f[3])[:4]]
        # Crop around the face with context, as in the model's training (uniface MiniFASNet._crop_face)
        scale = min((h - 1) / bh, (w - 1) / bw, LIVENESS_SCALE)
        nw, nh = bw * scale, bh * scale
        cx, cy = x + bw / 2, y + bh / 2
        x1, y1 = max(0, int(cx - nw / 2)), max(0, int(cy - nh / 2))
        x2, y2 = min(w - 1, int(cx + nw / 2)), min(h - 1, int(cy + nh / 2))
        crop = cv2.resize(img[y1:y2 + 1, x1:x2 + 1], LIVENESS_INPUT)
        blob = np.transpose(crop.astype(np.float32), (2, 0, 1))[np.newaxis]  # BGR, no normalisation
        net.setInput(blob)
        out = net.forward().reshape(-1)
    probs = _softmax(out)
    return float(probs[1])  # class 1 = real face
