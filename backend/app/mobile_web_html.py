"""Mobile Web & iOS Attendance & Face Verification Portal with Device Registration."""

MOBILE_WEB_HTML = """<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <title>IIITNR Scholar Attendance — iOS / Web Portal</title>
  <script src="https://cdn.tailwindcss.com"></script>
  <!-- HTML5 QR Code Scanner Library for Web & iOS -->
  <script src="https://unpkg.com/html5-qrcode@2.3.8/html5-qrcode.min.js"></script>
  <!-- Google Identity Services (GIS) Web SDK -->
  <script src="https://accounts.google.com/gsi/client" async defer></script>
  <style>
    .oval-guide {
      border: 3px dashed #10b981;
      border-radius: 50% / 60%;
    }
  </style>
</head>
<body class="bg-slate-950 text-slate-100 min-h-screen flex flex-col font-sans antialiased">

  <!-- Mobile Header -->
  <header class="w-full bg-slate-900/90 border-b border-slate-800 p-4 sticky top-0 z-50 backdrop-blur">
    <div class="max-w-md mx-auto flex items-center justify-between">
      <div class="flex items-center space-x-3">
        <div class="w-9 h-9 rounded-xl bg-gradient-to-tr from-blue-600 to-indigo-600 flex items-center justify-center font-bold text-white shadow-md">
          🎓
        </div>
        <div>
          <h1 class="text-sm font-bold text-white tracking-tight">IIIT NAYA RAIPUR</h1>
          <p class="text-[11px] text-blue-400 font-medium">iOS / Mobile Attendance Portal</p>
        </div>
      </div>
      <span class="px-2 py-0.5 rounded-full text-[10px] font-bold bg-emerald-500/20 text-emerald-400 border border-emerald-500/30">
        3-Tier Security
      </span>
    </div>
  </header>

  <!-- Main Container -->
  <main class="flex-1 w-full max-w-md mx-auto p-4 flex flex-col justify-start space-y-4">

    <!-- Android APK Download Banner -->
    <a href="/download/app.apk" download class="w-full bg-gradient-to-r from-blue-700/80 to-indigo-700/80 hover:from-blue-600 hover:to-indigo-600 border border-blue-500/40 rounded-2xl p-3 flex items-center justify-between shadow-lg text-decoration-none transition">
      <div class="flex items-center space-x-3">
        <span class="text-2xl">🤖</span>
        <div>
          <p class="text-xs font-bold text-white">Download Android App (APK)</p>
          <p class="text-[10px] text-blue-200">Official IIITNR Attendance App for Android</p>
        </div>
      </div>
      <span class="px-2.5 py-1 rounded-xl text-[11px] font-bold bg-white text-blue-900 shadow">
        ⬇️ Download APK
      </span>
    </a>

    <!-- Official Google Sign In (@iiitnr.edu.in) -->
    <div class="bg-slate-900 border border-slate-800 rounded-2xl p-4 shadow-sm flex flex-col items-center">
      <div class="w-full flex items-center justify-between mb-3">
        <label class="text-xs font-semibold text-slate-300 uppercase tracking-wider">
          Institute Login:
        </label>
        <span id="google-status-badge" class="text-[10px] px-2 py-0.5 rounded-full bg-blue-500/20 text-blue-300 font-bold">
          @iiitnr.edu.in
        </span>
      </div>

      <!-- Google GSI Button -->
      <div id="g_id_onload"
           data-client_id="734399685844-rocm7a76g418k6scthl5s7lvhajt4km4.apps.googleusercontent.com"
           data-context="signin"
           data-ux_mode="popup"
           data-callback="handleGoogleLogin"
           data-auto_prompt="false">
      </div>

      <div class="g_id_signin w-full flex justify-center mb-1"
           data-type="standard"
           data-shape="rectangular"
           data-theme="filled_black"
           data-text="signin_with"
           data-size="large"
           data-logo_alignment="left">
      </div>

      <!-- Logged In Profile Banner (Hidden initially) -->
      <div id="google-user-banner" class="hidden w-full bg-slate-950/80 border border-emerald-600/40 rounded-xl p-3 flex items-center space-x-3 mt-2">
        <div class="w-9 h-9 rounded-full bg-emerald-500/20 border border-emerald-500/40 flex items-center justify-center text-sm font-bold text-emerald-400" id="google-user-avatar">
          🎓
        </div>
        <div class="flex-1 min-w-0">
          <p class="text-xs font-bold text-white truncate" id="google-user-name">Scholar Name</p>
          <p class="text-[11px] text-slate-400 truncate" id="google-user-email">email@iiitnr.edu.in</p>
        </div>
        <span class="text-[10px] px-2 py-0.5 rounded-full bg-emerald-500/20 text-emerald-400 font-bold">Verified</span>
      </div>
    </div>

    <!-- Step 0: Scholar Account & Device Lock -->
    <div class="bg-slate-900 border border-slate-800 rounded-2xl p-4 shadow-sm">
      <label class="block text-xs font-semibold text-slate-300 mb-2 uppercase tracking-wider">
        Scholar Account:
      </label>
      <select id="scholar-select" onchange="onScholarChange()" class="w-full bg-slate-800 border border-slate-700 rounded-xl px-3 py-2.5 text-sm text-white focus:outline-none focus:border-blue-500 mb-3">
        <option value="scholar1@iiitnr.edu.in">scholar1@iiitnr.edu.in (Locked to Pixel 8a — Test Proxy)</option>
        <option value="mtech1@iiitnr.edu.in">mtech1@iiitnr.edu.in (Fresh Account — Register this iPhone)</option>
      </select>

      <!-- Device Lock Status Card -->
      <div id="device-info-card" class="bg-slate-950/70 border border-slate-800 rounded-xl p-3 text-xs">
        <div class="flex items-center justify-between mb-1">
          <span class="text-slate-400 flex items-center space-x-1.5">
            <span>📱</span> <strong class="text-slate-200" id="device-model-label">Apple iPhone</strong>
          </span>
          <span id="device-lock-badge" class="px-2 py-0.5 rounded-full text-[10px] font-bold bg-amber-500/20 text-amber-300">
            Proxy Test
          </span>
        </div>
        <p id="device-lock-desc" class="text-slate-400 text-[11px] mt-1 leading-relaxed">
          Scholar 1 is locked to Google Pixel 8a. If you submit from this iPhone, system will detect device mismatch proxy.
        </p>
      </div>
    </div>

    <!-- Step 1: Scan Dynamic Guard QR -->
    <div class="bg-slate-900 border border-slate-800 rounded-2xl p-4 shadow-sm">
      <div class="flex items-center justify-between mb-2">
        <label class="text-xs font-semibold text-slate-300 uppercase tracking-wider">
          Step 1: Scan 3s Guard QR
        </label>
        <span id="qr-status-badge" class="text-[11px] px-2 py-0.5 rounded-full bg-slate-800 text-slate-400 font-medium">
          Pending
        </span>
      </div>
      <p class="text-xs text-slate-400 mb-3">
        Point camera at the rotating 3-second QR code on the laptop screen.
      </p>

      <!-- QR Scanner Camera Box -->
      <div id="qr-reader-container" class="hidden mb-3 overflow-hidden rounded-xl border border-slate-700 bg-black">
        <div id="qr-reader" class="w-full"></div>
      </div>

      <!-- Scanned Token Display -->
      <div id="qr-token-box" class="hidden bg-emerald-950/40 border border-emerald-700/50 rounded-xl p-3 mb-3 text-emerald-300 text-xs font-mono break-all flex items-center justify-between">
        <span id="qr-token-text"></span>
        <button onclick="startQrScanner()" class="ml-2 text-slate-400 hover:text-white text-xs underline">Rescan</button>
      </div>

      <button id="btn-scan-qr" onclick="startQrScanner()"
              class="w-full bg-indigo-600 hover:bg-indigo-500 text-white font-semibold py-2.5 px-4 rounded-xl flex items-center justify-center space-x-2 transition shadow-md shadow-indigo-600/20 active:scale-95 text-sm">
        <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v1m6 11h2m-6 0h-2v4m0-11v3m0 0h.01M12 12h4.01M16 20h4M4 12h4m12 0h.01M5 8h2a1 1 0 001-1V5a1 1 0 00-1-1H5a1 1 0 00-1 1v2a1 1 0 001 1zm12 0h2a1 1 0 001-1V5a1 1 0 00-1-1h-2a1 1 0 00-1 1v2a1 1 0 001 1zM5 20h2a1 1 0 001-1v-2a1 1 0 00-1-1H5a1 1 0 00-1 1v2a1 1 0 001 1z"></path>
        </svg>
        <span id="btn-scan-qr-text">📷 Open Camera to Scan Guard QR</span>
      </button>
    </div>

    <!-- Step 2: Live Face Capture -->
    <div class="bg-slate-900 border border-slate-800 rounded-2xl p-4 shadow-sm text-center flex flex-col items-center">
      <div class="w-full flex items-center justify-between mb-3">
        <label class="text-xs font-semibold text-slate-300 uppercase tracking-wider text-left">
          Step 2: Live Face Selfie
        </label>
        <span id="face-status-badge" class="text-[11px] px-2 py-0.5 rounded-full bg-slate-800 text-slate-400 font-medium">
          Pending
        </span>
      </div>

      <!-- Preview Box -->
      <div class="relative w-44 h-56 bg-slate-950 rounded-2xl border-2 border-slate-800 overflow-hidden flex items-center justify-center shadow-inner mb-3">
        <img id="preview-img" class="w-full h-full object-cover hidden" alt="Selfie preview" />
        <div id="placeholder" class="flex flex-col items-center text-slate-500 space-y-2 p-4 text-center">
          <svg class="w-10 h-10 text-slate-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M3 9a2 2 0 012-2h.93a2 2 0 001.664-.89l.812-1.22A2 2 0 0110.07 4h3.86a2 2 0 011.664.89l.812 1.22A2 2 0 0018.07 7H19a2 2 0 012 2v9a2 2 0 01-2 2H5a2 2 0 01-2-2V9z"></path>
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M15 13a3 3 0 11-6 0 3 3 0 016 0z"></path>
          </svg>
          <span class="text-[11px]">Center face inside the oval</span>
        </div>
        <div class="absolute inset-3 oval-guide pointer-events-none opacity-40"></div>
      </div>

      <!-- Native Camera Input (iOS Safari optimized) -->
      <input type="file" id="camera-input" accept="image/*" capture="user" class="hidden" />
      <button onclick="document.getElementById('camera-input').click()"
              class="w-full bg-blue-600 hover:bg-blue-500 text-white font-semibold py-2.5 px-4 rounded-xl flex items-center justify-center space-x-2 transition shadow-md shadow-blue-600/20 active:scale-95 text-sm">
        <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 10l4.553-2.276A1 1 0 0121 8.618v6.764a1 1 0 01-1.447.894L15 14M5 18h8a2 2 0 002-2V8a2 2 0 00-2-2H5a2 2 0 00-2 2v8a2 2 0 002 2z"></path>
        </svg>
        <span id="btn-snap-text">🤳 Take Live Selfie</span>
      </button>
    </div>

    <!-- Step 3: Confirm & Verify Button -->
    <button id="btn-verify" onclick="verifyAttendance()" disabled
            class="w-full bg-emerald-600 disabled:bg-slate-800 disabled:text-slate-600 hover:bg-emerald-500 text-white font-bold py-3.5 px-4 rounded-xl flex items-center justify-center space-x-2 transition shadow-lg shadow-emerald-600/20 active:scale-95">
      <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"></path>
      </svg>
      <span>Step 3: Confirm & Mark Attendance</span>
    </button>

    <!-- Result Card -->
    <div id="result-box" class="hidden rounded-2xl p-4 border transition-all">
      <div class="flex items-start space-x-3">
        <div id="result-icon" class="text-2xl mt-0.5"></div>
        <div class="flex-1">
          <h3 id="result-title" class="font-bold text-base"></h3>
          <p id="result-detail" class="text-xs mt-1 text-slate-300"></p>
          <div id="match-bar-container" class="mt-3 w-full bg-slate-800 rounded-full h-2 overflow-hidden hidden">
            <div id="match-bar" class="h-full bg-emerald-500 rounded-full transition-all duration-500" style="width: 0%"></div>
          </div>
          <div id="match-score-text" class="text-xs font-mono font-bold mt-1 text-right"></div>
        </div>
      </div>
    </div>

  </main>

  <footer class="w-full p-4 text-center text-xs text-slate-500 border-t border-slate-900 mt-auto">
    IIIT Naya Raipur • Device Lock + 3s Guard QR + AI Face Match
  </footer>

  <script>
    // Generate or get persistent device ID for this iPhone
    let myDeviceId = localStorage.getItem('iiitnr_device_id');
    if (!myDeviceId) {
      myDeviceId = 'ios-' + Math.random().toString(36).substring(2, 10) + '-' + Date.now().toString(36);
      localStorage.setItem('iiitnr_device_id', myDeviceId);
    }

    let scannedQrToken = null;
    let capturedBase64 = null;
    let html5QrScanner = null;
    let currentAuthToken = localStorage.getItem('att_auth_token') || '';

    const scholarSelect = document.getElementById('scholar-select');
    const deviceLockBadge = document.getElementById('device-lock-badge');
    const deviceLockDesc = document.getElementById('device-lock-desc');
    const cameraInput = document.getElementById('camera-input');
    const previewImg = document.getElementById('preview-img');
    const placeholder = document.getElementById('placeholder');
    const btnVerify = document.getElementById('btn-verify');
    const btnSnapText = document.getElementById('btn-snap-text');
    const qrStatusBadge = document.getElementById('qr-status-badge');
    const faceStatusBadge = document.getElementById('face-status-badge');
    const qrReaderContainer = document.getElementById('qr-reader-container');
    const qrTokenBox = document.getElementById('qr-token-box');
    const qrTokenText = document.getElementById('qr-token-text');
    const btnScanQrText = document.getElementById('btn-scan-qr-text');

    function onScholarChange() {
      const email = scholarSelect.value;
      if (email.includes('scholar1')) {
        deviceLockBadge.className = 'px-2 py-0.5 rounded-full text-[10px] font-bold bg-amber-500/20 text-amber-300';
        deviceLockBadge.textContent = 'Proxy Test Mode';
        deviceLockDesc.textContent = 'Scholar 1 is locked to Google Pixel 8a. Submitting from this iPhone will test Device Lock + Face AI mismatch rejection!';
      } else if (email.includes('heroshowroomchurcha')) {
        deviceLockBadge.className = 'px-2 py-0.5 rounded-full text-[10px] font-bold bg-emerald-500/20 text-emerald-300';
        deviceLockBadge.textContent = 'Google SSO Verified';
        deviceLockDesc.textContent = 'Authenticated via Google Workspace SSO. Ready for biometric attendance check.';
      } else {
        deviceLockBadge.className = 'px-2 py-0.5 rounded-full text-[10px] font-bold bg-blue-500/20 text-blue-300';
        deviceLockBadge.textContent = 'New Phone Enrollment';
        deviceLockDesc.textContent = 'Account mtech1 has no phone yet. This iPhone will be registered and locked as its official device!';
      }
    }

    function updateVerifyButton() {
      if (scannedQrToken && capturedBase64) {
        btnVerify.disabled = false;
        btnVerify.classList.remove('disabled:bg-slate-800', 'disabled:text-slate-600');
      } else {
        btnVerify.disabled = true;
      }
    }

    // --- Step 1: QR Scanner (HTML5 Camera) ---
    function startQrScanner() {
      qrReaderContainer.classList.remove('hidden');
      btnScanQrText.textContent = 'Scanning for QR...';

      if (!html5QrScanner) {
        html5QrScanner = new Html5Qrcode("qr-reader");
      }

      html5QrScanner.start(
        { facingMode: "environment" },
        { fps: 10, qrbox: { width: 250, height: 250 } },
        (decodedText) => {
          scannedQrToken = decodedText;
          html5QrScanner.stop().then(() => {
            qrReaderContainer.classList.add('hidden');
            qrTokenBox.classList.remove('hidden');
            qrTokenText.textContent = '✅ ' + decodedText.substring(0, 24) + '...';
            qrStatusBadge.className = 'text-[11px] px-2 py-0.5 rounded-full bg-emerald-500/20 text-emerald-400 font-bold';
            qrStatusBadge.textContent = 'QR Scanned ✅';
            btnScanQrText.textContent = '🔄 Rescan QR';
            updateVerifyButton();
          }).catch(console.error);
        },
        (errorMessage) => {}
      ).catch(err => {
        alert("Camera error: " + err + "\\nPlease allow camera permissions in Safari.");
        qrReaderContainer.classList.add('hidden');
      });
    }

    // --- Step 2: Native Camera Selfie Capture ---
    cameraInput.addEventListener('change', (e) => {
      const file = e.target.files[0];
      if (!file) return;

      const reader = new FileReader();
      reader.onload = (event) => {
        const img = new Image();
        img.onload = () => {
          const maxDim = 640;
          let w = img.width, h = img.height;
          if (w > maxDim || h > maxDim) {
            if (w > h) { h = Math.round(h * maxDim / w); w = maxDim; }
            else { w = Math.round(w * maxDim / h); h = maxDim; }
          }
          const canvas = document.createElement('canvas');
          canvas.width = w; canvas.height = h;
          const ctx = canvas.getContext('2d');
          ctx.drawImage(img, 0, 0, w, h);
          capturedBase64 = canvas.toDataURL('image/jpeg', 0.85);

          previewImg.src = capturedBase64;
          previewImg.classList.remove('hidden');
          placeholder.classList.add('hidden');
          faceStatusBadge.className = 'text-[11px] px-2 py-0.5 rounded-full bg-emerald-500/20 text-emerald-400 font-bold';
          faceStatusBadge.textContent = 'Selfie Ready ✅';
          btnSnapText.textContent = '🔄 Retake Selfie';
          updateVerifyButton();
        };
        img.src = event.target.result;
      };
      reader.readAsDataURL(file);
    });

    // --- Step 3: Verify Attendance (Device + QR + Face) ---
    async function verifyAttendance() {
      if (!scannedQrToken) {
        alert("Please scan the 3-second Guard QR code first!");
        return;
      }
      if (!capturedBase64) {
        alert("Please capture a live selfie first!");
        return;
      }

      const email = scholarSelect.value;
      const resultBox = document.getElementById('result-box');
      const resultIcon = document.getElementById('result-icon');
      const resultTitle = document.getElementById('result-title');
      const resultDetail = document.getElementById('result-detail');
      const matchBarContainer = document.getElementById('match-bar-container');
      const matchBar = document.getElementById('match-bar');
      const matchScoreText = document.getElementById('match-score-text');

      btnVerify.disabled = true;
      btnVerify.innerHTML = '<svg class="animate-spin h-5 w-5 text-white" viewBox="0 0 24 24"><circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4" fill="none"></circle><path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8v8H4z"></path></svg> <span>Verifying Device, QR & Face...</span>';

      try {
        const reqHeaders = { 'Content-Type': 'application/json' };
        if (currentAuthToken) {
          reqHeaders['Authorization'] = 'Bearer ' + currentAuthToken;
        }
        const res = await fetch('/att/face/test-verify', {
          method: 'POST',
          headers: reqHeaders,
          body: JSON.stringify({
            email: email,
            qr_token: scannedQrToken,
            face_image: capturedBase64,
            device_id: myDeviceId,
            platform: 'iOS',
            model: 'Apple iPhone'
          })
        });
        const data = await res.json();

        resultBox.classList.remove('hidden');
        matchBarContainer.classList.remove('hidden');

        if (data.action === 'ENROLLED') {
          resultBox.className = 'rounded-2xl p-4 border bg-blue-950/40 border-blue-600/40 text-blue-200';
          resultIcon.textContent = '📱';
          resultTitle.textContent = 'Device Registered & Face Enrolled!';
          resultDetail.textContent = data.message;
          matchBar.style.width = '100%';
          matchBar.className = 'h-full bg-blue-500 rounded-full';
          matchScoreText.textContent = '100% (Device Locked + Face Saved)';
        } else if (data.ok === true) {
          resultBox.className = 'rounded-2xl p-4 border bg-emerald-950/40 border-emerald-600/40 text-emerald-200';
          resultIcon.textContent = '✅';
          resultTitle.textContent = 'Attendance Verified (' + data.match_pct + '% Match)';
          resultDetail.textContent = 'Device Lock OK • Guard QR Valid • Live Face Matched! Attendance Marked Present.';
          matchBar.style.width = data.match_pct + '%';
          matchBar.className = 'h-full bg-emerald-500 rounded-full';
          matchScoreText.textContent = data.match_pct + '% Match';
          matchScoreText.className = 'text-xs font-mono font-bold mt-1 text-right text-emerald-400';
        } else if (data.action === 'DEVICE_MISMATCH') {
          resultBox.className = 'rounded-2xl p-4 border bg-rose-950/40 border-rose-600/40 text-rose-200';
          resultIcon.textContent = '🔒';
          resultTitle.textContent = 'Device Lock + Face Rejection!';
          resultDetail.textContent = data.message;
          matchBar.style.width = data.match_pct + '%';
          matchBar.className = 'h-full bg-rose-500 rounded-full';
          matchScoreText.textContent = data.match_pct + '% Match (Imposter/Proxy Phone)';
          matchScoreText.className = 'text-xs font-mono font-bold mt-1 text-right text-rose-400';
        } else if (data.action === 'INVALID_QR') {
          resultBox.className = 'rounded-2xl p-4 border bg-amber-950/40 border-amber-600/40 text-amber-200';
          resultIcon.textContent = '⏱️';
          resultTitle.textContent = 'Guard QR Expired or Invalid';
          resultDetail.textContent = data.message + ' (Guard QR code rotates every 3 seconds). Please rescan live QR.';
          matchBar.style.width = '0%';
          matchScoreText.textContent = 'QR Expired';
        } else {
          resultBox.className = 'rounded-2xl p-4 border bg-rose-950/40 border-rose-600/40 text-rose-200';
          resultIcon.textContent = '❌';
          resultTitle.textContent = 'Face Mismatch (' + data.match_pct + '% Match)';
          resultDetail.textContent = data.message;
          matchBar.style.width = data.match_pct + '%';
          matchBar.className = 'h-full bg-rose-500 rounded-full';
          matchScoreText.textContent = data.match_pct + '% Match (Below 70% threshold)';
          matchScoreText.className = 'text-xs font-mono font-bold mt-1 text-right text-rose-400';
        }
      } catch (err) {
        resultBox.classList.remove('hidden');
        resultBox.className = 'rounded-2xl p-4 border bg-amber-950/40 border-amber-600/40 text-amber-200';
        resultIcon.textContent = '⚠️';
        resultTitle.textContent = 'Verification Error';
        resultDetail.textContent = err.message || 'Could not connect to server.';
      } finally {
        btnVerify.disabled = false;
        btnVerify.innerHTML = '<svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"></path></svg> <span>Step 3: Confirm & Mark Attendance</span>';
      }
    }

    function handleGoogleLogin(response) {
      const idToken = response.credential;
      fetch('/auth/google', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ id_token: idToken })
      })
      .then(res => res.json())
      .then(data => {
        if (data.ok) {
          currentAuthToken = data.token;
          localStorage.setItem('att_auth_token', data.token);
          document.getElementById('google-user-banner').classList.remove('hidden');
          const gsiBtn = document.querySelector('.g_id_signin');
          if (gsiBtn) gsiBtn.classList.add('hidden');
          document.getElementById('google-user-name').textContent = data.person.name || data.person.email;
          document.getElementById('google-user-email').textContent = data.person.email;

          // Select or add logged-in email to dropdown
          const select = document.getElementById('scholar-select');
          let found = false;
          for (let opt of select.options) {
            if (opt.value === data.person.email) {
              select.value = data.person.email;
              found = true;
              break;
            }
          }
          if (!found) {
            const newOpt = document.createElement('option');
            newOpt.value = data.person.email;
            newOpt.textContent = data.person.email + ' (Google Verified)';
            select.appendChild(newOpt);
            select.value = data.person.email;
          }
          onScholarChange();
          alert('✅ Welcome, ' + (data.person.name || data.person.email) + '! You are authenticated with your official IIITNR Google account.');
        } else {
          alert('❌ Google Login Failed: ' + (data.detail?.message || JSON.stringify(data)));
        }
      })
      .catch(err => alert('Network error: ' + err));
    }

    onScholarChange();
  </script>
</body>
</html>
"""
