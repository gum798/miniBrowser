# 전역 색반전 + 설정 저장 — 설계

2026-07-06 · 승인됨

## 문제

색반전이 탭 단위라 새 탭마다 다시 켜야 하고(사용자는 항상 켜고 씀), 광고 차단·
자리비움 자동 숨김 토글은 재시작하면 초기화된다. 사용자 요구: "기본 전체 색반전이
있고 설정 저장되게".

## 채택한 방식

앱 전역 설정 하나(`Settings`)를 `settings.json`으로 영속화. 색반전은 탭별 토글을
없애고 **전역 스위치 하나**로 통일(사용자 선택). 광고 차단·자리비움 상태도 함께
저장. UserDefaults 대신 JSON 파일 — 기존 스토어 패턴(`bookmarks.json` 등)과 동일,
코어 분리로 테스트 가능.

## 컴포넌트

- **`MiniBrowserCore.SettingsStore`** (신규, TDD 대상)
  - `Settings: Codable, Equatable { inverted: Bool, adBlockEnabled: Bool, bossModeEnabled: Bool }`
  - 기본값: `inverted=false, adBlockEnabled=true, bossModeEnabled=true` (현재 앱의
    시작 동작과 동일).
  - **관대한 디코딩**: 필드 단위 `decodeIfPresent ?? 기본값` (`TabSnapshot` 패턴) —
    설정이 추가돼도 옛 파일이 깨지지 않음. 파일 없음/손상 → 기본값.
  - `load() -> Settings`, `save(_:)` → `<directory>/settings.json`.
- **`AppSettings`** (MiniBrowserApp, 신규 — `@MainActor` 싱글턴 `ObservableObject`)
  - `Settings`를 로드해 보유; 값이 바뀔 때마다 즉시 `save`.
  - `inverted` 변경 시 등록된 콜백으로 전파(TabsModel이 전 탭에 적용).
- **`Tab`** (수정)
  - `inverted`는 전역 값을 반영하는 표시용으로 축소: 탭 생성 시
    `AppSettings.shared.inverted`로 초기화, 전역 토글 시 `setInverted(_:)`로 갱신
    (기존 installInvertScript/applyInvert 메커니즘 재사용 — 스택의 살아있는
    페이지는 드러날 때 `show()`가 이미 현재 반전 상태를 재적용).
  - `applyRestored(zoom:inverted:)` → `applyRestored(zoom:)`으로: 스냅샷의
    inverted는 복원에 사용하지 않음(전역이 결정).
- **`TabsModel`** (수정)
  - `restore()`: settings.json이 **없을 때만** 세션 활성 탭의 `inverted`를 전역
    초기값으로 마이그레이션(있으면 settings가 우선).
  - `setInvertedAll(_:)`: 모든 탭에 전역 반전 적용.
  - `persist()`: `TabSnapshot.inverted`에는 전역 값을 기록(옛 버전과 파일 호환 유지).
- **`BottomToolbar`** (수정)
  - "색 반전" 항목이 전역 토글(`AppSettings.shared.inverted`)로. 체크 표시는 전역 값.
  - "광고 차단", "자리비움 자동 숨김" 토글이 `AppSettings`에 기록.
- **`AdBlocker` / `BossMode`** (수정 소폭)
  - 시작 시 `AppSettings`에서 `enabled` 초기화. 동작 로직은 변화 없음.

## 동작 규칙

- 전역 반전 토글 → 현재 모든 탭(+스택에 살아있는 페이지는 드러날 때) 즉시 반영,
  새 탭도 그 값으로 시작, 재시작 후 유지.
- 설정 변경은 즉시 저장(디바운스 불필요 — 파일이 작고 변경 빈도 낮음).
- 줌은 지금처럼 탭별 유지(범위 외).

## 마이그레이션 / 호환

- 첫 실행(settings.json 없음): 세션 활성 탭의 inverted → 전역 초기값. 사용자의
  현재 세션(전부 반전)이 그대로 이어짐.
- session.json 포맷 불변(TabSnapshot.inverted 계속 기록) — 구버전으로 되돌려도 안전.

## 테스트

- `SettingsStoreTests` (유닛): 라운드트립, 파일 없음 → 기본값, 손상 파일 → 기본값,
  필드 누락(옛 파일) → 해당 기본값, 알 수 없는 필드 무시.
- 수동 검증: 반전 토글 → 전 탭 반영 → 재시작 유지; 새 탭 반전 시작; 광고차단·
  자리비움 토글 재시작 유지; settings.json 삭제 후 실행 → 세션에서 마이그레이션.
