#!/bin/bash
# ==============================================================================
# IIIT Naya Raipur Scholar Attendance & Leave System
# One-Click Linux Server Deployment Script (Ubuntu / Debian / CentOS / RHEL)
# ==============================================================================
set -e

echo "🚀 Setting up IIITNR Attendance Service on Linux Server..."

# 1. Install system prerequisites
if command -v apt-get &> /dev/null; then
    echo "📦 Installing system dependencies via apt..."
    sudo apt-get update
    sudo apt-get install -y python3 python3-pip python3-venv curl ca-certificates libgl1 libglib2.0-0 nginx
elif command -v yum &> /dev/null; then
    echo "📦 Installing system dependencies via yum..."
    sudo yum install -y python3 python3-pip curl nginx mesa-libGL glib2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$BACKEND_DIR"

# 2. Setup Python virtual environment
echo "🐍 Creating virtual environment in $BACKEND_DIR/.venv..."
python3 -m venv .venv
source .venv/bin/activate

# 3. Install Python requirements
echo "📚 Installing Python requirements..."
pip install --upgrade pip
pip install -r requirements.txt

# 4. Download OpenCV face recognition models
echo "📥 Downloading OpenCV AI Face models..."
chmod +x download_models.sh
./download_models.sh

# 5. Setup Systemd Service
echo "⚙️ Creating systemd service file (/etc/systemd/system/iiitnr-attendance.service)..."
CURRENT_USER=$(whoami)

sudo bash -c "cat << 'EOF' > /etc/systemd/system/iiitnr-attendance.service
[Unit]
Description=IIITNR Scholar Attendance & Leave Management Service
After=network.target

[Service]
Type=simple
User=$CURRENT_USER
WorkingDirectory=$BACKEND_DIR
ExecStart=$BACKEND_DIR/.venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8040
Restart=always
RestartSec=5
Environment=PYTHONUNBUFFERED=1
Environment=ATT_DATABASE_URL=sqlite:///$BACKEND_DIR/att_dev.db
Environment=ATT_UPLOAD_DIR=$BACKEND_DIR/uploads
Environment=ATT_TIMEZONE=Asia/Kolkata
Environment=ATT_INSTITUTE_DOMAIN=iiitnr.edu.in
Environment=ATT_TRUST_PROXY=true
Environment=ATT_DEV_MODE=false
Environment=ATT_GOOGLE_CLIENT_ID=734399685844-rocm7a76g418k6scthl5s7lvhajt4km4.apps.googleusercontent.com
Environment=ATT_JWT_SECRET=iiitnr-attendance-production-secret-key-2026

[Install]
WantedBy=multi-user.target
EOF"

sudo systemctl daemon-reload
sudo systemctl enable iiitnr-attendance.service
sudo systemctl restart iiitnr-attendance.service

echo ""
echo "✅ Deployment Successful!"
echo "📡 Service is running at http://0.0.0.0:8040"
echo "🔍 Check status anytime with: sudo systemctl status iiitnr-attendance"
echo "📜 View live logs with: sudo journalctl -u iiitnr-attendance -f"
