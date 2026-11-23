@echo off
mode con cp select=437 >nul

echo Starting disk expansion process...
set C=%SystemDrive:~0,1%

rem Wait for disk services to be ready
echo Waiting for disk services...
timeout /t 10 /nobreak >nul

rem Method 1: Delete installer partition if it exists
echo Checking for installer partition...
for /f "tokens=2" %%a in ('echo list vol ^| diskpart ^| findstr "\<installer\>"') do (
    echo Found installer partition, deleting...
    (
        echo select vol %%a
        echo delete partition override
        echo exit
    ) | diskpart
    echo Installer partition deleted
)

rem Method 2: Find and delete any unallocated partitions or recovery partitions
echo Checking for recovery/unallocated partitions...
echo list disk > "%temp%\diskpart_list.txt"
echo list partition >> "%temp%\diskpart_list.txt"
echo exit >> "%temp%\diskpart_list.txt"

diskpart /s "%temp%\diskpart_list.txt" > "%temp%\disk_info.txt"

rem Find recovery partitions and delete them to free up space
for /f "tokens=2" %%a in ('type "%temp%\disk_info.txt" ^| findstr "Recovery"') do (
    echo Deleting recovery partition %%a...
    (
        echo select disk 0
        echo select partition %%a
        echo delete partition override
        echo exit
    ) | diskpart
)

rem Method 3: Create unallocated space by shrinking other partitions if needed
echo Checking for other partitions to shrink...
for /f "tokens=2,4" %%a in ('echo list vol ^| diskpart ^| findstr "NTFS" ^| findstr /v "\<%C%\>"') do (
    echo Found NTFS partition %%a, attempting to shrink...
    (
        echo select vol %%a
        echo shrink desired=5000 minimum=1000
        echo exit
    ) | diskpart
)

rem Method 4: Extend system partition with all available unallocated space
echo Extending system partition...
for /f "tokens=2" %%a in ('echo list vol ^| diskpart ^| findstr "\<%C%\>"') do (
    echo Extending volume %%a...
    (
        echo select vol %%a
        echo extend
        echo exit
    ) | diskpart
    if !errorlevel! equ 0 (
        echo Volume extended successfully
    ) else (
        echo Volume extension failed, trying partition method...
        goto :partition_method
    )
)
goto :cleanup

:partition_method
rem Alternative method: Use partition selection instead of volume
echo Trying partition-based extension...
(
    echo select disk 0
    echo list partition
) | diskpart > "%temp%\partitions.txt"

rem Find system partition (usually has Boot flag or contains system drive)
for /f "tokens=2,4,5" %%a in ('type "%temp%\partitions.txt" ^| findstr "Primary"') do (
    if "%%c"=="Boot" (
        echo Found boot partition %%a, extending...
        (
            echo select disk 0
            echo select partition %%a
            echo extend
            echo exit
        ) | diskpart
        goto :cleanup
    )
)

rem If no boot partition found, find the largest primary partition
for /f "tokens=2" %%a in ('type "%temp%\partitions.txt" ^| findstr "Primary" ^| findstr /v "Recovery"') do (
    echo Extending partition %%a...
    (
        echo select disk 0
        echo select partition %%a
        echo extend
        echo exit
    ) | diskpart
    goto :cleanup
)

:cleanup
rem Clean up temporary files
del "%temp%\diskpart_*.txt" 2>nul
del "%temp%\disk_info.txt" 2>nul
del "%temp%\partitions.txt" 2>nul

rem Show final disk status
echo.
echo === Final Disk Status ===
echo list vol | diskpart | findstr "%C%"
echo.

rem Method 5: Force extension if there's still unallocated space
echo Checking for remaining unallocated space...
(
    echo select disk 0
    echo list partition
) | diskpart | findstr "Free" >nul
if !errorlevel! equ 0 (
    echo Found free space, attempting final extension...
    for /f "tokens=2" %%a in ('echo list vol ^| diskpart ^| findstr "\<%C%\>"') do (
        (
            echo select disk 0
            echo select vol %%a
            echo extend
            echo exit
        ) | diskpart
    )
)

echo Disk expansion completed.

rem Self-delete
del "%~f0" 2>nul
