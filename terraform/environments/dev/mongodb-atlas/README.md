# Dev Alpha MongoDB Atlas Free Terraform

발표와 개발 통합 테스트에 사용할 Audit Service 전용 MongoDB Atlas 8.0 M0 Free Cluster를 만든다. PrivateLink와 Atlas Cloud Backup/PIT는 사용하지 않으며, Database Network Access에는 기존 `team2` NAT Gateway의 고정 공인 IP `/32`만 허용한다.

```text
Audit Pod 또는 SSM 관리 EC2
→ 기존 doro-erp-dev-nat-a NAT Gateway
→ TLS
→ MongoDB Atlas M0 Public Endpoint
```

M0는 Atlas 사용료가 없지만 기존 EKS·NAT Gateway와 NAT Data Processing 같은 AWS 비용은 별도다.

## 1. Atlas 준비

Atlas Console에서 Organization을 만든 뒤 Organization ID를 확인한다. Terraform용 Atlas Programmatic API Key에는 해당 Organization의 Project 생성·관리 권한이 필요하다.

CloudShell의 현재 공인 IP를 API Key Access List에 `/32`로 등록한다. 이 목록은 Terraform이 Atlas API를 호출하기 위한 것이며, 뒤에서 Terraform이 만드는 Database Network Access의 NAT IP와는 다른 설정이다.

```bash
curl -fsS https://checkip.amazonaws.com
```

Atlas Key는 환경 변수로만 설정하고 `terraform.tfvars`에 넣지 않는다.

```bash
export MONGODB_ATLAS_PUBLIC_KEY='Atlas Public Key'
export MONGODB_ATLAS_PRIVATE_KEY='Atlas Private Key'
```

## 2. CloudShell 용량과 작업 디렉터리

CloudShell Home의 용량 부족을 피하도록 Provider와 Terraform 작업 데이터는 `/tmp`에 둔다. S3 Remote State는 영향을 받지 않지만 CloudShell을 다시 열면 환경 변수 설정과 `terraform init`을 다시 해야 한다.

```bash
mkdir -p /tmp/doro-terraform-plugin-cache
mkdir -p /tmp/doro-atlas-terraform-data
export TF_PLUGIN_CACHE_DIR=/tmp/doro-terraform-plugin-cache
export TF_DATA_DIR=/tmp/doro-atlas-terraform-data
```

## 3. 실행

Foundation Stack이 먼저 적용되어 `doro-erp-dev-nat-a` NAT Gateway가 `available` 상태여야 한다.

```bash
cd ~/Doro-ERP-Infra/terraform/environments/dev/mongodb-atlas
cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars
terraform init -reconfigure -backend-config=backend.hcl
terraform fmt -check -recursive
terraform validate
terraform plan -out=/tmp/mongodb-atlas-free.tfplan
terraform show -no-color /tmp/mongodb-atlas-free.tfplan
terraform apply /tmp/mongodb-atlas-free.tfplan
```

이전에 M10 Apply가 `NO_PAYMENT_INFORMATION_FOUND`로 실패했다면 기존 실패 Plan을 재사용하지 않는다. 새 Plan은 이미 State에 기록된 Atlas Project 같은 자원을 유지하고, M0 Cluster와 NAT IP Access List만 생성한다. 실패 과정에서 만들어진 PrivateLink용 AWS Security Group이 State에 있다면 새 구성에서 삭제될 수 있다.

Plan에는 다음 조건이 만족되어야 한다.

- `mongodbatlas_advanced_cluster.this`의 Tier가 `M0`
- `mongodbatlas_project_ip_access_list.eks_nat`가 NAT 공인 IP `/32`를 사용
- Atlas PrivateLink와 AWS Interface VPC Endpoint 생성 없음
- 기존 EKS·NAT·RDS 삭제 없음

## 4. Audit Database User와 Secret

Atlas Database User의 비밀번호를 Terraform으로 관리하면 평문이 Terraform State에 저장되므로 이 Stack은 Database User를 만들지 않는다.

Atlas Console의 `Database Access → Add New Database User`에서 Audit 전용 Password User를 만든다.

- Database user name: `doro_audit_runtime`
- Authentication: Password
- Database privilege: `readWrite` on `audit`
- Atlas Admin 권한은 부여하지 않음

그 다음 `Database → Connect → Drivers`에서 Public SRV 연결 문자열을 복사하고, 비밀번호를 URL Encoding하여 다음 형태로 만든다.

```text
mongodb+srv://doro_audit_runtime:<URL_ENCODED_PASSWORD>@<ATLAS_PUBLIC_HOST>/audit?retryWrites=true&w=majority
```

이 전체 값을 AWS Secrets Manager의 `doro-erp/dev/alpha/audit` Secret에서 `AUDIT_MONGODB_URI` 값으로 저장한다. URI는 Terraform Variable, Output, Git과 Shell History에 남기지 않는다.

Audit Application이 시작되면 `audit_records`, `admin_locks` Collection과 Unique·조회·TTL Index를 생성한다. 발표 전에 Application 기동과 Index 생성을 실제로 검증한다.

## 5. 확인

```bash
terraform output
aws ec2 describe-nat-gateways \
  --filter Name=tag:Name,Values=doro-erp-dev-nat-a Name=state,Values=available \
  --region ap-northeast-2 \
  --query 'NatGateways[0].[NatGatewayId,State,NatGatewayAddresses[0].PublicIp]' \
  --output table
```

`atlas_cluster_tier`는 `M0`, `atlas_database_access_cidr`는 NAT 공인 IP의 `/32`여야 한다. Atlas Console의 `Database & Network Access → IP Access List`에서도 같은 CIDR을 확인한다.

## 6. 삭제

Audit Pod를 먼저 중지하고 발표 데이터가 더 이상 필요하지 않은지 확인한다.

```bash
terraform plan -destroy -out=/tmp/mongodb-atlas-free-destroy.tfplan
terraform show -no-color /tmp/mongodb-atlas-free-destroy.tfplan
terraform apply /tmp/mongodb-atlas-free-destroy.tfplan
```

Atlas Database User는 Project가 삭제될 때 함께 사라진다. AWS Secrets Manager의 `AUDIT_MONGODB_URI` 값은 이 State가 소유하지 않으므로 별도로 정리한다.
