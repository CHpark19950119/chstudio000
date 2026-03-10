# CHEONHONG STUDIO — CHANGELOG

## 현재 이슈 (해결 필요)
- [ ] WiFi 연결 후 history/archive 데이터 Hive 캐시 확인 — 인터넷 없으면 최근 7일만 표시
- [ ] 4AM 일전환(rollover) 정상 작동 확인

## 모니터링 (확인 필요)
- [ ] Phase C 마이그레이션 정상 완료 확인 (data/today 문서 생성, history/{month} 생성)
- [ ] 캘린더 월 데이터 → history + archive + study 3단 fallback 정상 작동 확인
- [ ] 포커스 완료 → today.studyTime.total 증가 확인
- [ ] 투두 저장 → today.todos 리스트 동기화 확인
- [ ] 텔레그램 NFC → 다영, 배포 → 나 확인

## 2026-03-10
### v10.1 — 플리커링 근본수정 + NFC 경량화 + 식사독립
- [x] **시간 플리커링 근본 해결**: 스트림 리스너에서 timeRecords 파싱 완전 제거 (today doc 단일 소스)
- [x] **웹앱 충돌 원인 확인**: `/c/dev/CH-STUDIO` 웹앱이 같은 study doc에 동시 write → 스트림 분리로 해결
- [x] **식사 DayState 분리**: eating 제거 → `_isMealing` 독립 boolean (공부 상태 변경 없음)
- [x] **루틴카드 DayState 직접 사용**: `_nfc.state` 기반 상태 판별 (TimeRecord fallback 유지)

### v10.0 — NFC Service DayState FSM 리빌드
- [x] **DayState enum FSM**: boolean 토글 → `idle/awake/outing/studying/returned/sleeping` 상태 머신
- [x] **태그 중복 방지**: 동일 역할 태그 30초 쿨다운 (실수 방지)
- [x] **자동 기상**: idle 상태에서 wake 외 태그 태핑 → 자동 기상 기록
- [x] **리마인더**: 기상 60분 후 비활동 알림, 공부 4시간 후 식사 알림
- [x] **일일 요약**: 취침 태그 시 Telegram 일일 요약 (순공/식사/외출/활동시간)
- [x] **Telegram 정확성**: 모든 시간을 `DateTime.now()` 기준으로 전송 (추정값 사용 안 함)
- [x] **Firestore write timeout**: 모든 updateTimeRecord에 5초 timeout 적용
- [x] **GeofenceService 생성**: 집 위치 100m 반경 자동 외출/귀가 감지 (MethodChannel 기반)
- [x] **식사 상태 복귀**: 식사 전 상태 자동 복귀 (공부 중→식사→공부 재개)

## 2026-03-09
### v9.13 — NFC/시간기록 캐시 동기화 버그 수정
- [x] **_bgRefreshDoc write-protect 가드 추가**: 쓰기 직후 백그라운드 Firebase 갱신이 Hive 캐시 덮어쓰기 방지
- [x] **updateTodayField await 수정**: Hive today 캐시 비동기 저장 누락 수정
- [x] **updateTimeRecord await 수정**: updateStudyField / updateTodayField 비동기 완료 대기
- [x] **write-protect 시간 10초로 연장**: 네트워크 지연 대응

## 2026-03-08
### v9.12 — 오더탭 통계 개선 + 포커스존 즉시 돌입
- [x] **기록탭 강화**: 순공시간 추이 LineChart (주간/월간) + 과목별 누적시간 수평 BarChart + 최고 기록일 하이라이트
- [x] **과목 Firestore 동기화**: SubjectConfig에 Firestore 양방향 sync 추가 (다기기 대비)
- [x] **오더 "오늘" 탭 리디자인**: NFC 타임라인 중심 → 오늘의 습관/목표 이행 현황 + NFC는 ExpansionTile로 접기
- [x] **오더 "통계" 탭 리디자인**: 목표 달성률/습관 정착 파이프라인/스트릭 순위/주간 히트맵/목표 진행 타임라인
- [x] **포커스존 즉시 돌입**: 과목 선택 + 모드 선택 → 시작 버튼 → FocusScreen 이머시브 직행 (중간 카드 단계 제거)
- [x] **포커스 재진입 가드**: FocusScreen 복귀 시 무한 루프 방지 (_focusScreenOpen 플래그)

### v9.11 — 자동화 화면 컴팩트 리디자인
- [x] **NFC & 자동화 → 자동화**: 화면 이름 변경
- [x] **컴팩트 레이아웃**: SliverAppBar → Scaffold+AppBar+ListView, 세로 길이 대폭 축소
- [x] **상태바**: 가로 pill 형태 (emoji+label), 한 줄에 표시
- [x] **태그 행**: 한줄 Row + 미니 액션 버튼 (play/ndef/delete), PopupMenu 제거
- [x] **스캔 영역**: 소형 카드 + 상태 메시지 + 2버튼
- [x] **설정 통합**: 거치대 토글 + 무음 NFC 토글 → 단일 카드
- [x] **설정 화면**: 진입 카드 텍스트 '자동화'로 통일

### v9.10 — 홈 대시보드 정리 + 도서관 배치도 완성
- [x] **Habitat FAB 임시 비활성화**: CreatureFloatButton, HabitatScreen 진입 경로 제거
- [x] **대시보드 순서 변경**: NFC → 도서관 → 순공시간 → 성적 → 포커스 → 메모 → 위치요약 → 퀵툴
- [x] **날씨+성적 2컬럼 제거**: 성적만 단독 카드로 분리 (날씨는 헤더에 이미 존재)
- [x] **위치요약 카드 추가**: 일간 타임라인 대시보드에 표시
- [x] **도서관 배치도**: 단일 열람실 + 좌측 복도, 문 2개 (H-I, I-J), 항상 라이트 모드
- [x] **좌석 디자인**: 장애인/이용불가 → 희미 윤곽, 이용중 → 빗금 패턴, 스탠드 → 원형+S뱃지

### v9.9 — 도서관 좌석 배치도 CustomPainter 전환
- [x] **Flame → CustomPainter 전면 전환**: `library_floor_game.dart` 삭제
- [x] **세로 레이아웃**: 1번 하단(입구) → 56번 상단(안쪽 벽), 블록 G→A 아래→위
- [x] **입구 + 통로**: 하단 벽 열린 부분 + 좌측 세로 복도 표현
- [x] **좌석 도트**: glow + pulse(이용중), 입체 하이라이트, 이용불가 ✕ 표시
- [x] **하단 블록 H/I/J**: 입구 아래 가로 배치
- [x] **InteractiveViewer**: 핀치 줌(0.6~4x) + 패닝
- [x] **탭 말풍선**: glassmorphism 스타일, 2초 후 자동 사라짐
- [x] **60초 자동 갱신**
- [x] 다크/라이트 분기, 나무 텍스처 책상, 이중 벽선

### v9.8 — 크리쳐 3D 스프라이트 시트 교체
- [x] **하드코딩 픽셀 배열 전면 제거**: egg/baby/junior/master/legend × idle/walk/blink 전부 삭제
- [x] **3D 복셀 스프라이트 시트**: `creature_3d_sheet_128.png` (768×768, 6×6 그리드, 128×128 프레임)
- [x] **36프레임 SpriteAnimation**: 10fps (stepTime 0.1), 수면 시 0.3으로 감속
- [x] **스테이지별 스케일링**: EGG=0.5x, BABY=0.65x, JUNIOR=0.8x, SENIOR=1.0x, LEGEND=1.2x
- [x] **상태 머신 유지**: idle(부유), walk(좌우이동+flip), jump(탭), happy(경쾌), sleep(zzZ)
- [x] **LEGEND 금빛 오라**: MaskFilter.blur 글로우, sin 맥동
- [x] **MiniCreaturePainter**: 미니 새 아이콘으로 단순화 (CustomPainter에서 스프라이트 시트 불가)

### v9.7 — 도서관 Flame 탑다운 뷰 v2
- [x] **좌석 방향 수정**: 1번석 우측 배치 (실제 도서관 일치)
- [x] **입구 위치 수정**: 하단 블록 사이 (64-72 / 78-84 통로) + 입구 화살표
- [x] **가로 7블록 실제 레이아웃** + 하단 3블록 (A→G, 좌→우)
- [x] **도트 게임 스타일**: glow + pulse, 점유(빨강)/비점유(초록) 명확 구분
  - MaskFilter.blur 외부 발광, 점유는 pulse 애니메이션
  - 이용불가: 어두운 회색 + ✕
- [x] **책상 개선**: 그라디언트 나무 텍스처 + 우드 그레인 + 중앙 디바이더 + 그림자
- [x] 벽 + 하단 입구 개구부, 8px 그리드 패턴, 다크/라이트 대응
- [x] fitWidth 초기 줌, 핀치 줌/패닝, 좌석 탭 말풍선
- [x] 84석 파싱 100%

### v9.6.2 — 좌석 배치도 완전 개편
- [x] **ASP.NET POST 2단계 크롤링**: GET→ViewState 추출→POST(Roon_no=2)로 room 2(일반열람실) 84석 전체 파싱
  - 기존 GET은 room 1(노트리스, 34석)만 반환 → POST로 room 전환 필수
- [x] **좌석 그리드 90° 회전**: 세로형 폰 최적화
  - 상단 56석: 7그룹 × 2행 × 4열 (입구→안쪽 순서)
  - 하단 28석: 3서브그룹 가로 배치 (57-64 / 65-78 / 79-84)
- [x] dotAll 정규식 + room_content 영역 스코핑으로 파싱 정확도 개선
- [x] 파싱 결과: 84/84 seats 확인 (logcat)

### v9.6.1 — 좌석 배치도 버그 수정
- [x] 좌석 그리드 overflow 수정: `LayoutBuilder`로 화면 너비에 맞춰 동적 셀 크기 계산
- [x] CSS 클래스 파싱 수정: `int` → `String` 비교 (`Style1` vs `Style10` 정확 구분)
- [x] 하단 행(57~84) 레이아웃 정상 표시 확인

### v9.6 — 부곡도서관 좌석 현황
- [x] **홈 화면 도서관 카드 추가** (잔여좌석/이용률 실시간)
  - `home_library_card.dart`: part of home_screen, extension 패턴
  - 잔여좌석 큰 숫자 + 이용률 원형 게이지 + 상태 뱃지 (여유/거의만석/만석)
  - 탭 → 좌석 배치도 화면 진입
- [x] **좌석 배치도 화면** (84석 실제 레이아웃, 상태별 색상)
  - `library_seat_map_screen.dart`: InteractiveViewer 핀치 줌
  - 상단 요약 스트립 + 좌석 그리드 + 하단 범례
  - Pull-to-refresh + 새로고침 버튼
- [x] **library_service.dart**: HTTP 크롤링 + 30초 캐시
  - 부곡도서관 ASP.NET 좌석 현황 페이지 파싱
  - 요약 테이블 (data-room_no="2") + 개별 좌석 CSS 클래스 파싱
  - SeatStatus: available/standing/disabled/unavailable/inUse
- [x] AndroidManifest: `usesCleartextTraffic=true` (HTTP 서버 접속용)

### v9.5 Statistics Concentration + Cradle Fix + Weekly Chart Removal
- [x] **통계 화면: 세션별 집중도 + 시간별 집중도**
  - `_sessionConcentrationCard()`: 세션별 집중률(%) 바 — 80%↑ 초록, 50~80 노랑, 50↓ 빨강
  - `_hourlyConcentrationCard()`: 시간대별 순공분 히트맵 바 + 피크시간/활동시간 요약
  - 기존 `_barChartCard()` (주간/월간 순공시간 바)와 `_studySummaryCard()` 대체
- [x] **거치대 등록 플로우 수정**
  - StatefulBuilder 내부 변수 선언 버그 수정 (setBS 호출 시 매번 초기화됨)
  - 모든 calibration UI: 변수를 외부 스코프로 이동
  - 플로우: 안내 → 측정 시작 → 5초 측정(진행바) → 등록 완료 → 닫기
- [x] **홈 포커스 탭: 위클리 차트 제거**
  - `_fWeeklyChart()` 메서드 및 WEEKLY 섹션 삭제

### v9.4.4 Focus Setup → Home Tab Migration
- [x] **포커스 셋업 뷰 → 홈 포커스 탭 이동**
  - 시작 버튼 누르면 바로 세션 시작 + 몰입 화면 진입
  - `_loadFocusRecords()` 앱 시작 시 호출 추가
- [x] **FocusScreen 몰입 전용화**
  - `_shellView()` 제거 → 세션 종료 시 자동 `Navigator.pop()`
  - 비실행 상태에선 빈 화면 + 즉시 pop back
- [x] **정리**: 미사용 lottie import 제거 (home_screen.dart)

### v9.4.3 Home Focus Redesign + Single-scroll Focus + Session Delete
- [x] **home_focus_section.dart 완전 재디자인**
  - "집중할 준비가 되었나요?" + 큰 초록 카드 + Lottie 책 애니메이션 삭제
  - 새: gradient 순공시간 (52px) + 세션 수 뱃지 + 프로그레스 바
  - 과목 칩 가로 스크롤 + glassmorphism 시작 버튼
  - 진행 중: 컴팩트 상태 카드 (mode + subject + timer + 열기 버튼)
- [x] **focus_screen.dart 단일 스크롤 뷰로 통합**
  - PageView(시작/기록 탭) 제거 → 한 화면에 전부 스크롤
  - 거치대 설정 카드:
    - 미등록: "📐 거치대를 설정하세요" + [거치대 등록] 버튼
    - 등록됨: "✅ 거치대 등록됨" + 상태 dot + 현재 각도 표시 + [재등록]
    - 감지 OFF 시 [감지 켜기] 버튼
  - 기록 영역: divider → weekly chart → today summary → session list
- [x] **세션 삭제 기능**
  - 세션 카드 길게 누르기 → "삭제할까요?" 다이얼로그
  - 확인 → `FocusService.deleteFocusCycle()` (Hive + Firebase 동시 삭제)
  - UI 즉시 반영 (todaySessions 갱신)
- [x] Build OK + adb installed + logcat clean + Telegram sent

### v9.4.2 Setup/Records Redesign + Angle-based Cradle
- [x] **focus_screen.dart _setupView() 완전 재작성**
  - Hero 순공시간: 카드 래핑 제거 → 배경 위 floating gradient text (56px)
  - Session count 뱃지 + 목표 프로그레스 바 (3px thin)
  - Subject 칩: pill 형태 (borderRadius 20), transparent 배경
  - Mode 칩: glassmorphism frost 카드 + emoji/label/desc 레이아웃 + 활성 dot
  - Cradle 인라인: 미니멀 dot + 현재 각도 표시 + 설정 링크
  - Start 버튼: glass pill (translucent gradient, not solid)
  - `_secLabel()` 헬퍼 (uppercase, 2.5 letter-spacing, 0.55 opacity)
- [x] **focus_screen.dart _recordsView() 재디자인**
  - Weekly 차트: glass 카드, 56px 바 높이, 오늘 glow
  - Today 요약: gradient 순공 텍스트 (28px) + miniStat 뱃지
  - Session 타일: left gradient stripe (3px) + frost 카드 (14 radius)
  - 빈 상태: "아직 기록이 없어요" 메시지
- [x] **cradle_service.dart 각도 기반 감지로 재작성**
  - 기존: Euclidean distance + variance → 새: 중력 벡터 각도 (dot product)
  - `_angleDeg()`: 두 벡터 사이 각도 (도) 계산
  - attach threshold: 12° (캘리 각도 ±12° 이내 → ON)
  - detach threshold: 25° (캘리 각도 ±25° 초과 → OFF)
  - 히스테리시스 데드존: 12°~25°
  - `lastAngle` getter (debug용 현재 각도)
  - 캘리브레이션 = 해당 각도에서만 활성화
- [x] Settings 설명 텍스트 업데이트: "캘리브레이션 각도 기준 거치대 감지"
- [x] Build OK + adb installed + logcat clean + Telegram sent

### v9.4.1 Focus Zone Phase 2 Redesign
- [x] **focus_screen.dart** 완전 새 디자인 (Phase 2)
  - Glassmorphism 카드: `_frost()` 헬퍼 (ClipRRect + BackdropFilter + blur)
  - Theme-aware 컬러 시스템: `_bg`, `_card`, `_t1`/`_t2`/`_t3`, `_accent` (라이트/다크 자동)
  - 세션 시작 뷰: ShaderMask 그라디언트 히어로 타임, uppercase 라벨, 과목 컬러 칩, 인라인 거치대 상태
  - 기록 뷰: 주간 막대 차트 (오늘 glow), 그라디언트 요약 스트립, 좌측 컬러 스트라이프 세션 카드
  - 집중 뷰: 다크 배경(0xFF08080C), ambient glow pulse, CustomPainter 원형 링, 미니멀 버튼 행
  - Staggered fade-in 애니메이션 (`_stagger()` + CurvedAnimation + Interval)
  - Count-up 숫자 애니메이션 (`_heroCountCtrl`)
  - Monospace bold 숫자, light small 라벨
- [x] **거치대(Cradle) 검증 완료**
  - CradleService.init() → enabled=true, calibrated=true, ref 로드 OK
  - accelerometerEventStream 수신 OK (logcat 확인)
  - 포커스존 세션시작 뷰에서 거치대 상태 카드 표시
- [x] Build OK + adb installed + logcat clean + Telegram sent

### v9.4 Focus Zone 3-View Rewrite
- [x] **focus_service.dart** 완전 재작성: Hive-first 데이터 흐름
  - SharedPreferences → Hive Box('focus_data') 전환 (상태 저장/복원)
  - 세션 종료 시 Hive 즉시 저장 → notifyListeners() → UI 즉시 갱신
  - Firebase write는 백그라운드 (세션 기록 누락 방지)
  - `_loadTodaySessions()`: Hive에서 오늘 세션 목록 즉시 로드
  - `_saveSessionToHive()`: 세션 완료 즉시 Hive 저장
  - `getSessionsForDate()`: Hive 우선 → Firebase fallback
  - `getWeeklyStudyMinutes()`: 최근 7일 일별 순공 집계
  - `refreshTodaySessions()`: 외부에서 기록 리프레시
  - `deleteFocusCycle()`: Firebase + Hive 동시 삭제 + 로컬 목록 갱신
  - Foreground Task callback도 Hive 기반으로 전환
- [x] **focus_screen.dart** 완전 재작성: 3-View 구조
  - 뷰 1 (세션 시작): 오늘 순공 그라디언트 카드, 과목 가로 스크롤 칩, 모드 선택, 거치대 상태 카드, 시작 버튼
  - 뷰 2 (집중 모드): 전체화면 immersive, 원형 프로그레스 링 + glow, 모드/과목 전환, 화장실/서브타이머/거치대
  - 뷰 3 (기록): 주간 막대 그래프, 오늘 세션 리스트 (좌측 과목 컬러 스트라이프), 세그먼트 바
  - PageView 기반 탭 전환 (세션시작 ↔ 기록)
  - 세션 진행 중이면 자동 전체화면 포커스 전환
  - 거치대 캘리브레이션 바텀시트 (설정 뷰 내 인라인 카드에서 바로 접근)
- [x] 기존 기능 100% 유지: 과목 CRUD, 거치대 자동 휴식, 화장실 타이머, 서브타이머, moveTaskToBack, foreground 서비스
- [x] Build OK + adb installed + logcat clean

### v9.3 Alarm Delete + Magnet Delete + Cradle Reimplement
- [x] **Part 1: 알람 전체 삭제**
  - `alarm_service.dart`, `alarm_settings_screen.dart` 삭제
  - `qr_wake_screen.dart`, `qr_setup_screen.dart` 삭제
  - `AlarmForegroundService.kt` 삭제
  - `AlarmReceiver`, `BootReceiver` 클래스 삭제 (MainActivity.kt)
  - ALARM_CHANNEL MethodChannel 핸들러 전체 삭제
  - `AlarmSettings` 모델 삭제 (models.dart)
  - AndroidManifest: SCHEDULE_EXACT_ALARM, USE_EXACT_ALARM, RECEIVE_BOOT_COMPLETED, USE_FULL_SCREEN_INTENT, REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, FOREGROUND_SERVICE_MEDIA_PLAYBACK 권한 삭제
  - AndroidManifest: AlarmForegroundService, AlarmReceiver, BootReceiver 등록 삭제
  - home_screen: 알람 import/field/load/checkPendingWake/toolCard 삭제
  - settings_screen: 배터리카드, 브리핑BGM카드, alarmChannel 삭제
  - nfc_service: AlarmService import + stopVibrationByNfc 호출 삭제
  - firebase_data_part: getAlarmSettings/saveAlarmSettings 삭제
- [x] **Part 2: 자석(magnetometer) 완전 삭제**
  - `magnet_service.dart` 삭제
  - app_init: MagnetService import/init 삭제
  - settings_screen: _magnetCard/_calibrateMagnet 전체 삭제
  - focus_screen: MagnetService import/field/init/dispose 삭제
- [x] **Part 3: 거치대 감지 가속도계 방식 구현**
  - `cradle_service.dart` 신규 생성 (CradleService singleton)
  - 가속도계 기반 (accelerometerEventStream, 200ms 샘플링)
  - 캘리브레이션: 5초 측정 → 평균 → Hive 저장
  - ON 감지: 10초 연속 안정 (분산 < 1.5)
  - OFF 감지: 3초 연속 불안정 (분산 > 3.0)
  - 히스테리시스 데드존 (1.5~3.0)
  - focus_screen: CradleService 연동 (cradleStream → onCradleChanged)
  - settings_screen: 거치대 감지 카드 (_cradleCard + _calibrateCradle)
  - app_init: CradleService().init()
- [x] Build OK + adb installed + logcat clean

### v9.2 Glassmorphism Remodel (Focus + Todo + Progress)
- [x] `focus_screen.dart` 전면 재작성: 글래스모피즘 설정뷰 + 원형 프로그레스 링 (gradient stroke, glow effect)
- [x] `focus_screen.dart`: staggered fade-in 애니메이션, 글래스 모드 버튼, 거치대/화장실/서브타이머 유지
- [x] `home_todo_section.dart` 전면 재작성: 글래스모피즘 카드, 원형 완료율 프로그레스
- [x] `home_todo_section.dart`: 커스텀 체크박스 (scale 애니메이션), 글래스 인라인 추가, weekly bar chart 유지
- [x] `progress_screen.dart` 전면 재작성: color-stripe 글래스 카드, gradient 프로그레스 바
- [x] `progress_screen.dart`: overall donut chart 헤더, 100% 완료 gold border + sparkle, 과목별 글래스 요약
- [x] 3파일 모두 테마 대응 (light/dark), BackdropFilter + ImageFilter.blur 글래스모피즘
- [x] 기존 기능 100% 유지: 과목 관리, 거치대, 화장실, 서브타이머, AI분석, 그룹, 실시간 동기화
- [x] Build OK + adb installed

### v9.1 NFC Remodel + GPS Removal
- [x] `ready` NFC 태그 역할 삭제 (6→5 roles: wake/outing/study/meal/sleep)
- [x] `NfcTagConfig.placeName` 필드 추가 (태그별 장소 연결)
- [x] 공부 재개 로직: 식사/외출 중 study 태그 → 자동 종료 + 공부 재개 (원래 시작시간 유지)
- [x] `location_service.dart` 전면 재작성 (1,108→46 lines, -96%): GPS one-shot only
- [x] 삭제: location_tracking_part.dart, location_data_part.dart, gps_timeline_widget.dart, location_screen.dart
- [x] `KnownPlace` 모델 삭제, `LocationState`/`MotionState` enum 삭제
- [x] `telegram_service.dart` 재작성: `sendNfc()` 양쪽 봇 동시 전송
- [x] `nfc_action_part.dart` 전면 재작성: 순공시간 계산, GPS one-shot (외출/식사), 새 Telegram 포맷
- [x] `order_models.dart`: `readyTime` 삭제 (RoutineTarget 4항목)
- [x] `order_today_tab.dart`: 레이더 5각→4각, 루틴 타임라인 4행, 설정 시트 4필드
- [x] `statistics_screen.dart`: GPS 동선/장소 UI 제거
- [x] `home_screen.dart`: LocationService, 위치 추적 UI, 타임라인 완전 제거
- [x] `firebase_data_part.dart`: saveKnownPlaces/getKnownPlaces 제거
- [x] Build OK + adb installed

### Phase 5: alarm_service.dart Simplification (483 -> 322 lines, -33%)
- [x] Removed dead methods: cacheBriefingData, cacheOpenAiKey, setVolumeMax, startPersistentVibration, cancelPendingQrWake, stopAlarmForegroundService, getTodayWakeTime
- [x] Removed dead _snooze + dead dismiss/snooze branches in _onTapped
- [x] Build OK + adb installed

### Phase 4: location_service.dart Simplification (1312 -> 1108 lines, -16%)
- [x] Split into 3 part files: location_service.dart (403) + location_tracking_part.dart (503) + location_data_part.dart (202)
- [x] Removed Google Places API dead code (~80 lines): `_tryNearbyPlaceName`, `_handleUnknownStay`, `_showUnknownPlaceNotification`, placeholder API key
- [x] Removed dead fields: `_unknownStayStart`, `_unknownStayNotified`, `_lastPlacesQuery/Result/Lat/Lng`
- [x] Removed dead methods: `getTodayTimeline`, `updateKnownPlace`
- [x] Removed dead model: `NearbyPlaceResult` from models.dart
- [x] Constants moved to library-level (accessible by all part files)
- [x] Build OK + adb installed

### Phase 3: nfc_service.dart Stabilization (1088 -> 813 lines, -25%)
- [x] Split into 2 part files: nfc_service.dart (524) + nfc_action_part.dart (289)
- [x] Unified `_dispatch()` — merged 3 duplicate role switch blocks (_executeRole, _handleAutoAction, manualTestRole)
- [x] `_withFields()` helper — eliminated 15x TimeRecord boilerplate construction
- [x] Constants moved to library-level (_nfcChannel)
- [x] Build OK + adb installed

### Phase 2: firebase_service.dart Split + Dead Code Removal (1626 -> 1284 lines)
- [x] Split into 4 part files: firebase_service.dart (core 279), firebase_study_part.dart (245), firebase_history_part.dart (411), firebase_data_part.dart (349)
- [x] Removed ~342 lines dead code: 8 path getters, 5 unused delegates, 5 invalidation stubs, updateOrderCache, getData, getJournals, deleteTimeRecord, getRecentDiaries, isRestDay, watchRestDays, getCompletionHistoryExtended, getDayDetail, getMonthSummary, getMultiMonthSummary, saveDayDiary, getDayDiary, getAllDayDiaries, watchLiveFocus, isOnline, 3 dead constants
- [x] Constants moved to library-level (accessible by all part files)
- [x] Build OK + adb installed

### Phase 1: Dead Service Cleanup (~4,500 lines deleted)
- [x] Deleted 10 files: focus_timer_service, focus_mode_service, ai_calendar_service, sleep_service, briefing_service, meal_photo_service, exam_ticket_service, focus_session_screen, meal_photo_screen, calendar_dashboard_widget
- [x] Cleaned 16+ referencing files: app_init, main, home_screen (+ 4 part files), calendar_screen (+ 3 part files), settings_screen, nfc_service, statistics_screen, order_goals_tab, models.dart, firebase_service
- [x] Removed from firebase_service: runReverseMigration, migrateDateRecords, migrateToTodayHistory, diagnosePhaseCData, ensureHistoryExists, FocusMode/Sleep CRUD (~470 lines)
- [x] Removed from models.dart: FocusModeConfig, AppUsageStat, SleepSettings, SleepRecord, SleepGrade
- [x] Build OK + adb installed

## 2026-03-07
### v9.0 NFC Remodel (ChangeNotifier + ListenableBuilder)
- [x] `NfcService` — ChangeNotifier 싱글톤 (콜백 패턴 → notifyListeners)
  - `onStateChanged` 콜백 제거 → `addListener`/`removeListener` (ChangeNotifier 표준)
  - `onNfcAction` 콜백 제거 → `NfcAction` 모델 + `consumeLastAction()` 패턴
  - 모든 role 핸들러에서 `_emitAction()` → `notifyListeners()` 자동 UI 갱신
- [x] `NfcScreen` — `lib/screens/nfc/nfc_screen.dart` (ListenableBuilder 기반)
  - 상태 칩: 외출/공부/식사 3열 표시 (기존 2열 → 3열)
  - 수동 테스트 섹션 추가 (모든 role 즉시 실행 가능)
  - 태그 카드 메뉴에 '수동 실행' 옵션 추가
  - 역할 요약에 취침(sleep) 아이콘 추가 (6개 역할 모두 표시)
  - setState는 로컬 UI 상태(스캔/등록)에만 사용
- [x] `home_screen.dart` — NFC 콜백 → `addListener(_onNfcChanged)` 패턴 전환
- [x] import 전면 업데이트: `nfc_screen.dart` → `nfc/nfc_screen.dart`
### v7.0 Focus Zone Remodel (ChangeNotifier + ListenableBuilder)
- [x] `FocusService` — ChangeNotifier 싱글톤 (`focus_timer_service.dart` 대체)
  - UI 타이머, 거치대, 화장실, 서브타이머 상태를 서비스에 통합
  - `notifyListeners()` 로 UI 자동 갱신 (setState 불필요)
- [x] `FocusScreen` — ListenableBuilder 기반 (`focus_session_screen.dart` 대체)
  - 설정 뷰 + 전체화면 몰입형 포커스 + 과목 관리 + 기록 링크
  - setState 사용 금지 (setup local state 제외)
- [x] `focus_result_sheet.dart` — 세션 완료 결과 다이얼로그 분리
- [x] `focus_history_screen.dart` — 포커스 기록 화면 분리 (조회/수정/삭제/수동추가)
- [x] import 전면 업데이트: `app_init`, `home_screen`, `home_focus_section`
- [x] 기존 기능 100% 유지: 거치대 자동 휴식, 화장실 타이머, 문제 서브타이머, 과목 CRUD, 수동 세션 추가, 90분 사이클 바, 순공시간 계산, Firebase 동기화, 포그라운드 서비스
### v6.2 과거기록 복구 + Hive 안정화
- [x] Hive Timestamp 직렬화 오류 수정 — `_sanitize()` 재귀 변환 (Timestamp → milliseconds)
- [x] Hive 역직렬화 타입 오류 수정 — `_deepCast()` 재귀 변환 (Map<dynamic,dynamic> → Map<String,dynamic>)
- [x] `getFocusCycles()`, `getTimeRecords()`, `getStudyTimeRecords()` 안전 캐스팅 (Map.from)
- [x] `getDayDiary()`, `getAllDayDiaries()`, `getCustomStudyTasks()` 안전 캐스팅
- [x] `renameTimeRecordDate()` 안전 캐스팅 (trRaw, strRaw, fcRaw)
- [x] `autoArchive()` → history 문서에도 동시 저장 (캘린더 호환)
- [x] calendar_screen: history → archive → study 3단 fallback
- [x] `_archiveToHistoryFormat()` archive→history 형식 변환 헬퍼
- [x] `diagnosePhaseCData()` 진단 함수 (Hive/Firestore cache/server 상태 확인)
- [x] `ensureHistoryExists()` history 비어있으면 마이그레이션 재실행
- [x] `focus_session_screen` _endBathroomBreak async→sync 수정 (빌드 에러)
- [x] 텔레그램 라우팅 확인: sendToGf(NFC/알람), sendToMe(배포/날씨) — 이미 정상
### 디버그 로그
- Hive: 10 keys, study 17 fields, today date=2026-03-07
- study doc: timeRecords 7일, studyTimeRecords 5일, focusCycles 5일
- today doc: 존재 (Firestore cache), studyTime.total=0
- history: Firestore cache 없음 (서버 timeout — WiFi 필요)
- `_Map<dynamic,dynamic>` cast error 해결됨
- `HiveError: Timestamp` 해결됨
- 디바이스 인터넷 미연결 상태에서 테스트

## 2026-03-06
### v6.0 Phase C: Today + Monthly History
- [x] firebase_service — today 문서 CRUD, history 문서 CRUD
- [x] 4AM 일전환 자동 아카이빙 (checkDayRollover)
- [x] migrateToTodayHistory() 1회 마이그레이션
- [x] home_screen — today 문서 우선 읽기
- [x] calendar_screen — history 문서 우선 + study fallback
- [x] focus_timer — today.studyTime + history 세션 추가
- [x] todo_service — today.todos 동기화
### v5.7 시간대별 배경
- [x] habitat_background — dawn/day/evening/night 분기
### v5.6 배경 이미지 교체
- [x] Canvas 렌더링 → 이미지 에셋 교체
### v5.5 호그와트 도서관
- [x] 전면 재작성: 석벽+고딕아치+스테인드글라스+샹들리에
- [x] NFC 텔레그램 meal_start/meal_end/study_end 추가
### v5.4 스프라이트 + 자석거치대
- [x] SpriteItemDef 시스템, 자석거치대 서비스
### v5.3 Library Full-Screen
- [x] 비율 기반 전면 재작성, NPC 고양이/부엉이
### v5.2 Cached Rendering
- [x] PictureRecorder 배경 캐싱
### v5.1 Pixel Art Rewrite
- [x] 32색 마스터팔레트, 프로시저럴 책장
### v5.0 Study Creature + Hive
- [x] Flame 게임 엔진, creature_service, Hive 캐시
### v4.6 텔레그램 알림 (다영)
- [x] NFC 태그 시 다영 텔레그램 알림, 수동 "다영에게 알리기" 버튼
### v4.5 setState 전면 교체 + 3-layer 캐시 + 2컬럼 레이아웃
- [x] 모든 화면 _safeSetState 교체, firebase 3-layer 캐시, 대시보드 2컬럼
### v4.4 크래시 안정화
- [x] _safeSetState SchedulerBinding 패턴, write 보호
### v4.3.1 로컬 퍼스트 아키텍처
- [x] 행동 타임라인 캐시, Optimistic UI, NFC fallback

## 2026-03-05
### v3~v4 안정화
- [x] Phase B 문서 분리 → 역마이그레이션 (단일 study doc)
- [x] 캘린더 무한로딩 수정, 투두 삭제/수정
- [x] LocalCacheService (SharedPreferences 기반)
- [x] home_screen 로컬 캐시 우선 + Firebase 백그라운드 갱신
- [x] _safeSetState 헬퍼 전면 도입

## 로그 키워드
- `[Diag]` — Phase C 진단
- `[Migration-C]` — Phase C 마이그레이션
- `[Rollover]` — 4AM 일전환 아카이빙
- `[Archive]` — 7일 이전 데이터 월별 아카이브
- `[FB]` — Firestore 캐시/서버 읽기
- `[Home]` — 홈 화면 각 문서 로드
- `[LocalCache]` — Hive 캐시 저장/읽기
- `[Telegram]` — 텔레그램 전송

## Firestore 문서 구조 (Phase C)
| 문서 | 필드 | 크기 목표 |
|------|------|-----------|
| data/today | date, timeRecords, studyTime, todos, orderData | ~2KB |
| data/study | timeRecords, studyTimeRecords, focusCycles, todos, orderData (레거시) | ~50KB |
| data/creature | creature data | ~1KB |
| data/liveFocus | 실시간 포커스 | ~1KB |
| history/{yyyy-MM} | month, days.{dd}, summary | ~7KB/월 |
| archive/{yyyy-MM} | timeRecords, studyTimeRecords, focusCycles, todos (월별) | ~10KB/월 |
