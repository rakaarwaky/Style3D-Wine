#!/bin/bash
set -euo pipefail

STYLE3D_DIR="$(cd "$(dirname "$0")" && pwd)"
EXE="$STYLE3D_DIR/exe/Style3D_prod_2026-06-22_18-13-20_9030965.exe"
PREFIX="$STYLE3D_DIR/Style3D"
WINEARCH=win64

echo "=== Style3D Linux Auto-Installer ==="
echo ""

# 1. Check dependencies
echo "[1/7] Checking dependencies..."
for cmd in wine winetricks python3 curl unzip; do
    if ! command -v "$cmd" &>/dev/null; then
        # Try to install if missing
        if command -v dnf &>/dev/null; then
            echo "  Installing $cmd..."
            sudo dnf install -y "$cmd" 2>/dev/null || true
        fi
    fi
done
if ! command -v winetricks &>/dev/null; then
    echo "  Installing winetricks..."
    curl -Lo /tmp/winetricks https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks
    chmod +x /tmp/winetricks
    sudo cp /tmp/winetricks /usr/local/bin/winetricks
fi

# 2. Init prefix
echo "[2/7] Creating Wine prefix..."
WINEPREFIX="$PREFIX" WINEARCH=win64 wineboot --init 2>/dev/null

# 3. Install deps
echo "[3/7] Installing dependencies (vcrun2019, dotnet48, corefonts, d3dx9)..."
WINEPREFIX="$PREFIX" winetricks -q vcrun2019 dotnet48 corefonts d3dx9 2>/dev/null

# 4. Virtual desktop
echo "[4/7] Enabling virtual desktop..."
WINEPREFIX="$PREFIX" wine reg add "HKCU\\Software\\Wine\\Explorer\\Desktops" /v Default /t REG_SZ /d "1920x1080" /f 2>/dev/null

# 5. bcp47langs fix
echo "[5/7] Installing bcp47langs 32-bit DLL..."
BCP47_ZIP="$STYLE3D_DIR/BCP47Langs_x86.zip"
if [ -f "$BCP47_ZIP" ]; then
    unzip -o "$BCP47_ZIP" -d /tmp/bcp47_install/ BCP47Langs.dll 2>/dev/null
    SYSWOW64="$PREFIX/drive_c/windows/syswow64"
    STYLE3D_BIN="$PREFIX/drive_c/Program Files/Style3D"
    mkdir -p "$SYSWOW64" "$STYLE3D_BIN"
    cp /tmp/bcp47_install/BCP47Langs.dll "$SYSWOW64/bcp47langs.dll"
    cp /tmp/bcp47_install/BCP47Langs.dll "$STYLE3D_BIN/bcp47langs.dll"
    WINEPREFIX="$PREFIX" wine reg add "HKCU\\Software\\Wine\\DllOverrides" /v "bcp47langs" /t REG_SZ /d "" /f 2>/dev/null
    rm -rf /tmp/bcp47_install
    echo "  bcp47langs installed."
fi

# 6. Patch Qt6WebEngineCore
echo "[6/7] Patching Qt6WebEngineCore.dll (VirtualProtect WRITECOPY bug)..."
QT6CORE="$STYLE3D_BIN/Qt6WebEngineCore.dll"
if [ -f "$QT6CORE" ]; then
    python3 -c "
import struct
rva = 0x3d79301
with open('$QT6CORE', 'r+b') as f:
    import shutil
    shutil.copy2('$QT6CORE', '$QT6CORE.bak')
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
                print('  Patch OK: INT3 -> NOP at RVA 0x%08x' % rva)
            else:
                print('  Already patched or different byte: 0x%02x' % b[0])
            break
" 2>/dev/null || echo "  Patch skipped (DLL not found yet)"
fi

# 7. SSL certs
echo "[7/7] Setting up SSL certificates..."
if [ ! -f "$STYLE3D_DIR/ca-certificates.crt" ]; then
    cp /etc/ssl/certs/ca-certificates.crt "$STYLE3D_DIR/ca-certificates.crt" 2>/dev/null || true
fi

# Install Style3D
if [ -f "$EXE" ]; then
    echo ""
    echo "=== Running Style3D installer ==="
    echo "Please follow the installer GUI to complete installation."
    WINEPREFIX="$PREFIX" wine "$EXE"
else
    echo ""
    echo "=== Installer not found at: $EXE ==="
    echo "Please place Style3D_prod_*.exe in the exe/ directory and re-run this script."
fi

echo ""
echo "=== Done! ==="
echo "Run ./style3d.sh to launch Style3D."
