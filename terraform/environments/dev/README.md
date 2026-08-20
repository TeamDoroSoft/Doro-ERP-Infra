# Dev Alpha Terraform

기존 `team2-DoroLoad` VPC와 2-AZ Subnet을 재사용해 Doro ERP Dev Alpha 기반을 만든다. 기존 VPC·Subnet·Internet Gateway·Route Table·SSM Endpoint는 삭제하거나 State로 가져오지 않는다. 삭제된 NAT를 가리키는 Private Application 기본 Route만 Import한 뒤 새 NAT Gateway로 복구한다.

## 생성 범위

- NAT Gateway와 Private Application 기본 Route 복구
- S3 Gateway Endpoint, ECR·Logs·Secrets Manager·SQS·STS Interface Endpoint
- EKS 1.35, 단일 `t4g.large` Managed Node Group, EKS Access Entry
- EKS Worker Node SSM과 Private `t4g.micro` 관리 EC2
- 6개 ECR Repository
- RDS PostgreSQL 17.10, SQS FIFO Main/DLQ, 서비스별·방향별·DB Migration용 Secrets Manager Container
- AWS Secrets Store CSI Provider Add-on, Secret Rotation과 Pod Identity
- Service GitHub Actions가 OIDC로 Assume하는 ECR Image Push 전용 Role
- AWS Load Balancer Controller IAM Policy·Role과 Pod Identity Association
- 비공개 Frontend S3, CloudFront, WAF, Viewer용 us-east-1 ACM, ALB용 Regional ACM, `doro.minseok.click`

Redis와 MongoDB는 Foundation과 State 수명주기를 분리한다. Foundation Apply 후 각각 [`redis/`](redis/README.md)와 [`mongodb-atlas/`](mongodb-atlas/README.md)에서 실행한다.

ALB는 이 Stack에서 직접 만들지 않는다. Terraform은 Controller의 AWS 권한만 만들고,
Helm으로 Controller를 설치한 뒤 Dev Alpha Ingress를 Kubernetes에 적용할 때 ALB가 생성된다.
`/api/*` CloudFront VPC Origin은 `origin.doro.minseok.click`을 통해 내부 ALB의 HTTPS 443
Listener에 연결한다. TLS는 ALB에서 종료되고 Edge Pod Target 구간은 HTTP다. Terraform
Plan 전에 Controller와 Ingress를 적용해 `doro-erp-dev-alpha` ALB가 존재해야 한다.

## 1. CloudShell 준비

AWS Console에서 Region을 서울로 선택하고 CloudShell을 연다.

```bash
export AWS_REGION=ap-northeast-2
export AWS_DEFAULT_REGION=ap-northeast-2
aws sts get-caller-identity
```

Account가 `727646470302`인지 확인한다.

```bash
terraform version
```

Terraform이 없으면 다음과 같이 설치한다.

```bash
sudo yum install -y yum-utils
sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
sudo yum install -y terraform
terraform version
```

## 2. Bootstrap

Repository를 받은 뒤 최초 한 번 실행한다.

```bash
cd ~/Doro-ERP-Infra/bootstrap
terraform init
terraform fmt -check -recursive
terraform validate
terraform plan -out=bootstrap.tfplan
terraform show -no-color bootstrap.tfplan
terraform apply bootstrap.tfplan
```

State Bucket과 Terraform Role이 생기면 Bootstrap State를 S3로 이전한다.

```bash
cp backend.s3.tf.example backend.tf
terraform init -migrate-state -backend-config=backend.hcl
terraform plan
```

## 3. Terraform 실행 Role 사용

CloudShell 로그인 사용자가 `a-student-06`일 때:

```bash
aws sts assume-role \
  --role-arn arn:aws:iam::727646470302:role/doro-erp-dev-terraform \
  --role-session-name doro-erp-dev-a-student-06 \
  --output json
```

출력 Credential을 CloudShell의 환경 변수로 설정한다. 화면 공유나 Git·메모에 값을 남기지 않는다.

```bash
export AWS_ACCESS_KEY_ID='발급된 AccessKeyId'
export AWS_SECRET_ACCESS_KEY='발급된 SecretAccessKey'
export AWS_SESSION_TOKEN='발급된 SessionToken'
aws sts get-caller-identity
```

ARN이 `assumed-role/doro-erp-dev-terraform/...` 형태인지 확인한다.

## 4. Dev 변수 준비

```bash
cd ~/Doro-ERP-Infra/terraform/environments/dev
cp terraform.tfvars.example terraform.tfvars
curl -fsS https://checkip.amazonaws.com
nano terraform.tfvars
```

`eks_public_access_cidrs`의 예제 IP를 출력된 IP의 `/32`로 바꾼다. `0.0.0.0/0`은 검증 단계에서 거절된다.

## 4.1 ALB HTTPS 최초 적용 순서

이 Stack은 Controller가 만든 `doro-erp-dev-alpha` ALB를 Data Source로 조회하므로 새 환경에서는
인증서와 Security Group, Ingress, CloudFront를 한 번에 만들 수 없다. 다음 순서를 지킨다.
기존 `http-only` Origin을 이 최종 구성으로 바로 전환하면 Security Group 80 제거부터
CloudFront HTTPS 배포 완료까지 API가 일시 중단되므로 Dev 점검 시간에 연속 실행한다.
무중단 전환이 필요하면 HTTP·HTTPS Listener와 80·443 규칙을 동시에 유지하는 별도 과도기
Overlay/Plan을 먼저 승인하고, CloudFront 전환 확인 뒤 제거해야 한다. 최종 Manifest에 HTTP
Listener를 남겨 무중단 단계를 대신하지 않는다.

1. Regional ACM 인증서와 ALB Security Group만 먼저 Target Plan으로 생성한다. Target Apply는
   최초 순환 의존성을 끊는 Bootstrap에만 사용하고 저장한 Plan을 검토한 뒤 적용한다.

```bash
terraform plan \
  -target=aws_acm_certificate_validation.alpha_alb \
  -target=aws_security_group.alpha_alb_frontend \
  -target=aws_vpc_security_group_ingress_rule.alpha_alb_from_cloudfront \
  -target=aws_vpc_security_group_egress_rule.alpha_alb_all \
  -out=alb-https-bootstrap.tfplan
terraform apply alb-https-bootstrap.tfplan
```

2. Controller와 `doro-alpha-alb` IngressClass를 준비한 뒤, 실제 Image Tag와 Migration 준비가
   끝난 정상 Application Release 절차로 Dev Alpha Overlay를 적용한다. Edge Ingress의
`tls.hosts`를 통해 Controller가 Regional ACM 인증서를 탐색하고 HTTPS 443 Listener를 만든다.
   Base Ingress 단독 적용은 Dev 인증서 Host와 Security Group이 없으므로 ALB Release 절차로
   사용하지 않는다.

   API Cache Behavior의 전용 Origin Request Policy는 Cookie·Query·CSRF 등 Viewer 값을
   보존하고 `Host`만 `origin.doro.minseok.click`로 바꿔 CloudFront의 Origin TLS 이름 검증과
   ALB 인증서가 일치하게 한다.

3. Listener가 `HTTPS:443`, 올바른 Certificate ARN, HTTP Target Group을 사용하는지 확인한다.

```bash
aws elbv2 describe-listeners \
  --load-balancer-arn "$(aws elbv2 describe-load-balancers \
    --names doro-erp-dev-alpha --query 'LoadBalancers[0].LoadBalancerArn' --output text)"
terraform output -raw alb_origin_certificate_arn
```

확인이 끝난 뒤 아래의 전체 `terraform plan`과 Apply를 실행한다. 이 마지막 단계에서
`origin.doro.minseok.click` ALB Alias와 CloudFront `https-only` VPC Origin이 연결된다.
기존 HTTP ALB를 전환할 때도 443 Listener 검증 전에는 CloudFront를 먼저 변경하지 않는다.

## 5. Init·Plan

```bash
terraform init -backend-config=backend.hcl
terraform fmt -check -recursive
terraform validate
terraform plan -out=dev.tfplan
terraform show -no-color dev.tfplan
```

Plan에서 기존 VPC·Subnet·Load Balancer 삭제가 없어야 한다. 기존 Private Application 기본 Route 한 개가 Import된 뒤 NAT Target만 바뀌는지 확인한다.

## 6. Apply

검토가 끝난 저장 Plan만 적용한다.

```bash
terraform apply dev.tfplan
terraform output
```

CloudFront와 EKS·RDS 생성 때문에 시간이 걸릴 수 있다. 실행 중인 Apply가 있으면 State Lock을 강제로 해제하지 않는다.

## 7. EKS와 SSM 확인

```bash
aws eks update-kubeconfig --region ap-northeast-2 --name doro-erp-dev
kubectl get nodes -o wide
aws ssm describe-instance-information --region ap-northeast-2 --output table
```

관리 EC2 접속:

```bash
terraform output -raw management_session_command
aws ssm start-session \
  --target "$(terraform output -raw management_instance_id)" \
  --region ap-northeast-2
```

EKS Worker Node는 EC2 Console의 `Connect → Session Manager`에서 장애 진단용으로 접속한다. 정상 Kubernetes 관리는 `kubectl`을 사용한다.

## 8. PostgreSQL 4 DB Bootstrap

RDS Master Secret은 RDS가 Secrets Manager에서 관리한다. Secret 값을 Terraform State나 Shell History에 넣지 않는다. AWS Console의 Secrets Manager에서 `postgres_master_secret_arn`에 해당하는 Secret을 열어 임시로 확인하고, SSM 관리 EC2에서 `psql`을 실행한다.

`sql/bootstrap-postgres.sql`을 SSM Session에 안전하게 전달한 뒤 다음 형태로 실행한다.

```bash
psql \
  "host=RDS_ENDPOINT port=5432 dbname=postgres user=doro_admin sslmode=require" \
  --file bootstrap-postgres.sql
```

Script가 각 서비스 Runtime·Migration 비밀번호를 대화형으로 묻는다. Runtime Credential은
서비스별 Secret에, Migration Credential은 `doro-erp/dev/alpha/migration/{service}` 전용
Secret에 각각 입력한다. Runtime Pod Identity는 Migration Secret을 읽을 수 없다.

## 9. Application·Migration Secret 입력과 CSI 연결

Terraform Apply 뒤 AWS Console의 Secrets Manager에서 서비스별 Secret과 방향별 HMAC Secret 값을 JSON으로 입력한다. 정확한 Runtime Key 목록은 `deploy/components/secrets-manager/README.md`, Migration 입력과 실행 순서는 `deploy/migrations/README.md`를 따른다.

```bash
aws eks update-kubeconfig --region ap-northeast-2 --name doro-erp-dev
kubectl get pods -n aws-secrets-manager
kubectl get csidriver secrets-store.csi.k8s.io
kubectl get secretproviderclass -n doro-alpha
```

Secret 값은 Terraform Variable, Plan, Output과 Kubernetes Manifest에 넣지 않는다. `AWS_ACCESS_KEY_ID`와 `AWS_SECRET_ACCESS_KEY`는 Application Secret에 저장하지 않고 Pod Identity를 사용한다.

## 10. Service Image 게시 Workflow 연결

ECR Push Role은 Bootstrap Stack이 단독으로 생성하고 Trust Policy와 권한을 관리한다. Dev Stack은
같은 Role을 Data Source로 조회하며 새 IAM Role이나 Inline Policy를 생성하지 않는다. Bootstrap Apply 뒤
Bootstrap Stack의 `github_ecr_push_role_arn` Output을 확인한다.

```bash
cd ../../../bootstrap
terraform output -raw github_ecr_push_role_arn
```

GitHub `TeamDoroSoft/Doro-ERP-Service` 저장소에서 `dev` Environment를 만들고, 위 ARN을
`AWS_ECR_PUSH_ROLE_ARN` Environment Variable로 등록한다. 이는 Role 식별자이며 Secret이 아니다.
Workflow는 `environment: dev`인 Job에서만 OIDC Role을 Assume할 수 있고, Role은 이 Terraform이
관리하는 여섯 ECR Repository의 조회·Layer Upload·Image Push 권한만 가진다.
Trust Policy의 Subject는 이름 재사용에도 다른 저장소가 권한을 얻지 못하도록 GitHub Organization ID
`305760709`와 Repository ID `1314731823`을 포함한 다음 immutable 값으로 고정한다.

```text
repo:TeamDoroSoft@305760709/Doro-ERP-Service@1314731823:environment:dev
```

`dev` Environment의 Deployment Branch Rule도 `main`으로 제한한다. Workflow 역시 다른 Branch에서는
Publish Job을 실행하지 않는다.

장기 Access Key를 GitHub Secret에 등록하지 않는다. GitHub Organization 또는 AWS Account가 소유한
`token.actions.githubusercontent.com` OIDC Provider가 먼저 존재해야 하며, 이 Stack은 기존 Provider를
Data Source로 조회해 재사용한다.

## 11. Frontend 확인

Vue Build 결과를 S3에 올린 뒤 CloudFront Cache를 무효화한다.

```bash
aws s3 sync FRONTEND_DIST_DIR "s3://$(terraform output -raw frontend_bucket_name)" --delete
aws cloudfront list-distributions \
  --query "DistributionList.Items[?Aliases.Items[?@=='doro.minseok.click']].[Id,Status,DomainName]" \
  --output table
```

현재 단계에서는 `/` 정적 SPA만 연결된다. `/api/*`는 AWS Load Balancer Controller와 내부 ALB 생성 후 별도 Plan으로 연결한다.
