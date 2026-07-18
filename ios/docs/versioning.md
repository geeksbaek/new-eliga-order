# iOS 버전 정책

엘리가오더는 `MAJOR.MINOR.PATCH (BUILD)` 형식을 사용한다.

- `major`: 호환되지 않는 대규모 변경
- `minor`: 사용자가 확인할 수 있는 새 기능
- `patch`: 버그 수정과 작은 UI 개선
- `build`: 동일한 앱 버전의 재업로드

버전은 앱과 위젯에서 항상 같아야 한다. 직접 여러 파일을 편집하지 말고 다음 명령을 사용한다.

```sh
ios/scripts/bump-version.sh minor
```

명령을 실행할 때마다 빌드 번호는 한 번 증가한다. TestFlight에 업로드한 빌드 번호는 다시 사용할 수 없다.
