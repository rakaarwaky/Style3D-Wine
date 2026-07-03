# Panduan Install Style3D via Wine (Linux)

## Spesifikasi
- **OS**: Fedora 44
- **Wine**: 11.12 (winehq-devel)
- **Winetricks**: 20260125
- **Style3D**: Style3D_prod_2026-06-22_18-13-20_9030965
- **Repo**: https://github.com/rakaarwaky/Style3D-Wine

## Struktur Direktori
```
/home/raka/App/Wine/
├── Style3D/                          # Wine prefix
│   ├── drive_c/                      # Drive C: Windows
│   │   ├── Program Files/Style3D/    # Instalasi Style3D
│   │   └── users/raka/              # User profile
│   ├── dosdevices/                   # Drive mapping
│   └── system.reg                    # Registry Windows
├── exe/
│   └── Style3D_prod_2026-06-22_18-13-20_9030965.exe  # Installer
├── ca-certificates.crt               # SSL certificates
└── style3d.sh                        # Script launcher
```

## Langkah Instalasi

### 1. Buat Wine Prefix Baru
```bash
WINEPREFIX=/home/raka/App/Wine/Style3D WINEARCH=win64 wineboot --init
```

### 2. Install Winetricks (Manual)
```bash
# Download winetricks
curl -L -o /tmp/winetricks https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks

# Install ke /usr/local/bin
sudo install -m 755 /tmp/winetricks /usr/local/bin/winetricks
```

> **Catatan**: Winetricks tidak bisa diinstall via dnf karena conflict dengan winehq-devel.

### 3. Install Dependencies
```bash
# Visual C++ Runtime 2019
WINEPREFIX=/home/raka/App/Wine/Style3D winetricks vcrun2019

# .NET Framework 4.8, Fonts, DirectX 9
WINEPREFIX=/home/raka/App/Wine/Style3D winetricks dotnet48 corefonts d3dx9
```

### 4. Enable Virtual Desktop
```bash
WINEPREFIX=/home/raka/App/Wine/Style3D wine reg add \
  "HKCU\Software\Wine\Explorer\Desktops" \
  /v Default /t REG_SZ /d "1920x1080" /f
```

### 5. Copy SSL Certificates
```bash
cp /etc/ssl/certs/ca-certificates.crt /home/raka/App/Wine/ca-certificates.crt
```

### 6. Fix bcp47langs.dll (32-bit untuk QtWebEngine)
```bash
# Download bcp47langs.dll 32-bit dari GitHub release
# Copy ke syswow64 dan direktori Style3D
SYSWOW64="/home/raka/App/Wine/Style3D/drive_c/windows/syswow64"
STYLE3D_DIR="/home/raka/App/Wine/Style3D/drive_c/Program Files/Style3D"
cp /path/to/bcp47langs_32bit.dll "$SYSWOW64/bcp47langs.dll"
cp /path/to/bcp47langs_32bit.dll "$STYLE3D_DIR/bcp47langs.dll"

# Registry override
WINEPREFIX=/home/raka/App/Wine/Style3D wine reg add \
  "HKCU\\Software\\Wine\\DllOverrides" /v "bcp47langs" /t REG_SZ /d "" /f
```

### 7. Patch Qt6WebEngineCore.dll (fix VirtualProtect WRITECOPY bug)
Wine bug: `VirtualProtect` returns `WRITECOPY (0x08)` instead of `READWRITE (0x04)`, causing Chromium/V8 `CHECK()` crash (`int3`).

```bash
python3 << 'PYEOF'
import struct
dll = "/home/raka/App/Wine/Style3D/drive_c/Program Files/Style3D/Qt6WebEngineCore.dll"
crash_rva = 0x3d79301

# Backup
import shutil
shutil.copy2(dll, dll + ".bak")

with open(dll, 'r+b') as f:
    dos = f.read(64)
    pe_off = struct.unpack('<I', dos[0x3c:0x40])[0]
    f.seek(pe_off + 24 + 240)  # section headers
    for i in range(9):
        name = f.read(8).rstrip(b'\x00').decode('ascii', errors='replace')
        vsize = struct.unpack('<I', f.read(4))[0]
        vrva = struct.unpack('<I', f.read(4))[0]
        rsize = struct.unpack('<I', f.read(4))[0]
        roffset = struct.unpack('<I', f.read(4))[0]
        f.read(20)
        if vrva <= crash_rva < vrva + vsize:
            file_off = crash_rva - vrva + roffset
            f.seek(file_off)
            assert f.read(1)[0] == 0xcc, "Expected INT3"
            f.seek(file_off)
            f.write(b'\x90')  # NOP
            print(f"Patched INT3 at RVA 0x{crash_rva:08x} to NOP")
            break
PYEOF
```

### 8. Jalankan Installer
```bash
WINEPREFIX=/home/raka/App/Wine/Style3D wine \
  "/home/raka/App/Wine/exe/Style3D_prod_2026-06-22_18-13-20_9030965.exe"
```

## Script Launcher (style3d.sh)
```bash
#!/bin/bash
export WINEPREFIX="/home/raka/App/Wine/Style3D"
export WINEARCH="win64"
export WINEDEBUG=-all

# Set Windows version to 10 per-app (required by modern QtWebEngine)
wine reg add "HKCU\\Software\\Wine\\AppDefaults\\Style3D.exe" /v Version /d win10 /f 2>/dev/null
wine reg add "HKCU\\Software\\Wine\\AppDefaults\\QtWebEngineProcess.exe" /v Version /d win10 /f 2>/dev/null

# bcp47langs override (perlu native 32-bit DLL)
export WINEDLLOVERRIDES="secur32=builtin;bcp47langs=native"

# SSL certificates
CA_CERT_PATH="/home/raka/App/Wine/ca-certificates.crt"
if [ ! -f "$CA_CERT_PATH" ]; then
    cp /etc/ssl/certs/ca-certificates.crt "$CA_CERT_PATH" 2>/dev/null
fi
export SSL_CERT_FILE="$CA_CERT_PATH"

# Staging writecopy for QtWebEngine
export STAGING_WRITECOPY=1

# Disable Qt WebEngine sandbox & GPU
export QTWEBENGINE_DISABLE_SANDBOX=1
export QTWEBENGINE_CHROMIUM_FLAGS="--no-sandbox --disable-gpu-sandbox --disable-namespace-sandbox --disable-gpu --disable-gpu-compositing"

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
```

### Auto-Install (1-klik)
```bash
# 1. Clone repo
git clone https://github.com/rakaarwaky/Style3D-Wine.git
cd Style3D-Wine

# 2. Taruh installer .exe di folder exe/
#    (download dari website Style3D)

# 3. Jalankan auto-installer
./install.sh

# 4. Jalankan Style3D
./style3d.sh
```

### Manual Steps
(Lihat langkah 1-8 di atas jika auto-installer gagal.)

### Jalankan Style3D
```bash
cd /home/raka/App/Wine
./style3d.sh
```

## Troubleshooting

### Wine Gagal Start
```bash
killall -9 wineserver winedevice
WINEPREFIX=/home/raka/App/Wine/Style3D wineboot --fixme
```

### Reset Style3D Preferences
```bash
rm -rf "/home/raka/App/Wine/Style3D/drive_c/users/raka/AppData/Local/Style3D/Preference"
```

### Uninstall Style3D
```bash
rm -rf /home/raka/App/Wine/Style3D
```

### Re-patch Qt6WebEngineCore.dll (setelah update Style3D)
```bash
python3 << 'PYEOF'
import struct, shutil
dll = "/home/raka/App/Wine/Style3D/drive_c/Program Files/Style3D/Qt6WebEngineCore.dll"
crash_rva = 0x3d79301
shutil.copy2(dll, dll + ".bak")
with open(dll, 'r+b') as f:
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
        if vrva <= crash_rva < vrva + vsize:
            file_off = crash_rva - vrva + roffset
            f.seek(file_off)
            b = f.read(1)
            if b[0] == 0xcc:
                f.seek(file_off)
                f.write(b'\x90')
                print(f"Patched INT3 at RVA 0x{crash_rva:08x}")
            else:
                print(f"Byte at offset bukan INT3: 0x{b[0]:02x}, cari crash RVA baru")
            break
PYEOF
```

> **Catatan**: Setiap Style3D update, `Qt6WebEngineCore.dll` mungkin berubah dan patch perlu diulang. Cek crash address dari error log terbaru jika offset `0x3d79301` berubah.

### Re-install bcp47langs.dll (setelah update Style3D)
```bash
SYSWOW64="/home/raka/App/Wine/Style3D/drive_c/windows/syswow64"
STYLE3D_DIR="/home/raka/App/Wine/Style3D/drive_c/Program Files/Style3D"
cp /home/raka/App/Wine/BCP47Langs_x86.zip /tmp/
unzip -o /tmp/BCP47Langs_x86.zip -d /tmp/bcp47/ BCP47Langs.dll
cp /tmp/bcp47/BCP47Langs.dll "$SYSWOW64/bcp47langs.dll"
cp /tmp/bcp47/BCP47Langs.dll "$STYLE3D_DIR/bcp47langs.dll"
WINEPREFIX=/home/raka/App/Wine/Style3D wine reg add \
  "HKCU\\Software\\Wine\\DllOverrides" /v "bcp47langs" /t REG_SZ /d "" /f
```

### Cek Wine Version
```bash
wine --version
WINEPREFIX=/home/raka/App/Wine/Style3D wine cmd /c echo %WINEPREFIX%
```

## Environment Variables Penting
| Variable | Value | Fungsi |
|----------|-------|--------|
| `WINEPREFIX` | `/home/raka/App/Wine/Style3D` | Wine prefix location |
| `WINEARCH` | `win64` | Arsitektur Windows |
| `WINEDEBUG` | `-all` | Disable debug logs |
| `STAGING_WRITECOPY` | `1` | Fix QtWebEngine crash |
| `QTWEBENGINE_DISABLE_SANDBOX` | `1` | Disable Chromium sandbox |
| `WINEDLLOVERRIDES` | `dwrite=b;secur32=builtin;crypt32=builtin;bcp47langs=native` | DLL override settings |
| `SSL_CERT_FILE` | `/home/raka/App/Wine/ca-certificates.crt` | SSL certificates |
