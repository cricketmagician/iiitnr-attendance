import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

print("[1] Importing app.main...", flush=True)
from app.main import app
print("[2] app.main imported successfully!", flush=True)

import uvicorn

if __name__ == "__main__":
    print("[3] Starting uvicorn on http://0.0.0.0:8040...", flush=True)
    uvicorn.run(app, host="0.0.0.0", port=8040, log_level="info")
