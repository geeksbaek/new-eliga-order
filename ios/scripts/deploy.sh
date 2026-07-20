#!/bin/zsh
#
# 엘리가오더 iOS App Store Connect 배포.
# bump-version.sh로 버전을 올리고, Release 아카이브를 만들어
# ExportOptions.plist(destination: upload)로 App Store Connect에 바로 업로드한다.
#
# 사용법: scripts/deploy.sh [major|minor|patch|build]  (기본값: patch)
#
# 사전 조건:
#   - Xcode에 팀 RCVFD6XLU9(엘리가) 서명 권한이 있는 Apple ID가 로그인되어 있어야 한다.
#     (Xcode > Settings > Accounts)
#   - signingStyle이 automatic이므로 인증서/프로파일은 Xcode가 자동으로 처리한다.
#   - 별도의 API 키, 앱 전용 암호, fastlane 설정이 필요 없다.

set -euo pipefail

script_dir=${0:A:h}
ios_dir=${script_dir:h}
bump=${1:-patch}

cd "$ios_dir"

if [[ -n "$(git status --porcelain)" ]]; then
  print -u2 "커밋되지 않은 변경사항이 있습니다. 먼저 커밋하거나 정리하세요."
  git status --short >&2
  exit 1
fi

print "1/4 버전 범프 ($bump)"
zsh scripts/bump-version.sh "$bump"

version=$(sed -n 's/.*MARKETING_VERSION = \([^;]*\);.*/\1/p' NewEligaOrder.xcodeproj/project.pbxproj | head -1)
build=$(sed -n 's/.*CURRENT_PROJECT_VERSION = \([^;]*\);.*/\1/p' NewEligaOrder.xcodeproj/project.pbxproj | head -1)

git add project.yml NewEligaOrder.xcodeproj/project.pbxproj
git commit -m "chore: release $version"

work_dir=$(mktemp -d)
archive_path="$work_dir/NewEligaOrder.xcarchive"
export_path="$work_dir/export"
trap 'rm -rf "$work_dir"' EXIT

print "2/4 아카이브 생성 ($version ($build))"
xcodebuild archive \
  -project NewEligaOrder.xcodeproj \
  -scheme NewEligaOrder \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -archivePath "$archive_path"

print "3/4 App Store Connect 업로드"
xcodebuild -exportArchive \
  -archivePath "$archive_path" \
  -exportPath "$export_path" \
  -exportOptionsPlist ExportOptions.plist

print "4/4 완료: $version ($build) 업로드됨. release 커밋은 로컬에만 있습니다 — 직접 push 여부를 확인하세요."
git log -1 --oneline
