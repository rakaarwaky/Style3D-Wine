#!/bin/bash
echo "Killing all Style3D/Wine processes..."
killall -9 wineserver winedevice CrashServer explorer.exe Style3D.exe QtWebEngineProcess \
  services.exe svchost.exe mscorsvw.exe plugplay.exe rpcss.exe 2>/dev/null
ps aux | grep "C:\\\\windows" | grep -v grep | awk '{print $2}' | xargs -r kill -9 2>/dev/null
wineserver -k 2>/dev/null
echo "Done."
