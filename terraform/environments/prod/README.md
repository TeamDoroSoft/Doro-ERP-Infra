# Prod Alpha Terraform

별도 [Network Terraform](network/README.md)이 만든 VPC와 2-AZ Subnet을 사용해 Doro ERP Prod Alpha 기반을 만든다. VPC·Subnet·Internet Gateway·NAT·Route Table·VPC Endpoint는 Network State가 소유하며 이 Foundation State에는 포함하지 않는다.

## 생성 범위

- EKS 1.35, AZ-a의 `t3.large` Managed Node 최소 2개·최대 4개, EKS Access Entry
- EKS Worker Node SSM과 Public IP·Inbound Rule이 없는 Private `t4g.micro` 관리 EC2
- CloudWatch에 기록되는 관리 SSM Shell, 20분 Idle Timeout과 60분 최대 Session
- 6개 ECR Repository
- RDS PostgreSQL 17.10, SQS FIFO Main/DLQ, 서비스별·방향별·DB Migration용 Secrets Manager Container
- AWS Secrets Store CSI Provider Add-on, Secret Rotation과 Pod Identity
- Kubernetes HPA용 Metrics Server Community Add-on
- Managed Node Group 자동 증설용 Cluster Autoscaler IAM과 Pod Identity
- CloudWatch Observability Add-on, 14일 Container Log 보존과 Prod 운영 Alarm SNS Topic
- Service GitHub Actions가 OIDC로 Assume하는 ECR Image Push 전용 Role
- AWS Load Balancer Controller IAM Policy·Role과 Pod Identity Association
- 비공개 Frontend S3, CloudFront, WAF, Viewer용 us-east-1 ACM, ALB용 Regional ACM, `doro.minseok.click`

Network, Redis와 MongoDB는 Foundation과 State 수명주기를 분리한다. [`network/`](network/README.md)를 먼저 Apply한 뒤 Foundation, [`redis/`](redis/README.md), [`mongodb-atlas/`](mongodb-atlas/README.md) 순서로 실행한다.

ALB는 이 Stack에서 직접 만들지 않는다. Terraform은 Controller의 AWS 권한과 ALB Frontend
Security Group·Regional ACM 인증서를 만들고, AWS Load Balancer Controller가 Gateway API
Manifest를 조정해 `doro-erp-prod-alpha-gateway` Internal ALB를 생성한다. `/api/*` CloudFront
VPC Origin은 `origin.doro.minseok.click`을 통해 이 ALB의 HTTPS 443 Listener에 연결한다.
TLS는 ALB에서 종료되고 Edge Pod Target 구간은 HTTP다.

순환 의존성을 피하기 위해 `enable_gateway_backend=false`인 Foundation Apply와 Gateway ALB
생성 후 `enable_gateway_backend=true`인 Backend Origin Apply를 분리한다. 첫 단계에서는
Gateway ALB Data Source, VPC Origin, Origin Route 53 Alias와 ALB 전용 CloudWatch 경보를
만들지 않는다. 새 Prod 배포에서 Network와 Terraform Backend는 별도 State가 소유하고,
Frontend S3는 이 Foundation State가 새로 생성한다.
이 변수는 안전을 위해 기본값이 없으며 매 Plan에서 `terraform.tfvars`로 명시해야 한다.
기존 CloudFront Backend가 서비스 중인 환경에서 `false`를 적용하면 Backend Origin이 제거되므로
재구축 또는 승인된 제거 작업이 아니라면 적용하지 않는다.

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
  --role-arn arn:aws:iam::727646470302:role/doro-erp-prod-terraform \
  --role-session-name doro-erp-prod-a-student-06 \
  --output json
```

출력 Credential을 CloudShell의 환경 변수로 설정한다. 화면 공유나 Git·메모에 값을 남기지 않는다.

```bash
export AWS_ACCESS_KEY_ID='발급된 AccessKeyId'
export AWS_SECRET_ACCESS_KEY='발급된 SecretAccessKey'
export AWS_SESSION_TOKEN='발급된 SessionToken'
aws sts get-caller-identity
```

ARN이 `assumed-role/doro-erp-prod-terraform/...` 형태인지 확인한다.

## 3.1 Network Apply

Foundation보다 먼저 Terraform 관리형 VPC를 적용한다.

```bash
cd ~/Doro-ERP-Infra/terraform/environments/prod/network
cp terraform.tfvars.example terraform.tfvars
terraform init -reconfigure -backend-config=backend.hcl
terraform validate
terraform plan -out=/tmp/doro-prod-network.tfplan
terraform show -no-color /tmp/doro-prod-network.tfplan
terraform apply /tmp/doro-prod-network.tfplan
```

Internet Gateway와 NAT Gateway가 각각 한 개이고 S3 삭제가 없는지 확인한다. 자세한 검증과
기존 VPC 전환 절차는 [Network README](network/README.md)를 따른다.

## 4. Prod 변수 준비

```bash
cd ~/Doro-ERP-Infra/terraform/environments/prod
cp terraform.tfvars.example terraform.tfvars
curl -fsS https://checkip.amazonaws.com
nano terraform.tfvars
```

`eks_public_access_cidrs`의 예제 IP를 출력된 IP의 `/32`로 바꾼다. `0.0.0.0/0`은 검증 단계에서 거절된다.

## 4.1 Gateway API와 Backend Origin 적용 순서

### 1단계: Foundation Apply

`terraform.tfvars`에서 다음 값을 유지한다.

```hcl
enable_gateway_backend = false
```

아래의 일반 Plan·Apply로 EKS, Controller IAM, ALB Security Group과 Regional ACM 인증서를
먼저 준비한다. Gateway ALB가 없어도 Plan이 가능하다. Network 자원과 S3 삭제가 Plan에 있으면
적용하지 않는다.

이 단계의 CloudFront에는 Backend Origin과 `/api/*` Behavior가 없으므로 API는 배포 준비
상태가 아니다. Application Smoke Test와 사용자 Traffic은 3단계 적용 후 시작한다.

### 2단계: Gateway ALB 생성

[`Doro-ERP-GitOps/deploy/platform/aws-load-balancer-controller`](https://github.com/TeamDoroSoft/Doro-ERP-GitOps/blob/main/deploy/platform/aws-load-balancer-controller/README.md)의
절차로 Gateway API CRD, Controller, GatewayClass와 Prod Alpha Overlay를 적용한다. 새 ALB와
Edge Target이 준비될 때까지 CloudFront Backend를 활성화하지 않는다.

```bash
aws elbv2 describe-load-balancers \
  --names doro-erp-prod-alpha-gateway \
  --query 'LoadBalancers[0].{Arn:LoadBalancerArn,DNS:DNSName,Scheme:Scheme,State:State.Code}' \
  --output table
```

Listener가 `HTTPS:443`, 올바른 Regional Certificate, HTTP Target Group을 사용하는지 확인한다.

```bash
GATEWAY_ALB_ARN="$(aws elbv2 describe-load-balancers \
  --names doro-erp-prod-alpha-gateway \
  --query 'LoadBalancers[0].LoadBalancerArn' \
  --output text)"

aws elbv2 describe-listeners \
  --load-balancer-arn "${GATEWAY_ALB_ARN}" \
  --output table

terraform output -raw alb_origin_certificate_arn
```

### 3단계: Backend Origin Apply

Target이 모두 Healthy인 것을 확인한 뒤 `terraform.tfvars`를 변경한다.

```hcl
enable_gateway_backend = true
```

다시 전체 Plan을 저장하고 검토한다. 이 Plan에서 Gateway ALB Data Source를 조회하고
CloudFront VPC Origin, `origin.doro.minseok.click` Alias, `/api/*` Cache Behavior와 Gateway
ALB CloudWatch 경보를 추가한다. 무관한 EKS·EC2·RDS 교체나 VPC·S3 삭제가 있으면 적용하지 않는다.

API Cache Behavior의 Origin Request Policy는 Cookie·Query·CSRF 등 Viewer 값을 보존하고
`Host`만 `origin.doro.minseok.click`로 바꿔 CloudFront Origin TLS 이름과 ALB 인증서를
일치시킨다.

## 5. Init·Plan

```bash
terraform init -backend-config=backend.hcl
terraform fmt -check -recursive
terraform validate
terraform plan -out=prod.tfplan
terraform show -no-color prod.tfplan
```

Plan에서 Network State가 소유하는 VPC·Subnet·IGW·NAT·VPC Endpoint의 생성·변경·삭제가 없어야 한다. Foundation Plan에 Frontend S3 삭제가 있으면 적용하지 않는다.

## 6. Apply

검토가 끝난 저장 Plan만 적용한다.

```bash
terraform apply prod.tfplan
terraform output
```

CloudFront와 EKS·RDS 생성 때문에 시간이 걸릴 수 있다. 실행 중인 Apply가 있으면 State Lock을 강제로 해제하지 않는다.

## 7. EKS와 SSM 확인

```bash
aws eks update-kubeconfig --region ap-northeast-2 --name doro-erp-prod
kubectl get nodes -o wide
aws ssm describe-instance-information --region ap-northeast-2 --output table
```

관리 EC2 접속:

```bash
terraform output -raw management_session_command
aws ssm start-session \
  --target "$(terraform output -raw management_instance_id)" \
  --region ap-northeast-2 \
  --document-name doro-erp-prod-session
```

관리 Session은 `/doro-erp/prod/ssm-sessions` CloudWatch Log Group에 Streaming되고, 20분 동안 입력이 없거나 총 60분이 지나면 종료된다. SSH Session과 Port Forwarding은 사용자 IAM Policy에서 허용하지 않는다. EKS Worker Node도 장애 진단 시 같은 `--document-name doro-erp-prod-session`을 지정해 CLI로 접속하며, 정상 Kubernetes 관리는 `kubectl`을 사용한다.

Session Log에는 명령과 출력이 남으므로 비밀번호·Token·완성된 Connection URI를 명령행에 직접 입력하거나 출력하지 않는다.

## 8. PostgreSQL 4 DB Bootstrap

RDS Master Secret은 RDS가 Secrets Manager에서 관리한다. Secret 값을 Terraform State나 Shell History에 넣지 않는다. AWS Console의 Secrets Manager에서 `postgres_master_secret_arn`에 해당하는 Secret을 열어 임시로 확인하고, SSM 관리 EC2에서 `psql`을 실행한다.

`sql/bootstrap-postgres.sql`을 SSM Session에 안전하게 전달한 뒤 다음 형태로 실행한다.

```bash
psql \
  "host=RDS_ENDPOINT port=5432 dbname=postgres user=doro_admin sslmode=require" \
  --file bootstrap-postgres.sql
```

Script가 각 서비스 Runtime·Migration 비밀번호를 대화형으로 묻는다. Runtime Credential은
서비스별 Secret에, Migration Credential은 `doro-erp/prod/alpha/migration/{service}` 전용
Secret에 각각 입력한다. Runtime Pod Identity는 Migration Secret을 읽을 수 없다.

## 9. Application·Migration Secret 입력과 CSI 연결

Terraform Apply 뒤 AWS Console의 Secrets Manager에서 서비스별 Secret과 방향별 HMAC Secret 값을 JSON으로 입력한다. 정확한 Runtime Key 목록과 Migration 실행 순서는 각각 `Doro-ERP-GitOps/deploy/components/secrets-manager/README.md`와 `Doro-ERP-GitOps/deploy/migrations/README.md`를 따른다. Terraform의 Pod Identity 연결은 GitOps Manifest의 ServiceAccount 이름과 Secret 경로 계약에 의존한다.

```bash
aws eks update-kubeconfig --region ap-northeast-2 --name doro-erp-prod
kubectl get pods -n aws-secrets-manager
kubectl get csidriver secrets-store.csi.k8s.io
kubectl get secretproviderclass -n doro-alpha
```

Secret 값은 Terraform Variable, Plan, Output과 Kubernetes Manifest에 넣지 않는다. `AWS_ACCESS_KEY_ID`와 `AWS_SECRET_ACCESS_KEY`는 Application Secret에 저장하지 않고 Pod Identity를 사용한다.

## 10. Service Image 게시 Workflow 연결

ECR Push Role은 Bootstrap Stack이 단독으로 생성하고 Trust Policy와 권한을 관리한다. Prod Stack은
같은 Role을 Data Source로 조회하며 새 IAM Role이나 Inline Policy를 생성하지 않는다. Bootstrap Apply 뒤
Bootstrap Stack의 `doro_erp_service_ecr_publisher_role_arn` Output을 확인한다.

```bash
cd ../../../bootstrap
terraform output -raw doro_erp_service_ecr_publisher_role_arn
```

GitHub `TeamDoroSoft/Doro-ERP-Service` 저장소에서 `prod` Environment를 만들고, 위 ARN을
`AWS_ECR_PUSH_ROLE_ARN` Environment Variable로 등록한다. 이는 Role 식별자이며 Secret이 아니다.
Workflow는 `environment: prod`인 Job에서만 OIDC Role을 Assume할 수 있고, Role은 이 Terraform이
관리하는 여섯 ECR Repository의 조회·Layer Upload·Image Push 권한만 가진다.
Trust Policy의 Subject는 이름 재사용에도 다른 저장소가 권한을 얻지 못하도록 GitHub Organization ID
`305760709`와 Repository ID `1314731823`을 포함한 다음 immutable 값으로 고정한다.

```text
repo:TeamDoroSoft@305760709/Doro-ERP-Service@1314731823:environment:prod
```

`prod` Environment의 Deployment Branch Rule도 `main`으로 제한한다. Workflow 역시 다른 Branch에서는
Publish Job을 실행하지 않는다.

장기 Access Key를 GitHub Secret에 등록하지 않는다. GitHub Organization 또는 AWS Account가 소유한
`token.actions.githubusercontent.com` OIDC Provider가 먼저 존재해야 하며, 이 Stack은 기존 Provider를
Data Source로 조회해 재사용한다.

## 10.1 중앙 Log와 최소 Alarm 확인

CloudWatch Observability Add-on은 전용 `cloudwatch-agent` Pod Identity로 Container Log와
Container Insights Metric을 전송한다. Application Signals 자동 계측은 아직 활성화하지 않아
Application Pod를 자동 재시작하거나 Trace 비용을 발생시키지 않는다. Container Log Group은
기본 14일 보존하며 `cloudwatch_log_retention_days`로 조정한다.

```bash
aws eks describe-addon \
  --cluster-name doro-erp-prod \
  --addon-name amazon-cloudwatch-observability \
  --query 'addon.{status:status,health:health.issues}'
kubectl get pods -n amazon-cloudwatch
aws logs describe-log-groups \
  --log-group-name-prefix /aws/containerinsights/doro-erp-prod \
  --query 'logGroups[].{name:logGroupName,retention:retentionInDays}' \
  --output table
```

최소 Alarm은 EKS Failed Node, 서비스별 Running Pod 2개 미만, FIFO DLQ Message, ALB 자체 5xx와
Edge Target 5xx를 SNS Topic으로 전달한다. `operations_alarm_email`을 설정했다면 Apply 뒤 수신함에서
SNS 구독을 반드시 확인한다. Runtime을 아직 배포하지 않은 신규 환경에서는 서비스별 Running Pod
Alarm이 먼저 발생하는 것이 정상이며, Image와 Migration을 준비한 뒤 모두 `OK`로 전환되는지 확인한다.

```bash
terraform output -raw operations_alarm_topic_arn
aws cloudwatch describe-alarms \
  --alarm-name-prefix doro-erp-prod-alpha \
  --query 'MetricAlarms[].{name:AlarmName,state:StateValue,reason:StateReason}' \
  --output table
aws logs tail /aws/containerinsights/doro-erp-prod/application --since 10m
```

Alarm 임계치는 Prod 실제 요청량과 복구 시간을 관찰한 뒤 조정한다. Tenant·Store·Actor ID를
CloudWatch Metric Dimension으로 추가하지 않고, Secret·Cookie·요청 Body를 Log에 남기지 않는다.

## 11. Frontend 확인

Vue Build 결과를 S3에 올린 뒤 CloudFront Cache를 무효화한다.

```bash
aws s3 sync FRONTEND_DIST_DIR "s3://$(terraform output -raw frontend_bucket_name)" --delete
aws cloudfront list-distributions \
  --query "DistributionList.Items[?Aliases.Items[?@=='doro.minseok.click']].[Id,Status,DomainName]" \
  --output table
```

Terraform에는 `/` 정적 SPA와 `/api/*` CloudFront Ordered Cache Behavior·VPC Origin이 코드화돼 있다. 다만 AWS Load Balancer Controller가 생성하는 내부 ALB와 HTTPS Listener를 포함한 실제 AWS Apply·Runtime 연결은 아직 검증되지 않았다.
