#!/bin/bash
# ═══════════════════════════════════════════════════
# CHEONHONG STUDIO — Firebase App Distribution Deploy
# Usage: bash deploy.sh "릴리스 노트 메시지"
# ═══════════════════════════════════════════════════

set -e

APP_ID="1:241623003531:android:b27e90816d5c2ba832ff8e"
APK_PATH="build/app/outputs/flutter-apk/app-release.apk"
NOTES="${1:-빌드 업데이트}"

echo "▶ Flutter 빌드 시작..."
flutter build apk --release

echo "▶ Firebase App Distribution 배포..."
firebase appdistribution:distribute "$APK_PATH" \
  --app "$APP_ID" \
  --release-notes "$NOTES" \
  --groups "테스터"

echo "✓ 배포 완료!"
