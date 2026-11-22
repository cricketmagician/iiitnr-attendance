# 🚀 IIITNR Scholar Attendance & Leave System — Deployment Guide

This guide covers two deployment modes:
1. **Cloud Free Deployment (Immediate / Temporary)**: Deploy on **Render.com** (recommended) or **Vercel** with permanent HTTPS URL.
2. **Institute Server / VPS Deployment (Final)**: Deploying on a college physical server, virtual machine, or Linux VPS with Docker or Systemd.

---

## 🌐 Option 1: Free Cloud Deployment (Immediate)

### A. Deploy on Render.com (Recommended — 2 Minutes)
Render runs the full Python FastAPI server 24/7 with background workers, persistent storage, and OpenCV face models.

1. Go to [Render.com](https://render.com) and Sign In with your GitHub account.
2. Click **New +** > **Web Service** (or **Blueprint**).
3. Connect your repository: `cricketmagician/iiitnr-attendance`.
4. Render will automatically detect `render.yaml`. Click **Apply / Create**.
5. Once built (takes ~2 minutes), Render gives you a permanent HTTPS domain:
   ```
   https://iiitnr-attendance.onrender.com
   ```
   * **Root Portal**: `https://iiitnr-attendance.onrender.com`
   * **Guard Kiosk**: `https://iiitnr-attendance.onrender.com/guard`
   * **APK Download**: `https://iiitnr-attendance.onrender.com/download/app.apk`

---

### B. Deploy on Vercel
Vercel is serverless. Configuration files (`vercel.json` and `api/index.py`) are pre-configured in this repository.

1. Go to [Vercel.com](https://vercel.com) and import `cricketmagician/iiitnr-attendance`.
2. Set Environment Variables:
   * `ATT_GOOGLE_CLIENT_ID`: `734399685844-rocm7a76g418k6scthl5s7lvhajt4km4.apps.googleusercontent.com`
   * `ATT_JWT_SECRET`: Any random 32-character string.
   * `ATT_DATABASE_URL`: Hosted PostgreSQL connection URL (e.g. from Neon or Supabase free tier).
3. Click **Deploy**.

---

## 🖥️ Option 2: Institute Server / Linux VPS Deployment (Final Server)

When the institute provides you with a dedicated server or Ubuntu/Debian VM, use either Docker or Native Systemd.

### Method A: Docker Compose (Fastest & Cleanest)

Prerequisites on server: `docker` and `docker compose`.

1. Clone the repository on the server:
   ```bash
   git clone https://github.com/cricketmagician/iiitnr-attendance.git
   cd iiitnr-attendance
   ```

2. Start the service with Docker Compose:
   ```bash
   docker compose up -d --build
   ```

3. Check status & logs:
   ```bash
   docker compose ps
   docker compose logs -f attendance-api
   ```
   * The database persists on the host in `./attendance_data/attendance.db`.
   * Uploaded leave files persist in `./attendance_uploads/`.
   * Automatically restarts if the server reboots!

---

### Method B: Native Systemd Service (Bare Metal / Without Docker)

If Docker is not installed on the institute server, run the automated setup script:

1. Clone the repository on the server:
   ```bash
   git clone https://github.com/cricketmagician/iiitnr-attendance.git
   cd iiitnr-attendance/backend
   ```

2. Run the server installer script:
   ```bash
   chmod +x scripts/setup_server.sh
   ./scripts/setup_server.sh
   ```

3. Manage the service anytime:
   ```bash
   sudo systemctl status iiitnr-attendance
   sudo systemctl restart iiitnr-attendance
   sudo journalctl -u iiitnr-attendance -f
   ```

---

## 🔒 Nginx Reverse Proxy & SSL Configuration (Optional)

To map a college domain (e.g., `attendance.iiitnr.ac.in`) to the service on port `8040`:

```nginx
server {
    listen 80;
    server_name attendance.iiitnr.ac.in;

    # Maximum file upload size for leave attachments
    client_max_body_size 10M;

    location / {
        proxy_pass http://127.0.0.1:8040;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

Enable HTTPS via Let's Encrypt:
```bash
sudo certbot --nginx -d attendance.iiitnr.ac.in
```
