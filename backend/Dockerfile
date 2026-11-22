# Multi-stage Dockerfile for IIITNR Attendance Backend & Face Verification
FROM python:3.11-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    PORT=8040

# Install required system packages for OpenCV and cryptography
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    libglib2.0-0 \
    libgl1 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy dependency specifications first for Docker layer caching
COPY requirements.txt .

RUN pip install --no-cache-dir -r requirements.txt

# Copy application source code
COPY . .

# Download the official OpenCV YuNet & SFace ONNX models if not present
RUN chmod +x download_models.sh && ./download_models.sh

# Create persistent directories for SQLite database and uploads
RUN mkdir -p /app/data /app/uploads

# Set default environment variables
ENV ATT_DATABASE_URL="sqlite:////app/data/attendance.db" \
    ATT_UPLOAD_DIR="/app/uploads" \
    ATT_TIMEZONE="Asia/Kolkata" \
    ATT_INSTITUTE_DOMAIN="iiitnr.edu.in" \
    ATT_TRUST_PROXY="true"

EXPOSE 8040

HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:8040/health || exit 1

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8040"]
