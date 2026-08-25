# Terraform Bootstrap

이 Stack은 Doro ERP Prod Terraform State Bucket, Route 53 Public Hosted Zone, 실행 IAM Role,
ECR Push Role과 Prod SSM 운영자 IAM Group을 생성한다. IAM 사용자, 등록된 `minseok.click`
도메인과 계정 공용 GitHub Actions OIDC Provider는 선행조건이며, OIDC Provider는 Data Source로
조회만 하고 기존 태그·Thumbprint·Client ID를 변경하지 않는다.
SSM Group의 멤버십은 `ssm_operator_user_names`의 정확한 목록으로 관리한다. ECR Push Role의
신뢰 관계는 GitHub Organization ID `305760709`, Service Repository ID `1314731823`과
`prod` Environment를 포함한 Subject로 제한한다.

## 최초 Bootstrap

최초 실행에는 S3 Backend와 `doro-erp-prod-terraform` Role이 아직 없으므로 권한 있는 개인
Source Profile(`erp-prod-source`)과 Local State로 실행한다. Source IAM 사용자는 이 Stack의
S3·Route 53·IAM Group·Membership·Policy·Role 생성과 OIDC Provider 조회 권한이 있어야 한다. Terraform은
실행 주체에게 없는 권한을 스스로 부여할 수 없다. `backend.s3.tf.example`은 이 단계에서
`.tf` 확장자로 바꾸지 않는다.

```powershell
$env:AWS_PROFILE = "erp-prod-source"
$env:AWS_REGION = "ap-northeast-2"

terraform init
terraform fmt -check -recursive
terraform validate
terraform plan -out bootstrap.tfplan
terraform apply bootstrap.tfplan
```

Apply가 끝나면 기존 `minseok.click` 등록기관의 네임서버 설정을 다음 Output의 네 개 값으로
교체한다. 기존 DNS Record가 있다면 NS를 바꾸기 전에 새 Hosted Zone으로 먼저 옮긴다.

```powershell
terraform output route53_public_hosted_zone_name_servers
```

외부 DNS에서 새 네임서버 위임이 확인되기 전에는 ACM을 생성하는 Foundation Apply로 넘어가지 않는다.

AWS Console CloudShell에서는 별도 Profile을 지정하지 않는다.

```bash
export AWS_REGION=ap-northeast-2
export AWS_DEFAULT_REGION=ap-northeast-2
aws sts get-caller-identity
terraform init
terraform fmt -check -recursive
terraform validate
terraform plan -out=bootstrap.tfplan
terraform apply bootstrap.tfplan
```

Apply가 끝나면 `Docs/prod-infra-설계.md`의 가이드에 따라 `erp-prod`가 `doro-erp-prod-terraform` Role을 Assume하도록 구성하고 Identity를 검증한다.

```powershell
aws sts get-caller-identity --profile erp-prod
```

Assumed Role ARN을 확인한 뒤 S3 Backend 블록을 활성화하고 로컬 State를 S3로 이전한다. `backend.tf`는 이전 완료 후 Git에 포함한다.

```powershell
Copy-Item backend.s3.tf.example backend.tf
terraform init -migrate-state -backend-config=backend.hcl
terraform plan
```

## 이후 변경

- `doro-erp-prod-terraform-operators` Group과 AssumeRole 정책도 Bootstrap이 생성하며 기본 멤버는 `a-student-02`, `a-student-06`, `b-student-05`, `b-student-11`이다.
- 승인된 `terraform_operator_user_names`와 `terraform_operator_additional_principal_arns`만 Terraform Role을 Assume한다.
- `team2-doro-load-group`은 Terraform이 생성하며 기본 멤버는 `a-student-02`, `a-student-06`, `b-student-05`, `b-student-11`이다. 이 Group의 정책은 기존 감사 Shell 문서와, Foundation이 만드는 `doro-erp-prod-provider-admin-port-forwarding` Custom Session 문서만 사용하도록 제한한다. 후자는 `Name=doro-erp-prod-management` EC2만 Target으로 허용하며 원격 Host·443은 문서 본문에 고정된다.
- `aws_iam_group_membership`은 목록 전체를 배타적으로 관리하므로 Console에서 임의로 추가한 멤버는 다음 Apply에서 제거될 수 있다.
- IAM 사용자 생성과 Login Profile·Access Key 관리는 이 Stack 범위가 아니다.
- Terraform 실행 Role은 자기 IAM 정책과 Trust Policy를 변경할 수 없다. Bootstrap IAM 변경은 승인된 개인 Source Principal로만 Plan·Apply한다.
- Foundation 이후 Stack은 개인 Source Credential이 아니라 승인된 Terraform Role로 실행한다.
- Terraform Role은 후속 AWS 자원과 프로젝트 IAM 범위를 관리하며, EKS Node Group·ElastiCache·Auto Scaling·CloudFront VPC Origin 등에 필요한 Service-linked Role의 자동 생성도 허용한다.
- State Lock을 강제로 해제하기 전에 실행 중인 다른 작업이 없는지 확인한다.
- State Bucket은 `prevent_destroy`가 적용되어 일반 Destroy로 삭제되지 않는다.
- Access Key, Secret, Session Token과 `.tfstate`를 Git에 추가하지 않는다.

기존 환경을 완전히 삭제할 때는 기존 Bootstrap State를 먼저 Local Backend로 이전하고 모든
하위 Stack을 Destroy한 뒤, 승인된 절차로 기존 State Bucket의 Version과 Object를 비우고
`prevent_destroy`를 해제해 마지막에 삭제한다. Remote State가 남아 있는 동안 Bucket부터
삭제하지 않는다.
