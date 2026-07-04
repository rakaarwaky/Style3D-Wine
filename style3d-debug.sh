#!/bin/bash
export WINEPREFIX="/home/raka/Applications/Wine/Style3D"
export WINEARCH="win64"
export WINEDEBUG=+loaddll,+seh,+msgbox

wine reg add "HKCU\\Software\\Wine\\AppDefaults\\Style3D.exe" /v Version /d win10 /f 2>/dev/null
wine reg add "HKCU\\Software\\Wine\\AppDefaults\\QtWebEngineProcess.exe" /v Version /d win10 /f 2>/dev/null

export SSL_CERT_FILE="/home/raka/Applications/Wine/ca-certificates.crt"
export WINEDLLOVERRIDES="secur32=builtin;bcp47langs=native"

export STAGING_WRITECOPY=1
export QTWEBENGINE_DISABLE_SANDBOX=1
export QTWEBENGINE_CHROMIUM_FLAGS="--no-sandbox --disable-gpu-sandbox --disable-namespace-sandbox --enable-logging --v=1"
export QTWEBENGINE_REMOTE_DEBUGGING=9999

killall -9 wineserver winedevice 2>/dev/null
sleep 1

echo "Wine: $(wine --version)"
echo "Logging enabled. Open webstore then check output."
echo "Remote debugging at http://localhost:9999"

wine explorer /desktop=Default,1920x1080 "C:\\Program Files\\Style3D\\Style3D.exe" 2>&1 | tee /tmp/style3d-debug.log
