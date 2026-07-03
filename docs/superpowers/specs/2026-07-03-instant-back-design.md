# 즉시 뒤로가기 (페이지 스택) — 설계

2026-07-03 · 승인됨

## 문제

링크를 눌러 들어갔다가 뒤로 나오면 매번 재로딩된다. 뽐뿌·SLR클럽 등 주요 사이트가
`Cache-Control: no-store`를 보내 WebKit의 back-forward 캐시가 비활성화되기 때문이며,
공개 API로 이 캐시를 강제할 수 없다. 사용자 요구: "가급적 로딩 안 하게".

## 채택한 방식

**페이지 스택**: 링크로 이동할 때 현재 페이지의 웹뷰를 죽이지 않고 산 채로 스택에 두고,
새 웹뷰를 만들어 그 위에 표시한다. 뒤로가기 = 현재 웹뷰를 걷어내고 밑의 살아있는 웹뷰를
다시 표시(네트워크 0, 스크롤·DOM 상태 보존). 걷어낸 웹뷰는 forward 스택으로 가서
앞으로가기도 즉시다.

기각한 대안: (a) 스냅샷을 먼저 보여주고 밑에서 재로딩 — 여전히 매번 로딩이고 목록이
바뀔 수 있음. (b) 캐싱 강화 — `no-store`를 우회할 공개 API가 없음.

## 동작 규칙

- **푸시**: 메인 프레임 + `linkActivated` 네비게이션만 가로채서 새 웹뷰에 로드.
  폼 제출·리다이렉트·JS 이동(pushState 등)은 지금처럼 같은 웹뷰의 네이티브 히스토리.
- **뒤로**: 현재 웹뷰의 네이티브 히스토리가 있으면(`webView.canGoBack`) 그것 먼저,
  없으면 스택 pop. 앞으로도 대칭.
- **forward 비우기**: 새 링크 이동(푸시) 시 forward 스택의 웹뷰를 전부 파기 — 일반
  브라우저와 동일.
- **메모리 상한**: back/forward 스택 각각 살려두는 웹뷰 **5개**. 초과 시 현재
  페이지에서 가장 먼 항목(스택 바닥)부터 웹뷰만 파기하고 URL·제목을 남긴다
  (placeholder). placeholder까지 되돌아가면/나아가면 그때 새로 로드한다.
  (forward에도 상한을 두는 이유: placeholder를 연속으로 되돌아가면 그때마다 새
  웹뷰가 생겨 forward에 live가 무한히 쌓일 수 있다.)
- **canGoBack/canGoForward**(툴바·엣지 스와이프 활성 조건) =
  네이티브 히스토리 ‖ 스택에 항목 있음.

## 컴포넌트

- **`MiniBrowserCore.PageStack<Element>`** (신규, 순수 로직, 유닛테스트 대상)
  - back/forward 두 스택과 상한을 관리하는 상태기계.
  - `push(current:)` → forward 전체 비움 + 상한 초과분 evict를 콜백으로 통지,
    `goBack(current:) -> Element?`, `goForward(current:) -> Element?`,
    `canGoBack`, `canGoForward`.
  - Element는 제네릭: 앱에서는 `.live(WKWebView)` / `.placeholder(URL, title)` enum.
- **`Tab`** (수정)
  - `pageStack` 소유. `pushNewPage(for request:)` — 새 웹뷰 생성(기존 `makeWebView` +
    AdBlocker/ElementHider 등록 + 줌/반전 적용), 현재 웹뷰를 스택에 푸시, 교체.
  - `goBack()/goForward()` — 위 동작 규칙대로 라우팅. 팝 시 KVO 재구독(기존
    `hardReset()`의 재구축 패턴 재사용), title/url/canGo* published 값 즉시 갱신,
    현재 줌·반전 상태를 드러난 웹뷰에 재적용.
  - placeholder 복귀는 새 웹뷰 + 해당 URL 로드.
  - 깨짐 자동복구(`hardReset`)는 **현재 웹뷰만** 교체하고 스택은 유지.
- **`WebView.Coordinator`** (수정)
  - `decidePolicyFor navigationAction`: 메인 프레임 `linkActivated`이면 `.cancel` 후
    `tab.pushNewPage(for:)`. 나머지는 `.allow`.
  - `updateNSView`의 웹뷰 교체 분기는 지금 그대로(스택 스왑도 같은 경로로 재부착).
- **`EdgeSwipeOverlay`** (수정 소폭)
  - 활성 조건을 탭 수준 canGoBack/Forward로(이미 `tab?.canGoBack` 사용 — Tab 쪽이
    스택 인지로 바뀌면 자동 반영). 커밋 시 `tab.goBack()` 호출도 그대로.
  - 드래그 중 밑에 실제 이전 웹뷰가 드러나는 라이브 리빌은 **이번 범위에서 제외**
    (후속 개선). 기존 슬라이드+셰브론 시각 효과 유지.
- **`TwoFingerSwipe`** (신규 전용 타입, BrowserView에서 설치)
  - 로컬 `.scrollWheel` 이벤트 모니터. 웹뷰 위에서 phase `.began`부터 가로 델타가
    세로를 확실히 지배하면 내비게이션 스와이프로 전환해 이벤트를 소비하고, 임계값을
    넘겨 놓으면 `tab.goBack()/goForward()`.
  - 단, 현재 웹뷰의 네이티브 히스토리로 갈 수 있는 방향이면 WebKit 기본 제스처에
    맡긴다(소비하지 않음). `allowsBackForwardNavigationGestures`는 유지.

## 바뀌지 않는 것

- 새 탭(window.open/target=_blank) 경로, 세션 저장(현재 URL만; 스택은 재시작 시
  유지하지 않음), 즐겨찾기·히스토리 기록, 광고차단·방해요소·색반전·줌의 적용 방식.

## 트레이드오프 (수용)

- 메모리 증가: 페이지당 수십 MB 가능 → 상한 5로 제한(필요 시 조정).
- 살아있는 백그라운드 페이지의 JS 타이머가 계속 돎 — 공개 API로 완전 정지 불가,
  영향 미미로 판단.
- 두 손가락 스와이프가 가로 스크롤 요소(캐러셀) 위에서 오동작할 수 있음 — 가로
  지배 판정으로 완화, 모바일 레이아웃에선 드묾.

## 테스트

- `PageStackTests` (유닛): 푸시/팝 순서, forward 비우기, 상한 초과 시 oldest evict
  콜백, placeholder 경계, canGoBack/Forward 불변식, 빈 스택 동작.
- 수동 검증(실행): 뽐뿌 목록→글→뒤로(즉시+스크롤 보존), 앞으로, 6단계 이상 들어가
  placeholder 재로딩 확인, 엣지 드래그·두 손가락·‹ 버튼 3경로, 새 탭·줌·반전 회귀.
