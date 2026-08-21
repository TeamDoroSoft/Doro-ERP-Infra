# IAM 리소스 정리 및 Bootstrap State 협의사항

xlsx(`Doro_Team2_IAM_정책설명포함.xlsx`) 분석하다가 Terraform으로 관리 안 되는 IAM 리소스들 발견해서 AWS CLI(profile: `team2`, 계정 `727646470302`)로 하나씩 실측 조사한 내용 정리. 담당자 확인/협의 필요한 부분 위주로 남김.

## 1. 제외 확정 — team2-doroload 계열 (이전 프로젝트 잔재)

대상:
- Role: `team2-doro-eks-loadbalanceController-role`, `team2-doro-secret-iam-role`, `team2-doroload-auto-cluster-role`, `team2-doroload-auto-node-role`, `team2-doroload-ssm-role`
- Policy: `team2-doro-ALB-Controller-IAM-Policy`, `team2-doro-secrets-read`, `team2-doro-collector-s3-access`

확인 근거:
- IAM `RoleLastUsed` 전부 2026-07-24~28에 멈춰있음 (오늘까지 갱신 없음)
- CloudTrail(ap-northeast-2 + us-east-1) 이벤트 히스토리 조회해도 해당 role 관련 이벤트 0건
- 관련 EC2 인스턴스 0대, EKS 클러스터도 이미 삭제됨 (`aws eks list-clusters` 결과 `doro-erp-dev`, `team1-eks`뿐)
- 팀 확인: 이전 프로젝트(DoroLoad EKS)에서 쓰던 권한 맞음, 앞으로 배제하기로 함

주의: `team2-doroload-ssm-access-policy`는 이름이 비슷하지만 **다른 리소스**. 죽은 role이 아니라 지금도 활성 상태인 `team2-doro-load-group`에 붙어있는 정책이라 제외 대상 아님 (아래 3번 참고).

## 2. doro-erp-service-ecr-publisher — 콘솔 수동 생성 확인, import 보류 중

CloudTrail(us-east-1)로 확인:
- 오늘(2026-08-20) `a-student-02`가 AWS 콘솔에서 수동 생성 (`CreateRole` 이벤트의 userAgent가 Chrome 브라우저, `sessionCredentialFromConsole: true`)
- 이후 1시간 동안 `UpdateAssumeRolePolicy`를 6번 재호출하며 trust policy subject 형식을 계속 고침 (중간에 JSON 문법 오류로 한 번 실패한 기록도 있음) — GitHub Actions가 계속 실패해서 콘솔에서 직접 붙잡고 고친 흔적
- 기존 `doro-erp-dev-github-ecr-push` role(bootstrap 관리)과 권한이 완전히 겹침: ECR push 범위(`doro-erp-{edge,store-access,commerce,payment,queue,audit}`)가 기존 role의 `doro-erp-*` 와일드카드의 부분집합이고, immutable GitHub OIDC subject도 이미 `var.github_ecr_subjects`에 등록돼 있음

진행 상황:
- Terraform 코드는 "일단 현재 상태 그대로 편입" 방향으로 작성 완료 — `bootstrap/doro-erp-service-ecr-publisher.tf`, `bootstrap/locals.tf`, `bootstrap/iam.tf` 수정, `terraform validate` 통과
- 코드에 "KNOWN DUPLICATE — pending consolidation review" 주석 남겨둠. `iam:CreateRole`/`iam:CreatePolicy` 권한은 의도적으로 안 줘서, Terraform으로 삭제는 가능하지만 재생성은 안 되게 해둠
- **아직 `terraform import` / `apply` 안 함** — 아래 4번 state 문제 때문에 보류 중
- 나중에 Doro-ERP-Service GitHub Actions workflow를 기존 `doro-erp-dev-github-ecr-push`로 옮기기로 하면, 이 파일 + 관련 statement 삭제하고 이 role/policy는 콘솔에서 정리하면 됨

## 3. team2-doro-load-group — xlsx에 없던 신규 발견, 활성 그룹

- 멤버 5명: `a-student-02`, `a-student-06`, `b-student-11`, `b-student-05`, `cld-team2-doro-github-action` (오늘/어제 로그인 기록 있음)
- 관리형 정책 1개(`team2-doroload-ssm-access-policy`) + 인라인 정책 3개(`EKS-Direct-Console-Access`, `team2-doro-load-ecr-push-policy`, `team2-doro-load-s3-frontend-policy`) 확인 완료
- `EKS-Direct-Console-Access`만 Resource가 `*`로 열려있어서 계정 내 모든 EKS 클러스터 조회 가능한 상태 — 나머지 둘은 team2 소유 리소스로 정확히 스코프됨

진행 상황:
- Terraform 코드 작성 완료 — `bootstrap/team2-doro-load-group.tf` (Group + 인라인 정책 3개 + 관리형 정책 attachment + 멤버십), `bootstrap/locals.tf`/`bootstrap/iam.tf`에 권한 statement 추가, `terraform validate` 통과
- ⚠️ **주의**: `aws_iam_group_membership`은 배타적(authoritative) 리소스라, apply하는 순간 코드에 없는 멤버는 그룹에서 자동으로 빠짐. import 직전에 `aws iam get-group`으로 실제 멤버십 다시 확인 필요 (특히 `b-student-05` 본인 계정 포함돼 있음)
- **아직 import/apply 안 함**

## 4. Bootstrap state 소재 문제 — 별도 문서로 분리함

`ERP/Bootstrap_Terraform_State_이슈_보고서.md`로 옮겼음. a-student-06과 협의할 내용이라 Infra 하위가 아니라 ERP 루트에 둠.

## 다음 단계

- [ ] a-student-06과 bootstrap state 소재 확인 협의 (별도 문서 참고)
- [ ] state 확보되면 `team2-doro-load-group`, `doro-erp-service-ecr-publisher` import 진행
- [ ] `doro-erp-service-ecr-publisher`는 통합(consolidation) 여부 팀 논의 후 재결정
- [x] `doro-erp-dev-management`의 인라인 정책 2개(`DoroERPDevEKSConnectPolicy`, `DoroErpEcrDescribeImages`) — dev 환경 state가 정상이라 bootstrap 문제와 무관하게 바로 진행 가능, 아래에서 작업
