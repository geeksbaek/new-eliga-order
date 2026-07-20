---
name: ios-deploy
description: 엘리가오더 iOS 앱을 버전 범프 후 App Store Connect(TestFlight)에 아카이브·업로드한다. "iOS 앱 배포해", "TestFlight 올려줘", "앱스토어 커넥트에 업로드" 같은 요청에 사용한다.
---

# 엘리가오더 iOS 배포

`ios/scripts/deploy.sh`가 실제 배포 파이프라인이다. 이 스킬은 그 스크립트를 안전하게 실행하기 위한 절차와 주의사항을 담는다.

## 배경

- 이 저장소에는 fastlane이나 CI 기반 iOS 배포 워크플로우가 없다. 배포는 이 Mac에 로컬로 설치된
  Xcode와, Xcode에 로그인된 Apple ID(팀 `RCVFD6XLU9`, 엘리가)의 서명 권한을 그대로 사용하는
  로컬 `xcodebuild` 커맨드로 이루어진다.
- `ios/ExportOptions.plist`의 `destination: upload` 설정 덕분에 `xcodebuild -exportArchive`
  한 번으로 아카이브 익스포트와 App Store Connect 업로드가 동시에 끝난다. 별도의
  `altool`/`notarytool`/Transporter/fastlane이 필요 없다.
- API 키(.p8)나 앱 전용 암호는 쓰지 않는다. `signingStyle: automatic` + Xcode에 로그인된
  계정만으로 인증서/프로파일 취득과 업로드 인증이 모두 처리된다.

## 실행 전 확인

1. `git status`가 깨끗한지 확인한다 (스크립트가 release 커밋을 만들기 때문에 다른 변경사항과
   섞이면 안 된다). 배포하려는 변경사항은 이미 커밋되어 있어야 한다.
2. Xcode에 팀 `RCVFD6XLU9`로 서명 가능한 Apple ID가 로그인되어 있는지 확인한다.
   `security find-identity -v -p codesigning`으로 서명 아이덴티티 존재 여부는 확인할 수 있지만,
   실제로 해당 팀 권한이 있는지는 Xcode > Settings > Accounts를 사용자에게 직접 확인받는 게
   가장 확실하다. 로그인이 안 되어 있으면 사용자에게 로그인을 요청하고 기다린다 — 대신 로그인해줄
   수 없다.

## 실행

```sh
cd ios
scripts/deploy.sh patch   # major|minor|patch|build, 기본값 patch
```

스크립트가 하는 일 (`ios/scripts/deploy.sh` 참고):
1. `scripts/bump-version.sh <bump>`로 버전/빌드 번호 증가
2. `chore: release X.Y.Z` 커밋 생성 (**push는 하지 않음**)
3. `xcodebuild archive` (Release 설정)
4. `xcodebuild -exportArchive` — `ExportOptions.plist`의 upload 설정으로 App Store Connect에
   바로 업로드

## 안전 수칙 — 반드시 지킬 것

- **실제 업로드(3~4단계)는 되돌릴 수 없는 프로덕션 행위다.** TestFlight 빌드 번호는 재사용이
  불가능하고, 한 번 업로드되면 사용자/테스터에게 노출될 수 있다. 사용자가 이미 명시적으로
  "배포해"라고 요청한 경우가 아니라면, 실행 전에 반드시 사용자에게 최종 확인을 받는다.
- 이 스크립트는 **release 커밋을 로컬에만 만들고 push하지 않는다.** main으로의 push나 PR 머지는
  별도로 사용자에게 확인받고 진행한다 (백그라운드 세션에서는 정책상 자동으로 막힐 수 있다 —
  차단되면 우회하지 말고 사용자에게 알린다).
- 배포 중간에 실패하면(서명 오류, 네트워크 오류 등) 버전 범프 커밋만 로컬에 남고 업로드는
  일어나지 않는다. 재시도 전에 실패 원인을 사용자와 함께 확인한다.
- 빌드 번호를 건너뛰거나 두 번 쓰지 않도록, 배포 직전에 `git log`로 마지막 release 커밋을
  확인한다.
