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

## 2. doro-erp-service-ecr-publisher — 콘솔 수동 생성 확인, 통합 방향 확정됨

CloudTrail(us-east-1)로 확인:
- 8/20 `a-student-02`가 AWS 콘솔에서 수동 생성 (`CreateRole` 이벤트의 userAgent가 Chrome 브라우저, `sessionCredentialFromConsole: true`)
- 이후 1시간 동안 `UpdateAssumeRolePolicy`를 6번 재호출하며 trust policy subject 형식을 계속 고침 (중간에 JSON 문법 오류로 한 번 실패한 기록도 있음) — GitHub Actions가 계속 실패해서 콘솔에서 직접 붙잡고 고친 흔적

**통합 방향 확정 (2026-08-21)**: `doro-erp-dev-github-ecr-push`는 `RoleLastUsed`가 계속 비어있어서(`{}`) **한 번도 assume된 적이 없다는 게 확인됨.** 반면 Doro-ERP-Service의 실제 GitHub Actions workflow(`publish-ecr.yml`)는 GitHub Environment 변수 `AWS_ECR_PUSH_ROLE_ARN`(dev)을 읽는데, 그 값이 이미 `doro-erp-service-ecr-publisher`를 가리키고 있었음 — 즉 실제로 쓰이는 쪽은 처음부터 이거였음. **`doro-erp-service-ecr-publisher`를 정식/영구 리소스로 확정하고 `doro-erp-dev-github-ecr-push`는 제거하는 방향으로 진행.**

진행 상황:
- `bootstrap/doro-erp-service-ecr-publisher.tf` import 완료, 태그 3건만 diff(무해, 아직 미적용)
- 통합 작업: `bootstrap/iam.tf`에서 `doro-erp-dev-github-ecr-push` role/inline policy/trust policy 데이터소스 삭제, `doro-erp-service-ecr-publisher`에 `iam:CreateRole`/`iam:CreatePolicy` 추가해서 정식 lifecycle 관리로 전환, `bootstrap/variables.tf`의 `github_ecr_subjects`·`bootstrap/locals.tf`의 `github_ecr_role_name` 정리
- `terraform/environments/dev/github-actions.tf`의 `data "aws_iam_role"` 조회 대상도 `doro-erp-service-ecr-publisher`로 변경 (안 그러면 dev 스택의 data lookup이 깨짐)
- 검증: bootstrap plan → `0 add, 4 change(태그+trust policy statement), 2 destroy(안 쓰인 role+policy)`. dev 환경 plan → output 값만 변경, 실제 인프라 변경 없음
- GitHub Actions workflow는 이미 `doro-erp-service-ecr-publisher`를 가리키고 있어서 **이번 변경으로 workflow 자체는 전혀 안 바뀜**
- trust policy(mutable/immutable subject 혼용)는 이번 범위에서 제외 — 안정화 후 별도 진행
- **아직 apply 안 함** — [PR #16](https://github.com/TeamDoroSoft/Doro-ERP-Infra/pull/16)에 코드 반영, 리뷰 대기 중

## 3. team2-doro-load-group — xlsx에 없던 신규 발견, 그룹은 관리 안 하기로 범위 축소

- 멤버 5명: `a-student-02`, `a-student-06`, `b-student-11`, `b-student-05`, `cld-team2-doro-github-action`
- 관리형 정책 1개(`team2-doroload-ssm-access-policy`) + 인라인 정책 3개(`EKS-Direct-Console-Access`, `team2-doro-load-ecr-push-policy`, `team2-doro-load-s3-frontend-policy`) 확인
- CloudTrail·리소스 존재 여부로 실사용 재확인한 결과: `team2-doro-load-ecr-push-policy`(대상 ECR repo 삭제됨), `team2-doro-load-s3-frontend-policy`(대상 S3 버킷 삭제됨), `EKS-Direct-Console-Access`(사용 이력 0건) 3개는 전부 죽은 권한. `team2-doroload-ssm-access-policy`만 실사용 확인(우연히 `Team=team2` 태그가 현재 프로젝트의 management EC2에도 걸림)

**범위 축소 결정**: Group 전체(멤버십 포함)를 편입하지 않고, 실사용 확인된 `team2-doroload-ssm-access-policy` **정책 내용만** 관리. `aws_iam_group_membership`의 배타적 동작으로 인한 멤버 축출 리스크를 죽은 정책들 때문에 감수할 이유가 없다고 판단.

진행 상황: `bootstrap/team2-doroload-ssm-access-policy.tf` import 완료, [PR #16](https://github.com/TeamDoroSoft/Doro-ERP-Infra/pull/16)에 반영.

## 4. cld-team2-doro-github-action (IAM User) — 이것도 이전 프로젝트 잔재

- 인라인 정책 `DoroCloudFrontInvalidationPolicy`(CloudFront distribution `E3RZHD5Y24C4BO`, comment `team2-doro-cloud-front`, alias `doro.beam0331.click`)가 직접 붙어있음
- Username으로 정확히 필터링한 CloudTrail 확인 결과 활동이 전부 2026-07-22~24에 몰려있고 이후 이벤트 0건 — team2-doroload 계열과 같은 시기, 같은 패턴. 3개 저장소(Front/Service/Infra) 어디에도 이 User·정책·distribution을 참조하는 코드 없음
- **제외 대상으로 분류.** 다만 이 User에 **활성 상태인 장기 Access Key가 2개**(7/20, 7/22 생성, 한 달간 미사용) 남아있어서, Terraform 관리 여부와 별개로 **비활성화/삭제 권장** — 아직 미처리

## 5. Bootstrap state 소재 문제 — 해결됨

별도 문서(`ERP/Bootstrap_Terraform_State_이슈_보고서.md`)에서 다루던 문제. `s3://doro-erp-dev-tfstate-.../bootstrap/terraform.tfstate`에 이미 백업돼 있던 state를 검증 후 [PR #15](https://github.com/TeamDoroSoft/Doro-ERP-Infra/pull/15)로 정식 S3 backend 마이그레이션 완료.

## 다음 단계

- [x] bootstrap state S3 backend 마이그레이션 (PR #15)
- [x] `doro-erp-dev-management` 인라인 정책 2개 import
- [x] `team2-doroload-ssm-access-policy` import (Group 범위는 축소)
- [x] `doro-erp-service-ecr-publisher` import + `doro-erp-dev-github-ecr-push`와 통합 방향 확정 (PR #16)
- [ ] PR #15, #16 리뷰 및 apply
- [ ] `cld-team2-doro-github-action`의 미사용 Access Key 2개 비활성화/삭제
- [ ] `doro-erp-service-ecr-publisher`의 trust policy(mutable/immutable subject 혼용) 정리 — 안정화 후 별도 진행
