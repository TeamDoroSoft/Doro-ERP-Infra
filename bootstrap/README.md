# Terraform Bootstrap

이 Stack은 Doro ERP Dev Terraform State Bucket과 실행 IAM Role을 만든다. AWS Account에 이미 있는 GitHub Actions OIDC Provider는 조회해 재사용한다. ECR Push Role의 단일 Terraform 소유자이며, Dev Stack은 이 Role을 조회만 한다. ECR Push Role의 신뢰 관계는 GitHub Organization ID `305760709`, Service Repository ID `1314731823`과 `dev` Environment를 포함한 immutable Subject로 제한한다.

## 최초 Bootstrap

최초 실행에는 아직 S3 Backend가 없으므로 현재 `erp-dev` 개인 Profile과 로컬 State로 실행한다. `backend.s3.tf.example`은 이 단계에서 `.tf` 확장자로 바꾸지 않는다.

```powershell
$env:AWS_PROFILE = "erp-dev"
$env:AWS_REGION = "ap-northeast-2"

terraform init
terraform fmt -check -recursive
terraform validate
terraform plan -out bootstrap.tfplan
terraform apply bootstrap.tfplan
```

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

Apply가 끝나면 `Docs/dev-infra-설계.md`의 가이드에 따라 `erp-dev`가 `doro-erp-dev-terraform` Role을 Assume하도록 구성하고 Identity를 검증한다.

```powershell
aws sts get-caller-identity --profile erp-dev
```

Assumed Role ARN을 확인한 뒤 S3 Backend 블록을 활성화하고 로컬 State를 S3로 이전한다. `backend.tf`는 이전 완료 후 Git에 포함한다.

```powershell
Copy-Item backend.s3.tf.example backend.tf
terraform init -migrate-state -backend-config=backend.hcl
terraform plan
```

## 이후 변경

- 승인된 `terraform_operator_principal_arns`만 Terraform Role을 Assume한다.
- Terraform 실행 Role은 자기 IAM 정책과 Trust Policy를 변경할 수 없다. Bootstrap IAM 변경은 승인된 개인 Source Principal로만 Plan·Apply한다.
- Foundation 이후 Stack은 개인 Source Credential이 아니라 승인된 Terraform Role로 실행한다.
- Bootstrap Role은 State와 `doro-erp-dev-*` IAM 범위만 가진다. VPC·EKS 등 AWS 서비스 권한은 Foundation 구현과 함께 필요한 Action만 별도 정책으로 추가한다.
- State Lock을 강제로 해제하기 전에 실행 중인 다른 작업이 없는지 확인한다.
- State Bucket은 `prevent_destroy`가 적용되어 일반 Destroy로 삭제되지 않는다.
- Access Key, Secret, Session Token과 `.tfstate`를 Git에 추가하지 않는다.
