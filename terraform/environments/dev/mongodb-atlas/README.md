# Dev Alpha MongoDB Atlas Terraform

Audit Service 전용 MongoDB Atlas 8.0 Dedicated Cluster와 AWS PrivateLink를 만든다. Atlas Cluster는 AWS 서울 Region의 M10 3-Node Replica Set이며 AWS Interface Endpoint는 기존 `team2` VPC의 Data Subnet 두 개에 생성한다.

Atlas M10과 PrivateLink는 유료 자원이다. Apply 전 Atlas 요금과 Plan을 확인한다.

## 1. Atlas 준비

Atlas Console에서 Organization을 만든 뒤 Organization ID를 확인한다. Terraform용 Atlas Programmatic API Key에는 해당 Organization의 `Organization Project Creator`와 생성될 Project를 관리할 수 있는 권한이 필요하며, Private Endpoint 연결에는 Project Owner 수준 권한이 필요하다.

CloudShell에서 Key를 환경 변수로만 설정한다. `terraform.tfvars`에 넣지 않는다.

```bash
export MONGODB_ATLAS_PUBLIC_KEY='Atlas Public Key'
export MONGODB_ATLAS_PRIVATE_KEY='Atlas Private Key'
```

## 2. 실행

Foundation Stack이 먼저 적용되어 `doro-erp-dev` EKS와 `doro-erp-dev-management` Security Group이 존재해야 한다.

```bash
cd ~/Doro-ERP-Infra/terraform/environments/dev/mongodb-atlas
mkdir -p ~/.terraform.d/plugin-cache
export TF_PLUGIN_CACHE_DIR="$HOME/.terraform.d/plugin-cache"
cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars
terraform init -backend-config=backend.hcl
terraform fmt -check -recursive
terraform validate
terraform plan -out=mongodb-atlas.tfplan
terraform show -no-color mongodb-atlas.tfplan
terraform apply mongodb-atlas.tfplan
```

Provider Cache는 Foundation·Redis·Atlas Stack이 큰 AWS Provider Binary를 각각 중복 저장해 CloudShell 용량이 부족해지는 것을 막는다. CloudShell을 다시 열면 `TF_PLUGIN_CACHE_DIR`과 Atlas Key 환경 변수를 다시 설정한다.

Atlas Cluster와 PrivateLink 연결에는 시간이 걸릴 수 있다. Apply를 중간에 강제 종료하거나 State Lock을 강제로 해제하지 않는다.

## 3. Audit Database User와 Secret

Atlas Database User의 비밀번호를 Terraform으로 관리하면 평문이 Terraform State에 저장되므로 이 Stack은 Database User를 만들지 않는다.

Atlas Console의 `Database Access → Add New Database User`에서 Audit 전용 Password User를 만든다.

- Database user name: `doro_audit_runtime`
- Authentication: Password
- Database privilege: `readWrite` on `audit`
- Atlas Admin 권한은 부여하지 않음

그 다음 `Database → Connect → Private Endpoint → Drivers`에서 PrivateLink SRV 연결 문자열을 복사하고, 비밀번호를 URL Encoding하여 다음 형태로 만든다.

```text
mongodb+srv://doro_audit_runtime:<URL_ENCODED_PASSWORD>@<PRIVATE_ENDPOINT_HOST>/audit?retryWrites=true&w=majority
```

이 전체 값을 AWS Secrets Manager의 `doro-erp/dev/alpha/audit` Secret에서 `AUDIT_MONGODB_URI` 값으로 저장한다. URI는 Terraform Output, Git, Shell History에 남기지 않는다.

Audit Application이 시작되면 `audit_records`, `admin_locks` Collection과 Unique·조회·TTL Index를 생성한다. Database User에는 이 Index 생성에 필요한 권한이 있어야 한다.

## 4. 확인

```bash
terraform output
aws ec2 describe-vpc-endpoints \
  --vpc-endpoint-ids "$(terraform output -raw aws_vpc_endpoint_id)" \
  --region ap-northeast-2 \
  --query 'VpcEndpoints[0].[State,VpcId,SubnetIds,PrivateDnsEnabled]' \
  --output table
```

`atlas_private_link_status`는 최종적으로 `AVAILABLE`이어야 한다. DNS와 연결은 EKS Audit Pod 또는 SSM 관리 EC2에서 검증한다. PrivateLink는 동적 Member Port를 사용하므로 Endpoint Security Group은 공식 Atlas 요구 범위인 TCP `1024-65535`를 EKS와 관리 EC2 Security Group에만 허용한다.

## 5. 삭제

기본값은 Atlas Termination Protection이 켜져 있다. Audit Pod를 먼저 중지하고 필요한 Backup을 확인한 뒤 보호를 끄는 Apply를 한 번 실행한다.

```bash
sed -i 's/atlas_termination_protection_enabled = true/atlas_termination_protection_enabled = false/' terraform.tfvars
terraform plan -out=disable-protection.tfplan
terraform apply disable-protection.tfplan
terraform plan -destroy -out=mongodb-atlas-destroy.tfplan
terraform show -no-color mongodb-atlas-destroy.tfplan
terraform apply mongodb-atlas-destroy.tfplan
```

Atlas Database User와 AWS Secrets Manager의 URI 값은 이 State가 소유하지 않으므로 자동 삭제되지 않는다. Project가 삭제되면 그 안의 Database User도 함께 사라지지만, Secrets Manager 값은 별도로 정리해야 한다.
