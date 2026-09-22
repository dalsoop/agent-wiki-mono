import Foundation

/// 함대 공용 UI 문구 사전 — 2026-08-30 함대 전수 빈도 실측 TOP 200.
///
/// 앱이 각자 `"취소"`를 하드코딩하는 대신 이 공용 키를 쓴다.
/// `app-i18n-inspector fix` 가 첫 참조 대상으로 쓴다 — 공용 사전에 있으면
/// 앱별 키 생성 없이 바로 치환한다(31% 커버).
public enum CommonL10n: String, CaseIterable, LocalizationKey {

    /// 취소
    case commonCancel = "common.commonCancel"
    /// 삭제
    case commonDelete = "common.commonDelete"
    /// 저장
    case commonSave = "common.commonSave"
    /// 이름
    case name = "common.name"
    /// 설정
    case settings = "common.settings"
    /// 새로고침
    case refresh = "common.refresh"
    /// 추가
    case commonAdd = "common.commonAdd"
    /// 제목
    case title = "common.title"
    /// 닫기
    case commonClose = "common.commonClose"
    /// 메모
    case note = "common.note"
    /// 비밀번호
    case password = "common.password"
    /// 확인
    case commonOK = "common.commonOK"
    /// 포트
    case port = "common.port"
    /// 다시 불러오기
    case reload = "common.reload"
    /// 저장 전 확인 %1개
    case confirmBeforeSaveCount = "common.confirmBeforeSaveCount"
    /// 검색
    case search = "common.search"
    /// 없음
    case none = "common.none"
    /// 종류
    case type = "common.type"
    /// 회사
    case company = "common.company"
    /// 로드
    case load = "common.load"
    /// 이메일
    case email = "common.email"
    /// 표시 이름
    case displayName = "common.displayName"
    /// 한국어
    case korean = "common.korean"
    /// 전체
    case all = "common.all"
    /// 완료
    case done = "common.done"
    /// 재생
    case play = "common.play"
    /// 찾기
    case find = "common.find"
    /// 호스트
    case host = "common.host"
    /// 프로젝트
    case project = "common.project"
    /// 사용자
    case user = "common.user"
    /// 프로젝트 이름
    case projectName = "common.projectName"
    /// 선택
    case select = "common.select"
    /// 내장
    case builtIn = "common.builtIn"
    /// Vault credential ID (선택 핀)
    case vaultCredentialIdOptionalPin = "common.vaultCredentialIdOptionalPin"
    /// 선택…
    case selectEllipsis = "common.selectEllipsis"
    /// 연결 해제
    case disconnect = "common.disconnect"
    /// 다시 시도
    case retry = "common.retry"
    /// 만들기
    case create = "common.create"
    /// 역할
    case role = "common.role"
    /// 정렬
    case sort = "common.sort"
    /// 스캔
    case scan = "common.scan"
    /// 할 일
    case todo = "common.todo"
    /// 승인
    case approve = "common.approve"
    /// 배포
    case deploy = "common.deploy"
    /// 경로
    case path = "common.path"
    /// 이름 (필수)
    case nameRequired = "common.nameRequired"
    /// 시작
    case start = "common.start"
    /// 요약
    case summary = "common.summary"
    /// 상태
    case status = "common.status"
    /// 적용
    case apply = "common.apply"
    /// 반복
    case `repeat` = "common.repeat"
    /// 블록 추가
    case addBlock = "common.addBlock"
    /// 블록
    case block = "common.block"
    /// 새 스펙
    case newSpec = "common.newSpec"
    /// 빌드
    case build = "common.build"
    /// 새 그림
    case newDrawing = "common.newDrawing"
    /// 주소
    case address = "common.address"
    /// 제목 *
    case titleAsterisk = "common.titleAsterisk"
    /// 값
    case value = "common.value"
    /// 직접 입력
    case manualInput = "common.manualInput"
    /// 전화
    case phone = "common.phone"
    /// 손가락으로 그리기
    case drawWithFinger = "common.drawWithFinger"
    /// 폴더 이름
    case folderName = "common.folderName"
    /// 출처
    case source = "common.source"
    /// 프로젝트 홈
    case projectHome = "common.projectHome"
    /// 새 프로젝트
    case newProject = "common.newProject"
    /// 이미지
    case image = "common.image"
    /// 필터 초기화
    case resetFilters = "common.resetFilters"
    /// 결과 열기
    case openResults = "common.openResults"
    /// 복사
    case copy = "common.copy"
    /// 휴지통
    case trash = "common.trash"
    /// 버전 기록
    case versionHistory = "common.versionHistory"
    /// 기기
    case device = "common.device"
    /// 환경
    case environment = "common.environment"
    /// 상태 변경
    case changeStatus = "common.changeStatus"
    /// 연락처
    case contacts = "common.contacts"
    /// 통화
    case call = "common.call"
    /// 원하는 결과
    case desiredResult = "common.desiredResult"
    /// 사람 또는 에이전트
    case personOrAgent = "common.personOrAgent"
    /// 마감
    case dueDate = "common.dueDate"
    /// 종료
    case end = "common.end"
    /// 회사 ID
    case companyId = "common.companyId"
    /// 공고 ID
    case noticeId = "common.noticeId"
    /// 생성
    case generate = "common.generate"
    /// 지역
    case region = "common.region"
    /// 프로젝트 경로
    case projectPath = "common.projectPath"
    /// 토큰
    case token = "common.token"
    /// 규칙 이름
    case ruleName = "common.ruleName"
    /// 화면
    case screen = "common.screen"
    /// 원격 상태
    case remoteStatus = "common.remoteStatus"
    /// 호스트 (예: 192.168.2.10)
    case hostExample = "common.hostExample"
    /// 정보
    case info = "common.info"
    /// 설정 열기
    case openSettings = "common.openSettings"
    /// 검증
    case verify = "common.verify"
    /// 연결
    case connect = "common.connect"
    /// 항목을 선택하세요
    case selectAnItem = "common.selectAnItem"
    /// 프리셋
    case preset = "common.preset"
    /// 너비
    case width = "common.width"
    /// 높이
    case height = "common.height"
    /// 진단
    case diagnostics = "common.diagnostics"
    /// 바꾸기
    case replace = "common.replace"
    /// 모든 그림
    case allDrawings = "common.allDrawings"
    /// 상세
    case details = "common.details"
    /// 클립보드 릴레이
    case clipboardRelay = "common.clipboardRelay"
    /// 토큰 값
    case tokenValue = "common.tokenValue"
    /// 또는 Secret
    case orSecret = "common.orSecret"
    /// 시키기
    case dispatch = "common.dispatch"
    /// 등록
    case register = "common.register"
    /// 정지
    case stop = "common.stop"
    /// 다시 연결
    case reconnect = "common.reconnect"
    /// 편집
    case edit = "common.edit"
    /// 상호
    case tradeName = "common.tradeName"
    /// 사업자등록번호
    case businessRegistrationNumber = "common.businessRegistrationNumber"
    /// OCR 실행
    case runOcr = "common.runOcr"
    /// 접속 설정
    case connectionSettings = "common.connectionSettings"
    /// 계정 확인
    case verifyAccount = "common.verifyAccount"
    /// 보내기
    case send = "common.send"
    /// 새 이름
    case newName = "common.newName"
    /// 브리지
    case bridge = "common.bridge"
    /// 스토리지
    case storage = "common.storage"
    /// 위 확인 문자열 입력
    case enterConfirmationString = "common.enterConfirmationString"
    /// 한글에서 열기
    case openInHangul = "common.openInHangul"
    /// 대체 텍스트
    case alternativeText = "common.alternativeText"
    /// 작업 디렉터리
    case workingDirectory = "common.workingDirectory"
    /// 취소
    case undo = "common.undo"
    /// 서명하고 보내기
    case signAndSend = "common.signAndSend"
    /// PDF를 열어 바로 서명합니다
    case openPdfAndSign = "common.openPdfAndSign"
    /// 새 서명
    case newSignature = "common.newSignature"
    /// 폴더로 이동
    case moveToFolder = "common.moveToFolder"
    /// 6자리 코드
    case sixDigitCode = "common.sixDigitCode"
    /// 분류
    case category = "common.category"
    /// 실행 로그
    case runLog = "common.runLog"
    /// 명명 불일치 — 실물 '%1' → spec 이름으로 리네이밍 대상
    case namingMismatchRenameTarget = "common.namingMismatchRenameTarget"
    /// 대기
    case pending = "common.pending"
    /// 생성 큐
    case generationQueue = "common.generationQueue"
    /// Curate 열기
    case openCurate = "common.openCurate"
    /// 산출 없음
    case noOutput = "common.noOutput"
    /// 코멘트
    case comment = "common.comment"
    /// 배경
    case background = "common.background"
    /// 확대
    case zoomIn = "common.zoomIn"
    /// 테넌트 slug
    case tenantSlug = "common.tenantSlug"
    /// 점수 %1
    case scoreValue = "common.scoreValue"
    /// 파일 선택
    case chooseFile = "common.chooseFile"
    /// 폴더 선택
    case chooseFolder = "common.chooseFolder"
    /// 공급자 설정
    case providerSettings = "common.providerSettings"
    /// 합성 문서 r%1
    case composedDocumentRevision = "common.composedDocumentRevision"
    /// 열기
    case open = "common.open"
    /// Figma에 적용
    case applyToFigma = "common.applyToFigma"
    /// AI 생성
    case generateWithAI = "common.generateWithAI"
    /// 제외
    case exclude = "common.exclude"
    /// 섹션 추가
    case addSection = "common.addSection"
    /// 설정 저장
    case saveSettings = "common.saveSettings"
    /// 선행 단계
    case prerequisiteSteps = "common.prerequisiteSteps"
    /// 활성 실행
    case activeRun = "common.activeRun"
    /// 실행 기록
    case runHistory = "common.runHistory"
    /// 템플릿 라이브러리
    case templateLibrary = "common.templateLibrary"
    /// 업종
    case industry = "common.industry"
    /// 독해 패턴
    case readingPattern = "common.readingPattern"
    /// 성격
    case personality = "common.personality"
    /// 복제
    case duplicate = "common.duplicate"
    /// 필수
    case required = "common.required"
    /// 강조 색상
    case accentColor = "common.accentColor"
    /// 텍스트
    case text = "common.text"
    /// 도형
    case shape = "common.shape"
    /// 범위
    case scope = "common.scope"
    /// 위
    case top = "common.top"
    /// 아래
    case bottom = "common.bottom"
    /// 온보딩
    case onboarding = "common.onboarding"
    /// 생성 방식
    case generationMethod = "common.generationMethod"
    /// 미리보기 실패
    case previewFailed = "common.previewFailed"
    /// 라이브러리
    case library = "common.library"
    /// 미리보기
    case preview = "common.preview"
    /// job 폴더 경로 (jobs/<id>)
    case jobFolderPath = "common.jobFolderPath"
    /// track.wav 경로
    case trackWavPath = "common.trackWavPath"
    /// dub.<lang>.srt 경로
    case dubSrtPath = "common.dubSrtPath"
    /// 비우기
    case empty = "common.empty"
    /// 새 분류
    case newCategory = "common.newCategory"
    /// 사용 방법과 설정
    case howToUseAndSettings = "common.howToUseAndSettings"
    /// 분류 해제
    case uncategorize = "common.uncategorize"
    /// 새 분류…
    case newCategoryEllipsis = "common.newCategoryEllipsis"
    /// 새 기록
    case newRecord = "common.newRecord"
    /// 공유
    case share = "common.share"
    /// 최근순
    case newestFirst = "common.newestFirst"
    /// 중요순
    case byImportance = "common.byImportance"
    /// 태그
    case tags = "common.tags"
    /// 새 메모
    case newNote = "common.newNote"
    /// 경로 (…/swift-app-mono/main)
    case pathMonoMainExample = "common.pathMonoMainExample"
    /// 계정 토큰 붙여넣기
    case pasteAccountToken = "common.pasteAccountToken"
    /// 맥 앱 → 손님
    case macAppToGuest = "common.macAppToGuest"
    /// 설치 버튼과 공증 제출 버튼은 없다. 수정이 남은 동안 ADM 큐에 넣지 않는다.
    case noInstallOrNotarizeWhileDirty = "common.noInstallOrNotarizeWhileDirty"
    /// 공증은 지금 제출하지 않는다. 이 화면은 배포 칸과 소유 앱을 한곳에 둔 보드다.
    case notarizeDeferredDeployBoard = "common.notarizeDeferredDeployBoard"
    /// 불러오는 중
    case loading = "common.loading"
    /// 소유 앱 열기
    case openOwnerApp = "common.openOwnerApp"
    /// 스냅샷 다시 읽기
    case reloadSnapshot = "common.reloadSnapshot"
    /// 트랙
    case track = "common.track"
    /// 대상 · %1  ·  %2
    case targetProductRuntime = "common.targetProductRuntime"
    /// 판매 가능 — 갭 없음
    case sellableNoGaps = "common.sellableNoGaps"
    /// 이 자리에 %1 전용 작업 UI 가 들어갑니다 (해당 Kit 구현 예정).
    case stageWorkUiPlaceholder = "common.stageWorkUiPlaceholder"
    /// 01 · 재고 — 작업 큐
    case inventoryJobQueue01 = "common.inventoryJobQueue01"
    /// 콘텐츠 작업 남은 제품을 골라 실행 · 카탈로그 %1개
    case contentWorkRemainingCatalog = "common.contentWorkRemainingCatalog"
}
