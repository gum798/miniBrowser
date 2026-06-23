# miniBrowser

macOS에서 도는 **아이폰 Safari 스타일 미니 브라우저**. 폰 크기 창 + 모바일 레이아웃 + 관성 스크롤로, 데스크탑에서 모바일 웹을 보는 경험을 제공합니다.

> **상태: v1 구현 완료** — 코어 로직(주소 판별·즐겨찾기·기록·탭 상태)은 유닛 테스트로 검증, 앱 UI는 SwiftUI + WKWebView로 동작합니다.

## 스택

- Swift 6.3 / SwiftUI / WKWebView (WebKit = Safari와 동일 렌더링 엔진)
- **Swift Package** 로 빌드·실행 (Xcode 프로젝트 없음)
- 대상: macOS 26 (Apple Silicon)

## 빌드 / 실행

```bash
./scripts/run.sh         # 개발용: swift build → .build/miniBrowser.app 로 래핑 → 실행
./scripts/build-app.sh   # 릴리즈 빌드 → 아이콘·서명된 miniBrowser.app → /Applications 설치
swift test               # 코어 유닛 테스트 (MiniBrowserCore)
```

설치 후에는 Spotlight·Launchpad·Dock에서 일반 앱처럼 실행합니다(`open -a miniBrowser`). `build-app.sh --no-install`은 설치 없이 `dist/miniBrowser.app`만 만듭니다. 데이터(즐겨찾기·기록)는 설치 위치와 무관하게 `~/Library/Application Support/miniBrowser/`에 저장됩니다.

> **`swift run`을 직접 쓰지 마세요.** 번들 메타데이터가 없는 bare 실행은 WKWebView의 WebContent 프로세스 기동이 실패해 빈 화면이 될 수 있습니다(검증됨). 반드시 `scripts/run.sh`로 `.app` 번들(`CFBundleIdentifier`/`CFBundleDisplayName` 포함)을 거쳐 실행합니다.

## v1 범위

**포함**

- 주소창 (URL / 검색어 자동 판별 — 기본 Google), 페이지 로드, 뒤로·앞으로·새로고침
- 폰 크기(기본 390×844pt, 최소 320×480pt부터 자유 리사이즈) 창 + 모바일 User-Agent (사이트가 모바일 레이아웃으로 렌더링)
- 관성(momentum) 터치 스크롤 (WKWebView 기본)
- 탭 (아이폰풍 탭 스위처, `target=_blank`/`window.open` → 새 탭)
- 즐겨찾기 + 새 탭 시작화면(즐겨찾기 그리드 + 최근 방문)
- 방문 기록(History) + 주소창 자동완성
- 페이지 로드 실패 시 인라인 에러 + 재시도

## 아키텍처

상태/로직은 WebKit·UI 의존 없이 `MiniBrowserCore` 라이브러리로 분리해 유닛 테스트로 검증합니다. 앱(`MiniBrowserApp`)은 얇은 SwiftUI 셸입니다.

- **MiniBrowserCore (라이브러리, 테스트 대상)**
  - `URLResolver` / `SearchEngine` — 입력 문자열 → URL 이동 / 검색 판별 (순수 함수)
  - `BookmarkStore` (+ `Bookmark`) — 즐겨찾기 CRUD + JSON 영속화
  - `HistoryStore` (+ `HistoryEntry`) — 방문 기록 추가/조회/자동완성
  - `TabsState` — 탭 컬렉션 상태기계 (열기/닫기/선택/이동 불변식)
  - `MobileUserAgent` — iPhone Safari UA 상수
- **MiniBrowserApp (실행 파일, SwiftUI)**
  - `Tab` / `TabsModel` — `@MainActor`, 탭마다 `WKWebView`를 영구 소유(상태 유지)
  - `WebView` — `NSViewRepresentable` + Coordinator (활성 탭 web view 스왑, 네비게이션/새 탭/에러 처리)
  - `AddressBar` / `BottomToolbar` / `TabSwitcherView` / `StartPageView` / `BrowserView`

영속화 위치: `~/Library/Application Support/miniBrowser/` (`bookmarks.json`, `history.json`).

## v1 제외 / 추후(deferred)

- **암호 AutoFill / 패스키** — 서드파티 WKWebView 브라우저는 iCloud 키체인 완전 호환이 Apple의 제한된 엔타이틀먼트(`com.apple.developer.web-browser.public-key-credential`) 심사를 받아야 가능해 v1 제외.
- **탭/즐겨찾기 드래그 재정렬 UI** — 재정렬 로직(`TabsState.move` / `BookmarkStore.move`)은 구현·테스트되어 있으나 드래그 UI는 아직 연결하지 않음(추후).
- **다중 윈도우/실시간 스토어 갱신** — 단일 윈도우 기준. 시작화면 즐겨찾기는 토글 시 갱신되며, 다중 윈도우 동기화는 추후(스토어를 `ObservableObject`로 승격 검토).
- 당겨서 새로고침, 프라이빗 모드, 리더 모드, 배포용 서명/노터라이즈.

## 설계 문서

- 설계 스펙: `docs/superpowers/specs/2026-06-22-minibrowser-design.md`
- 구현 계획: `docs/superpowers/plans/2026-06-22-minibrowser.md`
