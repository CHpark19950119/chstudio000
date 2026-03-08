$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
$token = "8514127849:AAF8_F7SBfm51SGHtp9X5lva7yexdnFyapo"
$chatId = "8724548311"
$apk = "build\app\outputs\flutter-apk\app-debug.apk"
$pkg = "com.cheonhong.cheonhong_studio"

Set-Location "C:\dev\CHSTUDIO"
New-Item -ItemType Directory -Path "test_results" -Force | Out-Null

$devices = @(& $adb devices | Select-String "device$" | ForEach-Object { ($_ -split "\s+")[0] })
$dev = $null
foreach ($d in $devices) {
    if ($d -notmatch "emulator") { $dev = $d; break }
}
if (-not $dev -and $devices) { $dev = $devices[0] }
if (-not $dev) {
    Write-Host "ERROR: no device"
    exit 1
}
Write-Host "Device: $dev"

Write-Host "Building..."
flutter build apk --debug
if ($LASTEXITCODE -ne 0) {
    curl.exe -s -F "chat_id=$chatId" -F "text=CHSTUDIO build failed" "https://api.telegram.org/bot$token/sendMessage"
    exit 1
}

Write-Host "Installing..."
& $adb -s $dev install -r $apk

& $adb -s $dev shell am force-stop $pkg
Start-Sleep -Seconds 2
& $adb -s $dev logcat -c
& $adb -s $dev shell monkey -p $pkg -c android.intent.category.LAUNCHER 1
Write-Host "Waiting 20s..."
Start-Sleep -Seconds 20

& $adb -s $dev logcat -d -s flutter > test_results\logcat.txt

& $adb -s $dev shell screencap -p /sdcard/test.png
& $adb -s $dev pull /sdcard/test.png test_results\latest.png

$log = Get-Content test_results\logcat.txt
$errors = $log | Select-String "error|FAIL|timeout" | Where-Object { $_ -notmatch "emuglConfig|vulkan|swiftshader|Impeller" }
$success = $log | Select-String "OK|study doc|KB"

Write-Host ""
Write-Host "===== RESULT ====="
Write-Host "Pass: $($success.Count)"
Write-Host "Error: $($errors.Count)"

if ($errors.Count -gt 0) {
    Write-Host "--- errors ---"
    $errors | ForEach-Object { Write-Host $_.Line }
}

if ($errors.Count -gt 3) {
    curl.exe -s -F "chat_id=$chatId" -F "text=CHSTUDIO test errors: $($errors.Count)" "https://api.telegram.org/bot$token/sendMessage"
    exit 1
}

Write-Host "Sending to Telegram..."
$apkSize = (Get-Item $apk).Length / 1MB
$resultText = "CHSTUDIO OK (pass:$($success.Count) err:$($errors.Count) dev:$dev)"

if ($apkSize -lt 50) {
    curl.exe -s -F "chat_id=$chatId" -F "document=@$apk" -F "caption=$resultText" "https://api.telegram.org/bot$token/sendDocument"
} else {
    $sizeRound = [math]::Round($apkSize, 1)
    Write-Host "APK ${sizeRound}MB > 50MB limit, text only"
    curl.exe -s -F "chat_id=$chatId" -F "text=$resultText (APK ${sizeRound}MB)" "https://api.telegram.org/bot$token/sendMessage"
}

if (Test-Path test_results\latest.png) {
    curl.exe -s -F "chat_id=$chatId" -F "photo=@test_results\latest.png" -F "caption=screenshot" "https://api.telegram.org/bot$token/sendPhoto"
}

Write-Host "Deploy done\!"