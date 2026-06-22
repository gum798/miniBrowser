# miniBrowser

macOS에서 도는 **아이폰 Safari 스타일 미니 브라우저**. 폰 크기 창 + 모바일 레이아웃 + 관성 스크롤로, 데스크탑에서 모바일 웹을 보는 경험을 제공합니다.

> **상태: 설계 중 (v1 스펙 확정 단계)** — 아직 구현 코드는 없습니다. 아래 내용은 확정된 설계 방향입니다.

## 스택

- Swift 6 / SwiftUI / WKWebView (WebKit = Safari와 동일 렌더링 엔진)
- **Swift Package** 로 빌드·실행 (Xcode 프로젝트 없이 `swift run` / `swift test`)
- 대상: macOS (Apple Silicon)

## v1 범위

**포함**

- 주소창 (URL / 검색어 자동 판별), 페이지 로드, 뒤로·앞으로·새로고침
- 폰 크기 창 + 모바일 User-Agent (사이트가 모바일 레이아웃으로 렌더링)
- 관성(momentum) 터치 스크롤
- 탭 (아이폰풍 탭 전환)
- 즐겨찾기 / 시작화면
- 방문 기록 (History)

**v1 제외 (확장 지점만 남김)**

- 암호 AutoFill / 패스키 — 서드파티 WKWebView 브라우저는 iCloud 키체인 완전 호환이
  Apple의 제한된 엔타이틀먼트(`com.apple.developer.web-browser.public-key-credential`)
  심사를 받아야 가능해 v1에서는 제외
- 당겨서 새로고침, 프라이빗 모드, 리더 모드

## 빌드 / 실행 (예정)

```bash
swift run      # 앱 실행
swift test     # 유닛 테스트
```

## 아키텍처 (예정)

상태/로직은 WebKit·UI 의존 없이 분리해 유닛 테스트로 검증합니다.

- `URLResolver` — 입력 문자열 → URL 이동 / 검색 판별 (순수 함수)
- `BookmarkStore` — 즐겨찾기 CRUD + JSON 영속화
- `HistoryStore` — 방문 기록 추가/조회/자동완성
- `TabsModel` — 탭 컬렉션 상태기계 (열기/닫기/선택/이동)
- `WebViewContainer` — `NSViewRepresentable` 로 WKWebView 래핑
- `Views/*` — SwiftUI 화면 (주소창, 하단 툴바, 탭 스위처, 시작화면 등)
