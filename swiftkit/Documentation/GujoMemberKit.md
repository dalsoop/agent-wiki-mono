# GujoMemberKit

회원(고객) 모델·검색·기기·구독 요약 뷰모델. 네트워크 없음.

Support Desk · Seller Ops · Customer Manager 가 제각각 들고 있던 `Customer`/`StaffCustomer` 합집합이다. 소비 앱은 이 킷의 `Member` 와 `MemberCardViewModel` 을 쓰고, HTTP 는 각 앱(또는 이후 `GujoStaffAPIKit`)이 담당한다.

## 타입

- `Member` — `id`, `name`, `email`, `locale`, `createdAt`, `tags`
- `MemberDevice` — 기기 한 대 (`active`, `lastUsedAt`, …)
- `MemberSubscriptionSummary` — 구독 한 줄
- `MemberRecentInquiry` — 고객 카드의 최근 문의 슬롯
- `MemberSearchQuery` — 쿼리스트링 직렬화 (`serializedQuery`)
- `MemberCardViewModel` — 요약·기기·구독·최근 문의
- `PIIRetentionPolicy` — 기본 1095일(3년). 만료 판정·이메일/이름 마스킹. Service Mailer 의 로컬 규칙을 여기로 올렸다(메일러 소스는 그대로).

## JSON

`MemberJSON.decoder()` 가 Int/String id 와 ISO-8601(분수초 포함) 을 받는다. 픽스처는 서버 응답 형태:

- `GET /api/commerce/staff/customers`
- `GET /api/commerce/staff/customers/{id}` + devices
- `GET /api/support/staff/inquiries`

## 소비

첫 소비자는 `apps/gujo-support-desk-swift` 고객 카드 화면이다.
