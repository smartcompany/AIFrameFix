#!/usr/bin/env bash
# Universal Purchase 빌드: iOS와 macOS를 모두 빌드 및 업로드
# 같은 Bundle ID로 Universal Purchase 자동 설정됨

set -euo pipefail

# -------- Args --------
BUMP=false
IOS_ONLY=false
MACOS_ONLY=false
PROJECT_DIR="$(pwd)"

for arg in "$@"; do
  case "$arg" in
    -b|--bump) BUMP=true ;;
    --ios-only) IOS_ONLY=true ;;
    --macos-only) MACOS_ONLY=true ;;
    *) PROJECT_DIR="$arg" ;;
  esac
done

log()  { printf "\n\033[1;34m[Universal Purchase]\033[0m %s\n" "$*"; }
fail() { printf "\n\033[1;31m[error]\033[0m %s\n" "$*" >&2; exit 1; }

# -------- Checks --------
command -v flutter >/dev/null  || fail "Flutter가 PATH에 없음"
command -v fastlane >/dev/null || fail "fastlane이 설치 안됨 (gem install fastlane)"

cd "$PROJECT_DIR" || fail "프로젝트 경로 진입 실패: $PROJECT_DIR"
[ -f pubspec.yaml ] || fail "pubspec.yaml 없음 (Flutter 프로젝트 루트인지 확인)"

# -------- Optional: bump version patch --------
if $BUMP; then
  CURRENT_VERSION=$(grep '^version:' pubspec.yaml | awk '{print $2}')
  [ -n "$CURRENT_VERSION" ] || fail "pubspec.yaml에서 version을 찾지 못함"

  BASE_VERSION=${CURRENT_VERSION%%+*}  # 1.0.3
  BUILD_NUMBER=""
  if [[ "$CURRENT_VERSION" == *"+"* ]]; then
    BUILD_NUMBER="${CURRENT_VERSION#*+}"  # 15
  fi

  IFS='.' read -r MAJOR MINOR PATCH <<<"$BASE_VERSION"
  PATCH=$((PATCH + 1))
  NEW_VERSION="${MAJOR}.${MINOR}.${PATCH}"
  if [ -n "$BUILD_NUMBER" ]; then
    NEW_VERSION="${NEW_VERSION}+${BUILD_NUMBER}"
  fi

  log "버전 패치 증가: $CURRENT_VERSION → $NEW_VERSION"

  # macOS(BSD)와 GNU sed 모두 대응
  if sed --version >/dev/null 2>&1; then
    # GNU sed
    sed -i "s/^version: .*/version: ${NEW_VERSION}/" pubspec.yaml
  else
    # BSD sed (macOS)
    sed -i '' "s/^version: .*/version: ${NEW_VERSION}/" pubspec.yaml
  fi
else
  log "버전 증가는 건너뜀 (옵션 미지정)"
fi

# -------- iOS 빌드 및 업로드 --------
if ! $MACOS_ONLY; then
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  log "📱 iOS 빌드 시작"
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  
  [ -d ios ] || fail "ios 폴더 없음"
  
  log "flutter build ios --config-only --release"
  flutter build ios --config-only --release
  
  cd ios || fail "ios 폴더 이동 실패"
  if [ -f Gemfile ]; then
    log "bundle exec fastlane release"
    bundle exec fastlane release
  else
    log "fastlane release"
    fastlane release
  fi
  
  cd "$PROJECT_DIR" || fail "프로젝트 루트로 복귀 실패"
  log "✅ iOS 빌드 및 업로드 완료"
else
  log "⏭️  iOS 빌드 건너뜀 (--macos-only 옵션)"
fi

# -------- macOS 빌드 및 업로드 --------
if ! $IOS_ONLY; then
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  log "💻 macOS 빌드 시작"
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  
  [ -d macos ] || fail "macos 폴더 없음"
  
  log "flutter build macos --config-only --release"
  flutter build macos --config-only --release
  
  cd macos || fail "macos 폴더 이동 실패"
  if [ -f Gemfile ]; then
    log "bundle exec fastlane release"
    bundle exec fastlane release
  else
    log "fastlane release"
    fastlane release
  fi
  
  cd "$PROJECT_DIR" || fail "프로젝트 루트로 복귀 실패"
  log "✅ macOS 빌드 및 업로드 완료"
else
  log "⏭️  macOS 빌드 건너뜀 (--ios-only 옵션)"
fi

log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "🎉 Universal Purchase 빌드 완료!"
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "📝 참고: 같은 Bundle ID (com.smartcompany.aiFrameFix)로"
log "   App Store Connect에서 자동으로 Universal Purchase가 설정됩니다."
log "   사용자는 한 번 구매로 iOS와 macOS에서 모두 사용할 수 있습니다."

