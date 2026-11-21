"""HTML Template for the Guard Desk / Kiosk dynamic 3-second rotating QR code screen."""

GUARD_KIOSK_HTML = """<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>IIITNR Guard Desk Kiosk — Dynamic 3s QR</title>
  <script src="https://cdn.tailwindcss.com"></script>
  <script src="https://cdnjs.cloudflare.com/ajax/libs/qrcodejs/1.0.0/qrcode.min.js"></script>
  <style>
    @keyframes pulse-ring {
      0% { transform: scale(0.95); opacity: 0.8; }
      50% { transform: scale(1.05); opacity: 0.4; }
      100% { transform: scale(0.95); opacity: 0.8; }
    }
    .pulse-glow {
      box-shadow: 0 0 35px rgba(59, 130, 246, 0.4);
    }
  </style>
</head>
<body class="bg-slate-950 text-slate-100 min-h-screen flex flex-col items-center justify-between p-4 select-none font-sans">
  
  <!-- Header -->
  <header class="w-full max-w-lg flex items-center justify-between py-3 px-4 bg-slate-900/80 rounded-2xl border border-slate-800 backdrop-blur">
    <div class="flex items-center space-x-3">
      <div class="w-10 h-10 rounded-xl bg-gradient-to-tr from-blue-600 to-indigo-500 flex items-center justify-center font-bold text-lg shadow-lg">
        🎓
      </div>
      <div>
        <h1 class="text-base font-bold tracking-tight text-white">IIIT NAYA RAIPUR</h1>
        <p class="text-xs text-blue-400 font-medium tracking-wide">Scholar Attendance • Guard Kiosk</p>
      </div>
    </div>
    <div class="text-right">
      <span id="session-badge" class="px-2.5 py-1 rounded-full text-xs font-bold bg-emerald-500/20 text-emerald-400 border border-emerald-500/30">
        Morning Session
      </span>
      <div id="live-clock" class="text-xs text-slate-400 font-mono mt-1">--:--:--</div>
    </div>
  </header>

  <!-- Main Kiosk Body -->
  <main class="w-full max-w-md flex flex-col items-center my-auto">
    
    <!-- Security Banner -->
    <div class="mb-4 flex items-center space-x-2 bg-blue-950/60 border border-blue-800/50 rounded-full px-4 py-1.5 text-xs text-blue-300">
      <span class="w-2 h-2 rounded-full bg-emerald-400 animate-ping"></span>
      <span class="font-semibold">Dynamic Anti-Proxy Mode:</span>
      <span class="text-slate-400">Rotates every 3s</span>
    </div>

    <!-- QR Container -->
    <div class="relative p-6 bg-white rounded-3xl shadow-2xl pulse-glow flex flex-col items-center justify-center transition-all duration-300" id="qr-card">
      <div id="qrcode" class="w-[260px] h-[260px] flex items-center justify-center"></div>
      
      <!-- Overlay Institute Logo -->
      <div class="absolute inset-0 flex items-center justify-center pointer-events-none">
        <div class="w-12 h-12 bg-white rounded-xl shadow-md border-2 border-indigo-600 flex items-center justify-center text-indigo-700 font-black text-sm">
          IIIT
        </div>
      </div>
    </div>

    <!-- 3-Second Timer & Progress Bar -->
    <div class="w-full max-w-xs mt-6 flex flex-col items-center">
      <div class="w-full flex items-center justify-between text-xs text-slate-400 mb-1.5 font-mono">
        <span class="flex items-center space-x-1.5">
          <svg class="w-3.5 h-3.5 text-blue-400 animate-spin" fill="none" viewBox="0 0 24 24">
            <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
            <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8v8H4z"></path>
          </svg>
          <span>Refresh in <strong id="secs-text" class="text-blue-400">3s</strong></span>
        </span>
        <span id="slot-id" class="text-slate-500 text-[10px]">Slot #--</span>
      </div>

      <!-- Linear progress bar -->
      <div class="w-full h-2 bg-slate-800 rounded-full overflow-hidden p-0.5 border border-slate-700">
        <div id="progress-bar" class="h-full bg-gradient-to-r from-blue-500 to-indigo-500 rounded-full transition-all duration-100 w-full"></div>
      </div>
    </div>

    <!-- Instructions for Scholars -->
    <div class="mt-6 bg-slate-900/90 border border-slate-800 rounded-2xl p-4 w-full text-center">
      <p class="text-sm font-semibold text-slate-200">How to mark attendance:</p>
      <div class="grid grid-cols-3 gap-2 mt-2 text-xs text-slate-400">
        <div class="bg-slate-800/60 p-2 rounded-xl">
          <div class="text-base mb-1">📱</div>
          <div>1. Scan QR</div>
        </div>
        <div class="bg-slate-800/60 p-2 rounded-xl">
          <div class="text-base mb-1">🤳</div>
          <div>2. Face Check</div>
        </div>
        <div class="bg-slate-800/60 p-2 rounded-xl">
          <div class="text-base mb-1">✅</div>
          <div>3. Confirm</div>
        </div>
      </div>
    </div>

    <!-- iOS / Mobile Web Portal Quick Link -->
    <div class="mt-3 bg-blue-950/40 border border-blue-800/40 rounded-2xl p-3 w-full text-center">
      <p class="text-xs font-semibold text-blue-300 flex items-center justify-center space-x-1.5">
        <span>🍎</span> <span>iPhone (iOS) / Mobile Web Test Link:</span>
      </p>
      <a href="/m" target="_blank" class="text-xs text-blue-400 font-mono underline hover:text-blue-200 block mt-1 font-bold">
        http://192.168.137.17:8040/m
      </a>
    </div>

  </main>

  <!-- Footer with controls -->
  <footer class="w-full max-w-lg flex items-center justify-between text-xs text-slate-500 py-2 px-4">
    <button onclick="toggleFullscreen()" class="px-3 py-1.5 bg-slate-900 hover:bg-slate-800 border border-slate-800 rounded-lg text-slate-300 flex items-center space-x-1.5 transition">
      <span>⛶</span> <span>Fullscreen</span>
    </button>
    <div class="flex items-center space-x-2">
      <button id="sound-btn" onclick="toggleSound()" class="px-3 py-1.5 bg-slate-900 hover:bg-slate-800 border border-slate-800 rounded-lg text-slate-400 transition">
        🔔 Sound: Off
      </button>
    </div>
  </footer>

  <script>
    let qrcode = null;
    let currentSlot = null;
    let soundEnabled = false;
    let audioCtx = null;

    function playBeep() {
      if (!soundEnabled) return;
      try {
        if (!audioCtx) audioCtx = new (window.AudioContext || window.webkitAudioContext)();
        const osc = audioCtx.createOscillator();
        const gain = audioCtx.createGain();
        osc.connect(gain);
        gain.connect(audioCtx.destination);
        osc.frequency.value = 880;
        gain.gain.setValueAtTime(0.05, audioCtx.currentTime);
        gain.gain.exponentialRampToValueAtTime(0.001, audioCtx.currentTime + 0.08);
        osc.start();
        osc.stop(audioCtx.currentTime + 0.08);
      } catch (e) {}
    }

    function toggleSound() {
      soundEnabled = !soundEnabled;
      document.getElementById('sound-btn').innerText = soundEnabled ? '🔔 Sound: On' : '🔕 Sound: Off';
      document.getElementById('sound-btn').className = soundEnabled ? 'px-3 py-1.5 bg-blue-900/60 border border-blue-700 rounded-lg text-blue-200' : 'px-3 py-1.5 bg-slate-900 border border-slate-800 rounded-lg text-slate-400';
    }

    function toggleFullscreen() {
      if (!document.fullscreenElement) {
        document.documentElement.requestFullscreen().catch(() => {});
      } else {
        document.exitFullscreen().catch(() => {});
      }
    }

    async function fetchQR() {
      try {
        const res = await fetch('/att/guard/qr');
        if (!res.ok) return;
        const data = await res.json();
        
        // Update Session info
        document.getElementById('session-badge').innerText = data.session_label + ' Session';
        document.getElementById('slot-id').innerText = 'Slot #' + String(data.slot).slice(-6);

        if (data.slot !== currentSlot) {
          currentSlot = data.slot;
          renderQR(data.qr_string);
          playBeep();
          
          // Flash animation
          const card = document.getElementById('qr-card');
          card.classList.add('scale-105');
          setTimeout(() => card.classList.remove('scale-105'), 150);
        }
      } catch (e) {
        console.error('Fetch QR error:', e);
      }
    }

    function renderQR(text) {
      const container = document.getElementById('qrcode');
      container.innerHTML = '';
      qrcode = new QRCode(container, {
        text: text,
        width: 250,
        height: 250,
        colorDark: "#0f172a",
        colorLight: "#ffffff",
        correctLevel: QRCode.CorrectLevel.M
      });
    }

    // Dynamic 3-second cycle ticker
    function tick() {
      const now = new Date();
      document.getElementById('live-clock').innerText = now.toLocaleTimeString('en-IN', { hour12: true });

      const ms = now.getTime();
      const cycleMs = ms % 3000;
      const fraction = 1 - (cycleMs / 3000);
      const secsRemaining = ((3000 - cycleMs) / 1000).toFixed(1);

      document.getElementById('secs-text').innerText = secsRemaining + 's';
      document.getElementById('progress-bar').style.width = (fraction * 100) + '%';
    }

    // Initial fetch and intervals
    fetchQR();
    setInterval(fetchQR, 1000);
    setInterval(tick, 50);
  </script>
</body>
</html>
"""
