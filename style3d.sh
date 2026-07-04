#!/bin/bash
export WINEPREFIX="/home/raka/Applications/Wine/Style3D"
export WINEARCH="win64"
export WINEDEBUG=-all

# Set Windows version to 10 per-app (required by modern QtWebEngine)
wine reg add "HKCU\\Software\\Wine\\AppDefaults\\Style3D.exe" /v Version /d win10 /f 2>/dev/null
wine reg add "HKCU\\Software\\Wine\\AppDefaults\\QtWebEngineProcess.exe" /v Version /d win10 /f 2>/dev/null

# bcp47langs override (perlu native 32-bit DLL)
# WINEDLLOVERRIDES will be set fully below (line 50)

# Auto-patch Qt6WebEngineCore.dll INT3 crash (VirtualProtect WRITECOPY bug)
QT6CORE="$WINEPREFIX/drive_c/Program Files/Style3D/Qt6WebEngineCore.dll"
if [ -f "$QT6CORE" ]; then
    python3 -c "
import struct
rva = 0x3d79301
with open('$QT6CORE', 'r+b') as f:
    dos = f.read(64)
    pe_off = struct.unpack('<I', dos[0x3c:0x40])[0]
    f.seek(pe_off + 24 + 240)
    for i in range(9):
        name = f.read(8).rstrip(b'\x00').decode('ascii', errors='replace')
        vsize = struct.unpack('<I', f.read(4))[0]
        vrva = struct.unpack('<I', f.read(4))[0]
        rsize = struct.unpack('<I', f.read(4))[0]
        roffset = struct.unpack('<I', f.read(4))[0]
        f.read(20)
        if vrva <= rva < vrva + vsize:
            off = rva - vrva + roffset
            f.seek(off)
            b = f.read(1)
            if b[0] == 0xcc:
                f.seek(off)
                f.write(b'\x90')
                print('Patch OK')
            break
" 2>/dev/null || true
fi

# SSL certificates
CA_CERT_PATH="/home/raka/Applications/Wine/ca-certificates.crt"
if [ ! -f "$CA_CERT_PATH" ]; then
    cp /etc/ssl/certs/ca-certificates.crt "$CA_CERT_PATH" 2>/dev/null
fi
export SSL_CERT_FILE="$CA_CERT_PATH"

# DLL overrides (biarkan dwrite default biar fallback ke builtin Wine)
export WINEDLLOVERRIDES="secur32=builtin;bcp47langs=native"

# Staging writecopy for QtWebEngine
export STAGING_WRITECOPY=1

# Disable Qt WebEngine sandbox & use ANGLE (D3D11 → OpenGL wrapper)
export QTWEBENGINE_DISABLE_SANDBOX=1
export QTWEBENGINE_CHROMIUM_FLAGS="--no-sandbox --disable-gpu-sandbox --disable-namespace-sandbox --disable-software-rasterizer --use-gl=angle --use-angle=d3d11"

# Reset autosave to bypass "Abnormal Close" dialog
AUTOSAVE_JSON="$WINEPREFIX/drive_c/users/raka/AppData/Local/Style3D/Preference/projectAutoSaveInfos.json"
if [ -f "$AUTOSAVE_JSON" ]; then
    python3 -c "
import json
try:
    with open('$AUTOSAVE_JSON', 'r') as f:
        data = json.load(f)
    data['autoSaveInfos'] = []
    data['normalClose'] = True
    with open('$AUTOSAVE_JSON', 'w') as f:
        json.dump(data, f, indent=4)
except Exception:
    pass
" 2>/dev/null
fi

# Kill old wineserver
killall -9 wineserver winedevice 2>/dev/null
sleep 2

echo "Wine: $(wine --version)"
echo "Starting Style3D..."

DISPLAY=:0 wine explorer /desktop=Default,1920x1080 "C:\\Program Files\\Style3D\\Style3D.exe" &
echo "PID: $!"
sleep 25
echo "Done."
