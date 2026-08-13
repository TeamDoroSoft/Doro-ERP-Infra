# AWS Dev Alpha 남은 작업 체크리스트

## 목적

`doro.minseok.click` Dev Alpha 환경을 실제로 사용할 수 있는 상태까지 구성하기 위한 남은 작업을 실행 순서대로 정리한다.

- AWS Account: `727646470302`
- Region: `ap-northeast-2`
- Terraform 환경: `terraform/environments/dev`
- 기존 네트워크: `team2` VPC·Subnet·Internet Gateway·Route Table·SSM Endpoint 재사용
- 기준 확인일: 2026-08-13

현재 Terraform과 Secrets Store CSI 연결 코드는 준비되어 있지만 AWS에는 아직 Apply하지 않았다. 따라서 아래 단계는 반드시 순서대로 진행한다.

## 1. Bootstrap Terraform 실행

### 현재 상태

- [ ] Terraform 실행 Role `doro-erp-dev-terraform` 생성
- [ ] Terraform State S3 Bucket 생성
- [ ] S3 native State Lock 활성화
- [ ] Bootstrap Local State를 S3 Backend로 이전

### CloudShell 실행

AWS Console에서 서울 Region을 선택하고 CloudShell을 연다.

```bash
export AWS_REGION=ap-northeast-2
export AWS_DEFAULT_REGION=ap-northeast-2

aws sts get-caller-identity
git clone https://github.com/TeamDoroSoft/Doro-ERP-Infra.git
cd ~/Doro-ERP-Infra/bootstrap

terraform init
terraform fmt -check -recursive
terraform validate
terraform plan -out=bootstrap.tfplan
terraform show -no-color bootstrap.tfplan
terraform apply bootstrap.tfplan
```

Bootstrap Apply 후 State Backend를 이전한다.

```bash
cp backend.s3.tf.example backend.tf
terraform init -migrate-state -backend-config=backend.hcl
terraform plan
```

### 완료 조건

```bash
aws iam get-role --role-name doro-erp-dev-terraform
aws s3api head-bucket \
  --bucket doro-erp-dev-tfstate-727646470302-ap-northeast-2
```

두 명령이 대상 리소스를 정상적으로 반환하고, `backend.hcl`의 `use_lockfile = true` 설정으로 초기화한 Bootstrap의 후속 `terraform plan`에 예상하지 않은 변경이 없어야 한다.

## 2. Dev 인프라 Terraform 실행

### 현재 상태

- [ ] NAT Gateway 생성 및 Private Application 기본 Route 복구
- [ ] 추가 VPC Endpoint 생성
- [ ] EKS Cluster·Managed Node Group 생성
- [ ] SSM 관리 EC2 생성
- [ ] RDS PostgreSQL 생성
- [ ] SQS Main Queue·DLQ 생성
- [ ] ECR Repository 6개 생성
- [ ] Secrets Manager Secret Container 생성
- [ ] Frontend S3·CloudFront·WAF·ACM·Route53 구성

### Terraform 실행 Role 전환

```bash
aws sts assume-role \
  --role-arn arn:aws:iam::727646470302:role/doro-erp-dev-terraform \
  --role-session-name doro-erp-dev-cloudshell \
  --output json
```

출력된 임시 Credential을 CloudShell 환경 변수로 설정하고 Role 전환을 확인한다. Credential은 Git, 문서 또는 Shell Script에 저장하지 않는다.

```bash
export AWS_ACCESS_KEY_ID='발급된 AccessKeyId'
export AWS_SECRET_ACCESS_KEY='발급된 SecretAccessKey'
export AWS_SESSION_TOKEN='발급된 SessionToken'
aws sts get-caller-identity
```

### Plan과 Apply

```bash
cd ~/Doro-ERP-Infra/terraform/environments/dev
cp terraform.tfvars.example terraform.tfvars
curl -fsS https://checkip.amazonaws.com
nano terraform.tfvars

terraform init -backend-config=backend.hcl
terraform fmt -check -recursive
terraform validate
terraform plan -out=dev.tfplan
terraform show -no-color dev.tfplan
terraform apply dev.tfplan
terraform output
```

`terraform.tfvars`의 `eks_public_access_cidrs`에는 CloudShell에서 확인한 공인 IP의 `/32`만 입력한다. Plan에서 기존 VPC·Subnet·Load Balancer를 삭제하거나 교체하지 않는지 확인한다.

### 완료 조건

```bash
aws eks describe-cluster --name doro-erp-dev --region ap-northeast-2
aws eks update-kubeconfig --name doro-erp-dev --region ap-northeast-2
kubectl get nodes -o wide
aws ssm describe-instance-information --region ap-northeast-2 --output table
terraform plan
```

EKS가 `ACTIVE`, Node가 `Ready`, 관리 EC2와 Worker Node가 SSM Online이어야 한다. 마지막 Plan에는 예상하지 않은 변경이 없어야 한다.

## 3. Secret 실제 값 입력과 PostgreSQL 초기화

### 원칙

- `.env.example`의 비밀 값만 Secrets Manager에서 관리한다.
- 일반 환경변수는 Kubernetes ConfigMap으로 관리한다.
- AWS Access Key는 애플리케이션 Secret에 넣지 않고 EKS Pod Identity를 사용한다.
- Secret 값은 Terraform Variable·State·Plan·Output·Kubernetes Manifest·Git에 저장하지 않는다.

### 남은 작업

- [ ] RDS Master Secret 확인
- [ ] PostgreSQL 서비스 DB 4개 생성
- [ ] 서비스별 Runtime·Migration Role 생성
- [ ] 서비스별 Secrets Manager Secret JSON 입력
- [ ] 방향별 HMAC Secret 입력
- [ ] SecretProviderClass와 CSI Mount 확인
- [ ] Secret Rotation 동작 확인

관리 EC2에 SSM으로 접속한 후 `terraform/environments/dev/sql/bootstrap-postgres.sql`을 실행한다.

```bash
aws ssm start-session \
  --target "$(terraform output -raw management_instance_id)" \
  --region ap-northeast-2
```

관리 EC2에서 다음 형태로 실행한다.

```bash
psql \
  "host=RDS_ENDPOINT port=5432 dbname=postgres user=doro_admin sslmode=require" \
  --file bootstrap-postgres.sql
```

Secret JSON Key와 Kustomize 연결 방식은 `deploy/components/secrets-manager/README.md`를 따른다.

### 완료 조건

```bash
kubectl get pods -n aws-secrets-manager
kubectl get csidriver secrets-store.csi.k8s.io
kubectl get secretproviderclass -n doro-alpha
```

CSI 관련 Pod가 정상이고, 테스트 Pod에서 Secret이 파일과 Kubernetes Secret으로 동기화되며 애플리케이션 로그에 Secret 원문이 출력되지 않아야 한다.

## 4. EKS 애플리케이션 실행 기반 구현

Terraform Apply만으로 애플리케이션 API가 동작하지 않는다. 다음 Kubernetes 구성이 추가로 필요하다.

- [ ] `doro-alpha` Namespace와 서비스별 ServiceAccount
- [ ] 6개 애플리케이션 Deployment·Service
- [ ] 비밀이 아닌 환경변수 ConfigMap
- [ ] Readiness·Liveness Probe와 Resource Request·Limit
- [ ] EBS CSI Driver와 StorageClass
- [ ] Redis·MongoDB Stateful Workload와 PVC
- [ ] AWS Load Balancer Controller와 Pod Identity
- [ ] 서비스별 Ingress와 공유 Internal ALB
- [ ] CloudFront `/api/*` VPC Origin과 Internal ALB 연결
- [ ] NetworkPolicy·PDB·ResourceQuota
- [ ] CloudWatch Log·Alarm·Dashboard
- [ ] Redis·MongoDB Backup과 복구 절차

### 완료 조건

```bash
kubectl get deploy,sts,pod,svc,ingress -n doro-alpha
kubectl get pvc -n doro-alpha
kubectl get targetgroupbinding -n doro-alpha
```

모든 필수 Pod가 Ready이고 PVC가 Bound이며 ALB Target이 Healthy여야 한다. CloudFront에서 `/api/*` 요청이 Internal ALB로 전달되어야 한다.

## 5. 애플리케이션 배포와 통합 검증

### 남은 작업

- [ ] 서비스별 Docker Image Build
- [ ] ECR Repository에 Image Push
- [ ] Kubernetes Manifest에 고정 Image Tag 반영
- [ ] 애플리케이션 Deployment Rollout
- [ ] Frontend Build 결과를 S3에 업로드
- [ ] CloudFront Cache Invalidation
- [ ] `doro.minseok.click` HTTPS 접속 확인
- [ ] API·PostgreSQL·Redis·MongoDB 연결 확인
- [ ] SQS Event 발행·소비·재시도·DLQ 통합 테스트
- [ ] Secrets Manager Rotation 후 재기동 검증
- [ ] GitHub Actions Image Build·Push 자동화
- [ ] 배포 및 장애 대응 Runbook 작성

Frontend 배포 예시는 다음과 같다.

```bash
aws s3 sync FRONTEND_DIST_DIR \
  "s3://$(terraform output -raw frontend_bucket_name)" \
  --delete

aws cloudfront create-invalidation \
  --distribution-id CLOUDFRONT_DISTRIBUTION_ID \
  --paths '/*'
```

### 최종 완료 조건

- `https://doro.minseok.click`의 인증서와 DNS가 정상이다.
- Frontend 새로고침과 Client-side Routing이 정상이다.
- `/api/*` 요청이 CloudFront와 Internal ALB를 거쳐 정상 응답한다.
- 모든 애플리케이션이 필요한 DB·Cache·Queue·Secret에 최소 권한으로 접근한다.
- 정상·실패·재시도·DLQ 시나리오의 결과를 로그와 Metric으로 확인할 수 있다.
- AWS Console과 Terraform의 상태가 일치하며 최종 `terraform plan`에 Drift가 없다.

## 권장 실행 순서 요약

1. Bootstrap Apply와 Remote State 이전
2. Dev Terraform Plan 검토와 Apply
3. PostgreSQL Bootstrap과 Secret 실제 값 등록
4. EKS 실행 기반과 ALB·Ingress·CloudFront API 경로 구성
5. Image·Frontend 배포와 End-to-End 검증

각 단계가 완료되기 전에는 다음 단계의 운영 완료로 판단하지 않는다. 특히 Terraform Apply 성공과 애플리케이션 가용 상태를 구분해서 확인한다.
