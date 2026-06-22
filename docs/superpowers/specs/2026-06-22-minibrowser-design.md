# miniBrowser 설계 문서 (v1)

- 작성일: 2026-06-22
- 상태: 설계 확정 단계 (구현 전)
- 저장소: https://github.com/gum798/miniBrowser

---

## 1. 개요

macOS에서 도는 **아이폰 Safari 스타일 미니 브라우저**. 폰 크기 창, 모바일 레이아웃,
관성(touch) 스크롤로 데스크탑에서 모바일 웹을 보는 경험을 제공한다.

- **스택**: Swift 6.3 / SwiftUI / WKWebView (WebKit = Safari와 동일 렌더링 엔진)
- **빌드**: Swift Package, `swift run` / `swift test` (Xcode 프로젝트 없음)
- **대상**: macOS 26 (Apple Silicon), 개발/개인 사용 목적

### 목표 (Goals)
- 아이폰 Safari처럼 보이고 조작되는 브라우저 (모바일 레이아웃 + 관성 스크롤).
- 탭, 즐겨찾기/시작화면, 방문기록을 갖춘 실사용 가능한 미니 브라우저.
- 순수 로직은 WebKit·UI 의존 없이 분리하여 `swift test`로 검증.

### 비목표 (Non-Goals) — v1 제외, 확장 지점만 남김
- **암호 AutoFill / 패스키** — 서드파티 WKWebView 브라우저는 iCloud 키체인 완전 호환이
  Apple의 제한된 엔타이틀먼트(`com.apple.developer.web-browser.public-key-credential`)
  심사를 받아야 가능. 미니 프로젝트 범위 밖이라 v1 제외. (향후 별도 단계)
- 당겨서 새로고침, 프라이빗 모드, 리더 모드, 확장 프로그램, 동기화, 다운로드 관리자.
- 배포 가능한 서명/노터라이즈된 `.app` 패키징 (개발 실행에 집중).

---

## 2. 기반 검증 결과 (반드시 코드에 반영)

> 사전에 병렬 리서치로 SPM + SwiftUI + WKWebView 토대를 검증했다. 결론: **실현 가능(go-with-changes)**.
> 아래 4가지는 "선택"이 아니라 동작을 위한 **필수 제약**이다.

### G1. 활성화 정책 부트스트랩 (필수)
`swift run`은 `.app` 번들/Info.plist 없이 bare 바이너리를 띄우므로 프로세스가 `.regular`가
아닌 background 상태로 시작한다. 그대로 두면 Dock 아이콘 없음, 윈도우가 뒤로 감,
**키보드 포커스 불가(주소창/검색 입력이 죽음)**, 메뉴바 없어 Cmd-Q가 터미널을 종료한다.

App `init()`에서 main 큐로 디스패치하여 처리한다:
```swift
DispatchQueue.main.async {
    NSApp.setActivationPolicy(.regular)             // Dock 아이콘 + 실제 메뉴
    NSApp.activate()                                 // Swift 6.3: ignoringOtherApps: 는 deprecated
    NSApp.windows.first?.makeKeyAndOrderFront(nil)   // frontmost + 키보드 포커스
}
```
첫 실행 시 윈도우가 아직 `NSApp.windows`에 없을 수 있으므로 가드/재시도를 둔다.

### G2. WebContent 프로세스 기동 = 번들 메타데이터 의존 (HIGH 리스크)
WKWebView는 out-of-process이며, WebContent 헬퍼는 호스트 앱의 번들 메타데이터에 의존한다.
bundle-less CLI(= nil `CFBundleIdentifier`, 빈 `CFBundleDisplayName`)에서는
빈 웹뷰 + 콘솔의 `WebProcessProxy::didFinishLaunching: Invalid connection identifier
(web process failed to launch)`가 발생할 수 있다. (코드 서명/샌드박스 문제가 아님 —
`swift build`는 Apple Silicon에서 linker가 ad-hoc 서명을 자동 적용하고, 비-샌드박스라
원격 https 네트워크는 기본 허용된다.)

**대응**: 빌드 산출물을 최소 `.app` 번들로 감싸 Info.plist에 비어있지 않은
`CFBundleIdentifier`(`dev.gum798.miniBrowser`)와 `CFBundleDisplayName`(`miniBrowser`)을 넣는다.
경량 셸 스크립트(`scripts/run.sh`)가 `swift build` → `.app` 래핑 → 실행을 담당한다.
순수 bundle-less 실행은 위험으로 분류하고, **M0 smoke test에서 원격 https 로드를 실증**한다.
진단을 위해 `webViewWebContentProcessDidTerminate` / `didFailProvisionalNavigation`에 로그를 둔다.

### G3. 모바일(iPhone Safari) 렌더링
- `webView.customUserAgent`에 iPhone Safari UA를 **로드 전에** 설정 (1차 메커니즘).
  `applicationNameForUserAgent`는 Mac 토큰을 남기므로 부적합.
- `WKWebpagePreferences.preferredContentMode`는 iOS 전용이라 네이티브 macOS에서 무용 → 사용 안 함.
- 웹뷰 폭을 **~390pt**로 제약해야 사이트의 모바일 breakpoint가 잡힌다. (UA만으론 불충분)
- viewport WKUserScript 주입은 fallback.
- UA 문자열 (iOS/macOS 26 기준; OS 토큰 18_6 고정, 향후 `Version/`만 상향):
  ```
  Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1
  ```

### G4. 탭별 WKWebView 영속(per-tab persistence)
value 타입 state에서 `makeNSView`로 매번 WKWebView를 만들면 탭 전환 시 페이지/스크롤이
사라진다. **참조 타입 `Tab: ObservableObject`가 WKWebView를 영구 소유**하고 `TabsModel`이 보관한다.
NSViewRepresentable은 얇은 셸로, 활성 탭의 살아있는 web view를 컨테이너 subview로 **스왑**만 한다.

### 기타 결정
- App Sandbox / `com.apple.security.network.client`는 로컬 `swift run` 빌드에 **추가하지 않는다**
  (불필요하며 오히려 네트워크 제약). 추후 Mac App Store 배포 결정 시에만 재검토.
- linker의 ad-hoc 서명을 제거하지 않는다(`-no_adhoc_codesign` 금지).

---

## 3. 아키텍처

### 3.1 패키지 구조 (3 타깃)
순수 로직을 라이브러리로 분리한다. executable 모듈은 test target에서 `import`이 불안정하므로,
로직을 `MiniBrowserCore`에 두고 app과 test가 둘 다 그것을 import 한다.

```
MiniBrowser/
├── Package.swift                 // swift-tools-version: 6.3, platforms: [.macOS(.v26)]
├── scripts/
│   └── run.sh                    // swift build → .app 래핑(Info.plist) → open (G2)
├── Sources/
│   ├── MiniBrowserCore/          // 라이브러리: 순수 로직 (WebKit·UI 의존 없음)
│   │   ├── URLResolver.swift
│   │   ├── BookmarkStore.swift
│   │   ├── HistoryStore.swift
│   │   ├── Models.swift          // Bookmark, HistoryEntry, SearchEngine
│   │   └── TabsState.swift       // 탭 식별/순서/활성 선택의 순수 상태 로직
│   └── MiniBrowserApp/           // 실행 파일: SwiftUI GUI (얇은 셸)
│       ├── MiniBrowserApp.swift  //   @main App + G1 활성화 부트스트랩
│       ├── BrowserView.swift     //   전체 레이아웃
│       ├── AddressBar.swift
│       ├── BottomToolbar.swift
│       ├── TabSwitcherView.swift
│       ├── StartPageView.swift
│       ├── Tab.swift             //   ObservableObject, WKWebView 소유 (G4)
│       ├── TabsModel.swift       //   ObservableObject, TabsState 활용
│       └── WebView.swift         //   NSViewRepresentable + Coordinator (G2/G3/G4)
└── Tests/
    └── MiniBrowserCoreTests/
        ├── URLResolverTests.swift
        ├── BookmarkStoreTests.swift
        ├── HistoryStoreTests.swift
        └── TabsStateTests.swift
```

`Package.swift` 핵심: `// swift-tools-version: 6.3`, `platforms: [.macOS(.v26)]`
(툴체인 거부 시 `.macOS("26.0")` 폴백), 외부 의존성 없음.
`.target(MiniBrowserCore)` + `.executableTarget(MiniBrowserApp, deps: [Core])` +
`.testTarget(MiniBrowserCoreTests, deps: [Core])`.

### 3.2 계층 / 의존성 방향
```
Views (SwiftUI)  ─▶  TabsModel / Tab (ObservableObject)  ─▶  MiniBrowserCore (순수 로직)
        │                        │
        └────▶ WebView (NSViewRepresentable) ─▶ WKWebView (Coordinator: weak→Model)
```
- `MiniBrowserCore`는 어떤 UI/WebKit 타입도 import 하지 않는다 → 유닛 테스트로 완전 검증.
- App 계층은 Core를 소비하고 WebKit을 다루는 얇은 표현층.

---

## 4. 컴포넌트 상세 (계약 중심)

### 4.1 `URLResolver` (순수 함수, MiniBrowserCore)
입력 문자열을 "이동할 URL" 또는 "검색 URL"로 변환.
- 시그니처: `static func resolve(_ input: String, searchEngine: SearchEngine) -> URL?`
- 규칙:
  1. 앞뒤 공백 제거. 빈 문자열 → `nil`.
  2. `http://`, `https://`, `file://` 스킴 포함 → 그대로 URL.
  3. 공백 없고 점(`.`)을 포함하며 호스트로 유효 → `https://` 접두 후 URL.
     (`localhost`, IP 리터럴도 호스트로 인정)
  4. 그 외(공백 포함 또는 점 없음) → `searchEngine.searchURL(query:)` (쿼리 URL 인코딩).
- 테스트 케이스: `"example.com"`→`https://example.com`, `"https://a.com/x"`→그대로,
  `"swift"`→검색, `"hello world"`→검색, `"localhost:8080"`→`https://localhost:8080`,
  `"  "`→`nil`.

### 4.2 `SearchEngine` (enum, MiniBrowserCore)
- 케이스: `.google`(기본). 향후 `.naver`, `.duckduckgo` 추가 가능.
- `func searchURL(query: String) -> URL` — 예: `https://www.google.com/search?q=<encoded>`.

### 4.3 `BookmarkStore` (MiniBrowserCore)
- 즐겨찾기 CRUD + JSON 영속화.
- `init(directory: URL)` — 디렉토리 주입(테스트는 임시 디렉토리 사용).
- API: `func all() -> [Bookmark]`, `func add(_:)`, `func remove(id:)`, `func move(from:to:)`.
- 영속: `directory/bookmarks.json` (`Codable`). 읽기 실패 → 빈 목록으로 시작(로그), 쓰기 실패 → 비치명적.
- `Bookmark`: `{ id: UUID, title: String, url: URL, createdAt: Date }`.

### 4.4 `HistoryStore` (MiniBrowserCore)
- 방문기록 추가/조회/자동완성.
- `init(directory: URL)`.
- API: `func record(url:title:)`(동일 URL 최신화·중복제거), `func recent(limit:) -> [HistoryEntry]`,
  `func suggestions(for prefix: String, limit:) -> [HistoryEntry]`(주소창 자동완성).
- 영속: `directory/history.json` (`Codable`). 양이 커지면 SQLite로 교체 가능(지금은 YAGNI).
- `HistoryEntry`: `{ url: URL, title: String, lastVisited: Date, visitCount: Int }`.

### 4.5 `TabsState` (순수 상태 로직, MiniBrowserCore)
탭 컬렉션의 식별/순서/활성 선택을 UI·WebKit 없이 순수하게 모델링하여 불변식을 테스트.
- 데이터: `tabIDs: [UUID]`, `activeID: UUID?`.
- 연산: `add(id:)`, `close(id:)`, `select(id:)`, `move(from:to:)`.
- 불변식:
  - 탭이 1개 이상이면 `activeID`는 항상 유효한 ID.
  - **활성 탭을 닫으면 이웃(가능하면 다음, 없으면 이전) 탭이 활성**.
  - 마지막 탭을 닫으면 `activeID == nil` (UI 계층이 새 시작화면 탭을 즉시 생성).
- (이 순수 로직을 `TabsModel`이 감싸 실제 `Tab` 객체와 결합.)

### 4.6 `Tab` (ObservableObject, App) — G4
- 1 탭 = 1 WKWebView. 모델이 web view를 **영구 소유**.
- `@Published`: `title`, `url`, `progress`, `canGoBack`, `canGoForward`, `isLoading`, `loadError`.
- WKWebView KVO(`observe`)로 위 값 갱신(메인 스레드), 토큰을 보관해 **deinit에서 invalidate**.
- 생성 시 `customUserAgent`(G3) 설정. `func load(_ url: URL)`.

### 4.7 `TabsModel` (ObservableObject, App)
- `@Published tabs: [Tab]`, `activeID`. 내부적으로 `TabsState` 불변식을 사용.
- `newTab(url:)`(시작화면 또는 지정 URL), `close(id:)`, `select(id:)`.
- `createWebViewWith`(target=_blank/window.open)에서 호출되는 `newTab(configuration:)` 경로 제공.

### 4.8 `WebView` (NSViewRepresentable + Coordinator, App) — G2/G3/G4
- `makeNSView` → 컨테이너 `NSView` 반환. `updateNSView`에서 활성 `tab.webView`를 subview로 스왑
  (재생성 금지). `dismantleNSView`는 detach만(모델이 소유하므로 dealloc 금지).
- Coordinator가 `WKNavigationDelegate`(lifecycle/policy/error) + `WKUIDelegate`(`createWebViewWith`).
  Coordinator는 `TabsModel`을 **weak**로 보유(retain cycle 방지).
- `createWebViewWith`: 넘겨받은 `WKWebViewConfiguration` 그대로 새 Tab 생성 후 그 web view 반환
  (in-place 정책이면 nil 반환 + 현재 web view에 직접 load).
- 네비게이션 성공 시 `HistoryStore.record` 호출(콜백/클로저로 App 계층에 위임).

### 4.9 Views (SwiftUI, App)
아이폰 Safari 레이아웃:
- **상단** `AddressBar`: 현재 URL/제목, 진행률 표시, 새로고침/정지, 입력 시 `HistoryStore.suggestions`
  자동완성, 제출 시 `URLResolver.resolve`.
- **본문** `WebView`(폭 ~390pt 제약, 관성 스크롤은 WKWebView 기본 제공).
- **하단** `BottomToolbar`: 뒤로 / 앞으로 / 즐겨찾기 추가·열기 / 탭 버튼(개수 배지).
- `TabSwitcherView`: 카드/그리드(제목+스냅샷), 선택/닫기/새 탭.
- `StartPageView`(새 탭): 즐겨찾기 그리드 + 최근 기록. 항목 탭 → 이동.

---

## 5. 데이터 흐름
1. 주소창 입력 → `URLResolver.resolve` → 활성 `Tab.load(url)`.
2. WKWebView KVO → `Tab.@Published` 갱신 → SwiftUI 리렌더. 네비게이션 성공 → `HistoryStore.record`.
3. 탭 버튼 → `TabSwitcherView`에서 select/close/new → `TabsModel`(=`TabsState` 불변식) → 활성 web view 스왑.
4. 시작화면 즐겨찾기 탭 → 해당 URL 이동. `target=_blank` → `createWebViewWith` → 새 탭.

---

## 6. 에러 처리
- 네비게이션 실패(`didFail`/`didFailProvisionalNavigation`) → `Tab.loadError` 설정 → 본문에 인라인 에러 + 재시도.
- WebContent 프로세스 종료(`webViewWebContentProcessDidTerminate`) → 로그 + 자동 reload 1회 시도(G2 진단 지점).
- 잘못된 입력 → `URLResolver`가 자동으로 검색으로 폴백(에러 아님).
- 스토어 읽기 실패 → 빈 상태로 시작(로그), 쓰기 실패 → 비치명적 로그.

---

## 7. 영속화
- 위치: `~/Library/Application Support/miniBrowser/` (`FileManager` `.applicationSupportDirectory`).
- 파일: `bookmarks.json`, `history.json` (`Codable`).
- 스토어는 `directory` 주입으로 테스트 시 임시 디렉토리 사용.

---

## 8. 빌드 / 실행 / 테스트
- **실행**: `scripts/run.sh` — `swift build` → 산출물을 `.build/miniBrowser.app`로 래핑
  (Info.plist에 `CFBundleIdentifier`/`CFBundleDisplayName` 포함, G2) → `open` 실행.
  (단순 `swift run`은 G2 리스크가 있어 보조 수단으로만.)
- **테스트**: `swift test` — `MiniBrowserCore` 순수 로직 검증.
- macOS 26 / Swift 6.3 / Apple Silicon 가정.

---

## 9. 테스트 전략
- 유닛(XCTest 또는 Swift Testing), `MiniBrowserCore`만 대상:
  - `URLResolver`: URL vs 검색 분기 전 케이스.
  - `BookmarkStore`: 추가/삭제/이동/JSON 왕복(임시 디렉토리).
  - `HistoryStore`: 기록/중복제거/최신화/접두 자동완성.
  - `TabsState`: 활성탭 닫기 시 이웃 선택, 마지막 탭 닫기, 이동 후 순서/활성 불변식.
- WebKit/SwiftUI 렌더링은 유닛 테스트 대상 외 → **M0 smoke test로 수동 실증**
  (윈도우 표시 + 키보드 포커스 + 원격 https 로드 + 모바일 레이아웃).

---

## 10. 리스크 & 완화 (요약)
| 리스크 | 심각도 | 완화 |
|---|---|---|
| bundle-less에서 WebContent 기동 실패(빈 웹뷰) | High | `.app` 번들 래핑(Info.plist), M0 smoke test로 실증, 진단 로그 |
| macOS 26/Swift 6.3 실측 미수행(추론 기반) | Med | M0에서 G1+G2 동작을 가장 먼저 검증 |
| KVO 미정리/뷰 스왑이 .id와 충돌해 탭 영속 깨짐 | Med | deinit invalidate, weak 캡처, 단일 representable+subview 스왑, 변하는 .id 금지 |
| `.macOS(.v26)` 툴체인 거부 | Low | `.macOS("26.0")` 폴백 또는 `.v14/.v15` 하향 |
| UA 스푸핑만으론 일부 사이트 데스크톱 렌더 | Low | UA + 폭 ~390pt 제약 + viewport fallback, 완벽 에뮬은 비목표 |

---

## 11. 마일스톤 (개략)
- **M0 — 토대 smoke test**: 최소 SwiftUI 앱 + `.app` 래핑 스크립트 + WKWebView로 https 1페이지 로드.
  G1(키보드 포커스)·G2(WebContent 기동)·G3(모바일 레이아웃) 실증. **여기서 막히면 설계 재검토.**
- **M1 — Core 로직 + 테스트**: `URLResolver`/`BookmarkStore`/`HistoryStore`/`TabsState` + 유닛 테스트.
- **M2 — 단일 탭 브라우징 UI**: 주소창(검색/자동완성) + 본문 + 하단 툴바(뒤/앞/새로고침) + 히스토리 기록.
- **M3 — 탭**: `Tab`/`TabsModel` + 탭 스위처 + `target=_blank` 새 탭.
- **M4 — 즐겨찾기/시작화면**: 즐겨찾기 CRUD + 새 탭 시작화면(즐겨찾기/최근).
- (M5+ 향후: 암호, 당겨서 새로고침 등 비목표 항목.)
