@echo off
mode con cp select=437 >nul

rem Disk partition resizing is intentionally disabled for safety.
rem Resize the system volume manually after confirming the correct disk.

rem ================== RDP & SECURITY PREP ==================
rem Password is provided by the installer; never set a blank password.
if defined PasRdp (
    net user Administrator "%PasRdp%"
    if errorlevel 1 echo [WARNING] Administrator password update failed.
) else (
    echo [WARNING] PasRdp missing. Existing Administrator password left unchanged.
)
rem Lock account temporarily after 5 failed sign-in attempts.
net accounts /lockoutthreshold:5
net accounts /lockoutduration:30
net accounts /lockoutwindow:30

rem ========= RENAME PC ke AVOLA-TECH =========
set "NEWNAME=AVOLA-TECH"
echo [i] Renaming computer to %NEWNAME% ...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
 "try { Rename-Computer -NewName '%NEWNAME%' -Force -ErrorAction Stop | Out-Null; exit 0 } catch { exit 1 }"
if errorlevel 1 (
  echo [!] PowerShell rename failed, trying WMIC fallback...
  wmic computersystem where name="%COMPUTERNAME%" call rename "%NEWNAME%" >nul 2>&1
)

rem ================== RDP PORT ==================
rem Preserve installer-provided port, defaulting to 3389.
if not defined RdpPort set "RdpPort=3389"
set "RdpPortValid="
for /f "delims=0123456789" %%a in ("%RdpPort%") do set "RdpPortValid=invalid"
if defined RdpPortValid set "RdpPort=3389"
if "%RdpPort%"=="22" (
    echo [WARNING] Port 22 conflicts with common SSH usage. Using 3389.
    set "RdpPort=3389"
)
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" /v PortNumber /t REG_DWORD /d %RdpPort% /f
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server" /v fDenyTSConnections /t REG_DWORD /d 0 /f
for %%a in (TCP UDP) do (
    netsh advfirewall firewall add rule name="Remote Desktop - Custom Port (%%a-In)" dir=in action=allow protocol=%%a localport=%RdpPort% >nul 2>&1
)

rem ================== Disable Sleep (Never) ==================
echo [i] Disabling automatic Sleep (AC & DC)...
powercfg -change -standby-timeout-ac 0
powercfg -change -standby-timeout-dc 0
rem Kalau mau sekalian matikan hibernate:
rem powercfg -hibernate off

rem ================== Restart Service RDP (jika ada) ==================
sc query TermService >nul 2>&1
if errorlevel 1 goto :do_reboot

set retryCount=5
:restartRDP
if %retryCount% LEQ 0 goto :do_reboot
net stop TermService /y && net start TermService || (
    set /a retryCount-=1
    timeout 10 >nul
    goto :restartRDP
)

:do_reboot
echo [i] Scheduling reboot to apply changes...
shutdown /r /t 5 /c "Applied: Rename=AVOLA-TECH, RDP Port=%RdpPort%, Sleep=Never"
rem Keep script for troubleshooting; do not self-delete.
