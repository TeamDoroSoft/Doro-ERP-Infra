# Prod Alpha Terraform

별도 [Network Terraform](network/README.md)이 만든 VPC와 2-AZ Subnet을 사용해 Doro ERP Prod Alpha 기반을 만든다. VPC·Subnet·Internet Gateway·NAT·Route Table·VPC Endpoint는 Network State가 소유하며 이 Foundation State에는 포함하지 않는다.

## 생성 범위

- EKS 1.36, AZ-a의 `t3.large` Managed Node 최소 2개·최대 4개, EKS Access Entry
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
- 비공개 Frontend S3, CloudFront, WAF, Viewer용 us-east-1 ACM, ALB용 Regional ACM, POS `doro.minseok.click`과 Kiosk `kiosk.minseok.click`
- Bootstrap이 만든 Public Route 53 Hosted Zone `minseok.click`에 Terraform이 관리하는 DNS Record
- Provider Admin 전용 Pod Identity·OIDC/session 및 Edge-to-Store Access HMAC Secret Container, Internal ALB용 Security Group·Regional ACM과 고정 목적지 SSM Port Forwarding 문서

Network, Redis와 MongoDB는 Foundation과 State 수명주기를 분리한다. [`network/`](network/README.md)를 먼저 Apply한 뒤 Foundation, [`redis/`](redis/README.md), [`mongodb-atlas/`](mongodb-atlas/README.md) 순서로 실행한다.

ALB는 이 Stack에서 직접 만들지 않는다. Terraform은 Controller의 AWS 권한과 ALB Frontend
Security Group·Regional ACM 인증서를 만들고, AWS Load Balancer Controller가 Gateway API
Manifest를 조정해 `doro-erp-prod-alpha-gateway` Internal ALB를 생성한다. `/api/*` CloudFront
VPC Origin은 `origin.doro.minseok.click`을 통해 이 ALB의 HTTPS 443 Listener에 연결한다.
TLS는 ALB에서 종료되고 Edge Pod Target 구간은 HTTP다.

## Provider Admin private access contract

Provider Admin ALB·Ingress·IngressGroup·Namespace와 NetworkPolicy는 GitOps가 소유한다. 이
Foundation State는 ALB를 직접 만들거나 `admin.doro.minseok.click`의 Public Route 53 Alias를
만들지 않는다. GitOps는 전용 internal ALB에 아래 Output 계약을 적용해야 한다.

| Contract | Terraform ownership | GitOps requirement |
|---|---|---|
| Namespace and Edge identity | `doro-provider-admin`, ServiceAccount `provider-admin-edge-api`, dedicated Pod Identity role | Admin Edge Deployment only uses this ServiceAccount. Public Edge continues to use `doro-alpha/edge-api`. |
| Secret containers | `doro-erp/prod/alpha/provider-admin-edge` and `doro-erp/prod/alpha/hmac/edge-to-store-access-admin` | Admin OIDC/session values mount only into Admin Edge; Admin HMAC mounts only into Admin Edge and Store Access. Public Edge gets neither. |
| ALB network boundary | `provider_admin_alb_security_group_id` | Attach it only to the Admin internal ALB. Its only inbound rule is the management EC2 security group to TCP/443. |
| TLS and browser name | `provider_admin_alb_certificate_arn`, `provider_admin_alb_hostname` | Attach the Regional certificate to the HTTPS listener and route Host `admin.doro.minseok.click`; do not add it to the public Gateway/CloudFront origin or publish a public Alias. |

Keep `provider_admin_remote_host=null` for the first Foundation Apply so Terraform can create the
Admin ALB Security Group, Certificate and workload identity before the GitOps-owned ALB exists.
After that ALB is programmed, set the variable to its exact private ELBv2 DNS name (without scheme
or port) and apply the Foundation again. Only this second Apply creates the SSM document. Terraform
embeds that host, remote port `443`, and local port `8443` into
`doro-erp-prod-provider-admin-port-forwarding`; callers cannot change them. This prevents the SSM
document from becoming a general remote-host proxy and preserves the exact OIDC redirect contract.
Before starting the session, verify local port `8443` is unused. Map
`admin.doro.minseok.click` to `127.0.0.1` in the operator's local hosts resolver for the duration of
the tunnel so the browser sends the certificate Host/SNI while SSM forwards to the private ALB DNS.
The expected Admin origin is `https://admin.doro.minseok.click:8443` and the exact callback is
`https://admin.doro.minseok.click:8443/api/v1/provider/auth/callback`.

```bash
ss -ltn "sport = :8443"
aws ssm start-session \
  --target "$(terraform output -raw management_instance_id)" \
  --region ap-northeast-2 \
  --document-name "$(terraform output -raw provider_admin_port_forwarding_document_name)" \
  --parameters "localPortNumber=8443"
```

The SSM operator policy permits this custom document only with the `doro-erp-prod-management`
instance. Keep the normal session document separately for audited shell work. Verify after rollout
that a public CloudFront URL, shared Gateway ALB, and a public Edge Pod cannot serve
`/api/v1/provider/**`; then verify that the local tunnel reaches only the Admin ALB.

순환 의존성을 피하기 위해 `enable_gateway_backend=false`인 Foundation Apply와 Gateway ALB
생성 후 `enable_gateway_backend=true`인 Backend Origin Apply를 분리한다. 첫 단계에서는
Gateway ALB Data Source, VPC Origin, Origin Route 53 Alias와 ALB 전용 CloudWatch 경보를
만들지 않는다. 새 Prod 배포에서 Network와 Terraform Backend는 별도 State가 소유하고,
Frontend S3는 이 Foundation State가 새로 생성한다.
이 변수는 안전을 위해 기본값이 없으며 매 Plan에서 `terraform.tfvars`로 명시해야 한다.
기존 CloudFront Backend가 서비스 중인 환경에서 `false`를 적용하면 Backend Origin이 제거되므로
재구축 또는 승인된 제거 작업이 아니라면 적용하지 않는다.

Bootstrap Apply에서 `minseok.click` Public Hosted Zone을 먼저 생성하고, 등록기관 NS 위임과
외부 DNS 전파를 확인한 뒤 Foundation을 Apply한다. Foundation은 Bootstrap Remote State의 Zone ID를
사용해 ACM 검증과 Frontend·Origin Record를 만든다. Viewer 인증서는 POS와 Kiosk hostname을 모두
포함하고, 두 hostname은 같은 S3 Artifact·CloudFront Distribution·`/api/*` VPC Origin을 사용한다.
`kiosk_domain_name`의 기본값은 `kiosk.minseok.click`이며 변경할 때는 Hosted Zone 아래의 POS·Origin·
Provider Admin과 겹치지 않는 hostname을 사용한다. 도메인 등록 자체와 등록기관 설정은 AWS
Terraform 범위가 아니다.

```bash
terraform -chdir=../../../bootstrap output route53_public_hosted_zone_name_servers
```

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
curl -fsS https://checkip.amazonaws.com
```

신규 환경에서만 `cp terraform.tfvars.example terraform.tfvars`로 시작한다. 기존 환경에서는 예제
CIDR로 운영값을 덮어쓰지 말고, 먼저 현재 EKS Public Access CIDR을 확인한다.

```bash
aws eks describe-cluster \
  --name doro-erp-prod \
  --region ap-northeast-2 \
  --query 'cluster.resourcesVpcConfig.publicAccessCidrs' \
  --output json
nano terraform.tfvars
```

IAM처럼 EKS API 접근 변경이 목적이 아닌 Apply에서는 조회된 운영 CIDR을
`eks_public_access_cidrs`에 그대로 유지한다. 접근 경계를 변경하는 승인된 작업에서만 현재
CloudShell Public IP의 `/32`로 바꾼다. `0.0.0.0/0`은 검증 단계에서 거절된다.

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
일치시킨다. CloudFront는 Viewer의 Cookie Header를 값 변경 없이 전달한다. Backend의 인증 Cookie는
`Domain` 속성을 설정하지 않는 host-only Cookie여야 하며, 이 경우 `doro.minseok.click`과
`kiosk.minseok.click`은 같은 Distribution을 사용해도 브라우저 Cookie Jar가 분리된다. Backend가
`Domain=minseok.click` 또는 `Domain=.minseok.click`을 발급하면 이 격리가 깨지므로 적용 전후
`Set-Cookie` 응답을 반드시 확인한다.

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

장기 Access Key를 GitHub Secret에 등록하지 않는다. Bootstrap Stack은 AWS Account에 이미 있는
`token.actions.githubusercontent.com` 공용 OIDC Provider를 Data Source로 조회하고 ECR Publisher
Role의 Trust Policy에서만 참조한다. 기존 Provider의 태그·Thumbprint·Client ID는 변경하지 않는다.
GitHub Organization, Repository, Environment와 GitHub App은 AWS 밖의 선행조건이다.

## 10.1 Front 게시 Workflow 연결

Public Front와 Provider Admin은 `TeamDoroSoft/Doro-ERP-Front` 저장소의 `prod` Environment를
공유하지만 AWS Role은 분리한다. Public Role은 S3 Object 배포와 CloudFront 무효화만 수행하고,
Admin Role은 Provider Admin ECR Image 조회·Upload·Push만 수행한다.

```bash
terraform output -raw frontend_public_publisher_role_arn
terraform output -raw frontend_admin_ecr_publisher_role_arn
terraform output -raw frontend_bucket_name
terraform output -raw frontend_cloudfront_distribution_id
terraform output -raw frontend_ecr_repository_name
terraform output -raw frontend_url
terraform output -raw kiosk_frontend_url
```

Front 저장소의 `prod` Environment Variable은 다음 Output과 연결한다.

| GitHub Variable | Terraform Output | 권한 경계 |
|---|---|---|
| `AWS_FRONTEND_DEPLOY_ROLE_ARN` | `frontend_public_publisher_role_arn` | Public S3·CloudFront만 |
| `AWS_ADMIN_ECR_PUSH_ROLE_ARN` | `frontend_admin_ecr_publisher_role_arn` | Provider Admin ECR만 |
| `FRONTEND_S3_BUCKET` | `frontend_bucket_name` | Public Artifact Bucket 이름 |
| `FRONTEND_CLOUDFRONT_DISTRIBUTION_ID` | `frontend_cloudfront_distribution_id` | Public Distribution ID |
| `FRONTEND_ECR_REPOSITORY` | `frontend_ecr_repository_name` | ECR URL이 아닌 Repository 이름 |
| `PUBLIC_APP_ORIGIN` | `frontend_url` | POS 전용 HTTPS Origin |
| `KIOSK_APP_ORIGIN` | `kiosk_frontend_url` | Kiosk 전용 HTTPS Origin |

두 Role의 Trust Policy는 `repo:TeamDoroSoft/Doro-ERP-Front:environment:prod`만 허용한다. GitHub
`prod` Environment의 Deployment Branch Rule도 `main`으로 제한하고, Service ECR Publisher Role을
Front Workflow에 등록하지 않는다.

## 10.2 중앙 Log와 최소 Alarm 확인

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

현재 운영 방식은 이메일 구독을 사용하지 않으므로 `operations_alarm_email = null`을 유지한다. SNS Topic과
Alarm 연결은 향후 알림 채널을 추가할 수 있도록 유지하며, 지금은 CloudWatch Console에서 Alarm 상태를
직접 확인한다.

```bash
terraform output -raw operations_alarm_topic_arn
aws cloudwatch describe-alarms \
  --alarm-name-prefix doro-erp-prod-alpha \
  --query 'MetricAlarms[].{name:AlarmName,state:StateValue,reason:StateReason}' \
  --output table
aws logs tail /aws/containerinsights/doro-erp-prod/application --since 10m
```

Terraform이 만드는 `doro-erp-prod-alpha-operations` Dashboard에는 Failed Node, 여섯 Runtime과
Provider Admin Front·Edge의 Running Pod, Node CPU·Memory, Pod Restart·Pending·CrashLoopBackOff·
Image Pull Error, Pod CPU·Memory, PostgreSQL 상태, CloudFront 요청·오류율, DLQ Message, Alarm 상태,
ElastiCache Redis CPU·Memory·Connection·Eviction, 최근 Application Error와 Gateway ALB 5xx가
표시된다. 여덟 서비스 모두 Running Pod 2개 미만 경보를 사용한다. CloudWatch Console의 `대시보드`에서
열거나 다음 Output으로 이름을 확인한다.

```bash
terraform output -raw cloudwatch_operations_dashboard_name
```

Logs Insights의 `doro-erp-prod/alpha/application-errors` 저장 쿼리는 최근 Application Error를 조회한다.
`doro-erp-prod/alpha/request-trace-template`은 `REPLACE_WITH_REQUEST_ID`를 실제 `req-...` 값으로 바꿔
Edge와 하위 서비스 사이의 요청을 시간순으로 추적한다.

별도 Kubernetes Dashboard Workload는 설치하거나 외부에 공개하지 않는다. 배포 상태와 Git Drift는
Argo CD에서 확인하고, 현재 Kubernetes Resource는 AWS Console의 `EKS > doro-erp-prod > 리소스`에서
확인한다. 상세 로그와 Event는 CloudWatch 또는 `kubectl`을 사용한다.

Alarm 임계치는 Prod 실제 요청량과 복구 시간을 관찰한 뒤 조정한다. Tenant·Store·Actor ID를
CloudWatch Metric Dimension으로 추가하지 않고, Secret·Cookie·요청 Body를 Log에 남기지 않는다.

## 11. Frontend 확인

Vue Build 결과를 S3에 올린 뒤 CloudFront Cache를 무효화한다.

Kiosk hostname 추가는 다음 순서로 적용한다.

1. `terraform.tfvars`의 `kiosk_domain_name`이 승인된 `kiosk.minseok.click`인지 확인한다.
2. 저장한 Plan에서 Viewer ACM 인증서 교체, 인증 CNAME, CloudFront Alias 추가, Kiosk A·AAAA Alias
   추가만 의도한 변경인지 검토한다. 기존 `admin.doro.minseok.click` Regional 인증서와
   `origin.doro.minseok.click` Regional 인증서 변경이 있으면 적용하지 않는다.
3. Plan을 Apply하고 ACM이 `ISSUED`, CloudFront가 `Deployed`가 될 때까지 기다린다. Terraform의
   `create_before_destroy`가 기존 Viewer 인증서를 유지한 채 두 hostname 인증서를 먼저 발급한다.
4. 아래 DNS·TLS·Alias 검증 뒤 Kiosk Front의 진입 URL을 전환한다. 문제 발생 시 먼저 Kiosk 진입을
   중단하고, 검토된 이전 Terraform 값으로 되돌리는 Plan을 새로 생성한다.

주요 위험은 ACM DNS 검증 실패로 인한 Apply 대기, 이미 다른 Distribution에서 사용 중인 Kiosk Alias로
인한 CloudFront 배포 실패, AAAA 전파 뒤 IPv6 경로 검증 누락, Backend가 상위 Domain Cookie를 발급해
세션 격리가 무효화되는 경우다. DNS Alias를 먼저 별도 생성하지 않고 인증서와 Distribution 배포를
Terraform 의존성 순서에 맡긴다.

```bash
aws s3 sync FRONTEND_DIST_DIR "s3://$(terraform output -raw frontend_bucket_name)" --delete
aws cloudfront list-distributions \
  --query "DistributionList.Items[?Aliases.Items[?@=='doro.minseok.click'] && Aliases.Items[?@=='kiosk.minseok.click']].[Id,Status,DomainName,Aliases.Items]" \
  --output table

dig +short A doro.minseok.click
dig +short A kiosk.minseok.click
dig +short AAAA kiosk.minseok.click
curl -fsSI https://doro.minseok.click/
curl -fsSI https://kiosk.minseok.click/
```

두 hostname에서 인증 API를 호출한 뒤 응답의 `Set-Cookie`에 `Domain` 속성이 없는지 확인하고,
브라우저 개발자 도구에서 각 hostname의 Cookie가 다른 hostname 요청에 포함되지 않는지 확인한다.
Terraform에는 `/` 정적 SPA와 `/api/*` CloudFront Ordered Cache Behavior·VPC Origin이 코드화돼 있다. 다만 AWS Load Balancer Controller가 생성하는 내부 ALB와 HTTPS Listener를 포함한 실제 AWS Apply·Runtime 연결은 아직 검증되지 않았다.
