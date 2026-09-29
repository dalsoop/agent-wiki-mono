# 0003. 공유 원장 전송은 git seed + pull-only 피어, blob은 S3 호환 저장소로 한다

## 맥락

2026-07-29 이전에는 syncthing으로 Mac 사이에 원장을 복제했다. 이 전송로가 몇 주 동안 조용히 멈춰 있었는데(서버 폴더 0파일, 옆 Mac 데몬 미실행) 아무도 알지 못했다. mesh 복제에는 앞섬·뒤처짐 개념이 없어 뒤처짐이 어디에도 보이지 않았기 때문이다.

## 결정

- `gujo-wiki`의 텍스트 원장(`objects`, `events`)은 git으로 옮긴다. GitLab 원격(origin)이 seed이고, `gujo sync`는 origin과 fetch·merge·push를 한다.
- 다른 Mac은 피어 remote로 등록하되 push를 끈다. 피어에서는 fetch·merge만 한다.
- 대용량 `blobs`는 git 밖에서 S3 호환 저장소와 차집합으로 주고받는다. 2026-08에 저장소를 garage에서 Cloudflare R2로 옮겼고, 버킷 이름과 키 구조(`blobs/<앞 2자>/<sha256>`)는 그대로다.
- 이 계층의 첫 책임은 뒤처짐을 보이게 하는 것이다. `gujo status`는 네트워크 없이 마지막 sync 시각, 피어 ahead 수, 마지막으로 관측한 원격 전용 blob 수를 보여 준다.

## 대안

- syncthing mesh 유지: 실패가 보이지 않는 문제를 겪었으므로 택하지 않았다.
- 피어끼리 push 허용: 체크아웃된 브랜치에 push하는 사고가 날 수 있고, append-only union merge와 맞지 않아 택하지 않았다.

## 결과

- 원격 전송에 git·네트워크·GitLab 인증이 필요하고, merge 충돌은 사람이 풀어야 한다.
- blob은 내용 주소라 받은 뒤 sha256을 다시 계산해 검증할 수 있고, 삭제 연산은 없다.
- push 실패는 sync 실패가 아니라 결과의 `pushed=false`로 남으므로 호출하는 쪽이 확인해야 한다.
