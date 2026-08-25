# Doro ERP Prod 배포 인프라 설계

> 문서 상태: 최종 배포·시연 환경 구현 기준선
>
> 대상 환경: AWS `prod` / Alpha Cell
>
> 리전: `ap-northeast-2`
>
> 현재 구현 상태: `team2` Prod VPC 전체를 별도 Terraform Network State가 생성·관리하고 Foundation·Redis·Atlas가 Remote State Output으로 참조한다.

## 1. 목적과 범위

이 문서는 4인 부트캠프 프로젝트의 최종 배포와 시연에 사용할 단일 AWS `prod` 환경을 정의한다. 환경 이름은 `prod`지만 상용 운영 수준의 고가용성을 그대로 복제하지 않고, EKS와 Application Load Balancer(ALB)의 필수 다중 AZ 조건은 지키면서 실제 유료 워크로드는 한 AZ에 집중한다.

현재 범위는 다음과 같다.

- 별도 AWS Prod Account를 만들지 않고 현재 사용하는 한 AWS Account에 구축한다.
- `prod` 환경의 `alpha` Cell만 구축한다.
- AWS 자원은 Terraform으로 관리한다.
- 계정에 이미 존재하는 네 명의 IAM User와 계정 공용 GitHub OIDC Provider는 재사용하되, 프로젝트 IAM Group·Role·Policy는 Bootstrap Terraform이 생성한다. 공용 OIDC Provider는 Data Source로만 조회한다.
- Kubernetes 자원의 선언은 Kustomize로 관리한다. 초기 통합 단계에서는 승인된 Overlay를 수동 적용하고, 도입 가능 기준을 충족한 뒤 Argo CD가 같은 선언을 GitOps 방식으로 동기화한다.
- GitHub Actions가 테스트·이미지 빌드·ECR Push를 담당한다.
- 별도 `dev` AWS 환경은 만들지 않고 Local·CI 검증을 통과한 Image만 이 환경에 배포한다.

비용 상한은 현재 설계의 승인 조건으로 두지 않는다. 다만 학습·테스트에 필요하지 않은 중복 자원은 만들지 않고, 사용하지 않는 자원의 중지·삭제가 가능하도록 모든 자원을 코드로 관리한다.

## 2. 확정 사항

| 구분 | 결정 |
|---|---|
| AWS Account | 별도 Prod Account 없이 `727646470302` Account 사용 |
| Region | `ap-northeast-2` |
| Environment / Cell | `prod` / `alpha` |
| Network | Terraform 관리형 Prod VPC(`10.24.0.0/16`), IGW 1개, NAT 1개, Public·Application·Data Subnet 각 2개 |
| Availability Zones | az-a = `ap-northeast-2a`(`apne2-az1`), az-b = `ap-northeast-2c`(`apne2-az3`) |
| Compute | EKS `1.36`, 관리형 Node Group `t3.large` 최소 2대·최대 4대, Root Volume `gp3` 50 GiB, AZ-a 배치 |
| Application | 서비스별 최소 Replica 2개, HPA 최대 4개, PDB 적용 |
| API Routing | AWS Load Balancer Controller Gateway API, Edge HTTPRoute, 내부 ALB 1개 |
| PostgreSQL | RDS for PostgreSQL `17.10`, `db.t4g.small`, `gp3` 20 GiB, Single-AZ Instance 1개, 서비스별 Database 4개 |
| Redis | ElastiCache for Redis OSS 7.1, Prod Alpha Store Access 전용, TLS·RBAC |
| MongoDB | MongoDB Atlas 8.0 M0 Free, Prod Alpha Audit 전용, NAT 고정 IP `/32` 허용 |
| Messaging | Alpha 전용 FIFO Main Queue 3개와 FIFO DLQ 3개 |
| Container Registry | Amazon ECR, Git SHA 기반 불변 Image Tag |
| 배포 | 초기 Kustomize 수동 적용 → 통합 안정화 후 GitHub Actions → ECR → GitOps Commit → Argo CD |
| Secret | AWS Secrets Manager, 서비스별 EKS Pod Identity, AWS Secrets Store CSI Provider |
| 관리 접속 | CloudShell의 `kubectl`로 EKS 관리, SSM으로 Worker Node와 전용 관리 EC2 접속 |
| Prod Domain | `doro.minseok.click` |
| Public DNS | Bootstrap Terraform이 Route 53 Public Hosted Zone `minseok.click` 생성, 등록기관에서 NS 위임 |
| 관리 태그 | `Project=Doro-ERP`, `Environment=prod`, `Cell=alpha`, `Team=team2`, `ManagedBy=terraform` |

## 3. AZ 구성 원칙

이 환경의 구성 원칙은 **2-AZ Control/Network Plane + 1-AZ Prod Workload**다.

- EKS Cluster 생성 시 서로 다른 AZ의 Subnet이 최소 2개 필요하다.
- ALB는 내부 ALB도 서로 다른 AZ의 Subnet을 최소 2개 선택해야 한다.
- RDS DB Subnet Group은 서로 다른 AZ의 Subnet을 최소 2개 포함해야 한다.
- CloudFront는 전역 서비스이므로 위 2-AZ 조건의 원인이 아니다. 다만 VPC Origin으로 사용할 내부 ALB가 ALB의 2-AZ 조건을 따른다.
- EKS 관리형 Node Group은 AZ-a의 Application Subnet만 사용한다.
- Application Pod는 AZ-a Node에서 실행한다. Redis는 Data Subnet의 ElastiCache, MongoDB는 Atlas 서울 Region에서 운영한다.
- RDS Instance는 AZ-a에 Single-AZ로 생성한다. DB Subnet Group에는 AZ-a와 AZ-b를 모두 등록한다.
- NAT Gateway는 AZ-a에 1개만 생성한다.
- ALB는 AZ-a와 AZ-b에 걸쳐 생성되지만 Target Pod는 AZ-a에만 존재할 수 있다. 이는 개발 환경 축소안이며 AZ-a 장애를 견디는 고가용성 구성은 아니다.

AZ 이름은 AWS Account마다 물리 Zone과의 매핑이 다를 수 있으므로 설계에서는 논리 이름을 사용한다. 이 Account에서 `az-a`는 `ap-northeast-2a`(`apne2-az1`), `az-b`는 두 번째 사용 AZ인 `ap-northeast-2c`(`apne2-az3`)로 확정한다.

## 4. 네트워크 설계

### 4.1 Subnet 계획

| 논리 이름 | CIDR | AZ | 용도 |
|---|---|---|---|
| `private-app-a` | `10.24.10.0/24` | `ap-northeast-2a` | EKS Node·Pod, EKS Cluster ENI, 내부 ALB |
| `private-app-c` | `10.24.11.0/24` | `ap-northeast-2c` | EKS Cluster ENI, 내부 ALB의 두 번째 AZ |
| `private-data-a` | `10.24.20.0/24` | `ap-northeast-2a` | RDS Primary와 DB Subnet Group |
| `private-data-c` | `10.24.21.0/24` | `ap-northeast-2c` | RDS DB Subnet Group의 두 번째 AZ |
| `public-a` | `10.24.0.0/24` | `ap-northeast-2a` | NAT Gateway |
| `public-c` | `10.24.1.0/24` | `ap-northeast-2c` | ALB·향후 AZ 확장 |

VPC와 Subnet, Internet Gateway, Route Table, NAT Gateway, S3 Gateway Endpoint와 Interface Endpoint를 별도 Network Terraform State가 생성한다. Foundation·Redis·Atlas Stack은 고정 AWS ID를 저장하지 않고 Network Remote State Output을 읽는다. Public-a에는 비용 절감용 NAT Gateway와 Elastic IP를 하나만 두며 Private Application Route Table의 기본 경로가 이를 사용한다. Data Route Table에는 Internet 기본 경로를 두지 않는다.

CloudFront VPC Origin은 Private Application Subnet의 내부 ALB를 사용하며, CloudFront가 생성하는 Service-managed ENI를 위한 가용 IP를 유지한다.

Kubernetes Service CIDR는 VPC, VPN, 팀원 로컬 네트워크와 겹치지 않아야 한다. 실제 네트워크 목록을 확인한 후 Terraform 변수로 명시하며 자동 선택에 의존하지 않는다.

### 4.2 Terraform State 경계

Network는 `environments/prod/network/terraform.tfstate`, Foundation은 `environments/prod/terraform.tfstate`를 사용한다. Redis와 Atlas도 각각 별도 State를 사용한다. Apply는 Network→Foundation→Redis→Atlas 순서이며 Destroy는 반대 순서다.

Frontend S3와 Terraform Backend S3는 Network State에 포함하지 않는다. Terraform Backend S3와 Route 53 Public Hosted Zone은 Bootstrap State, Frontend S3는 Foundation State가 생성한다. Foundation은 Bootstrap Remote State에서 Hosted Zone ID를 읽는다. 신규 자원은 `doro-erp-prod-*` 이름과 `Team=team2`를 포함한 공통 Tag로 구분한다.

### 4.3 NAT와 Private AWS 접근

- Private Application Subnet의 기본 경로는 AZ-a의 단일 NAT Gateway를 사용한다.
- SSM 접속은 Terraform이 만든 `ssm`, `ssmmessages`, `ec2messages` Interface Endpoint를 사용한다.
- ECR API·ECR DKR·Secrets Manager·CloudWatch Logs·SQS·STS Interface Endpoint와 S3 Gateway Endpoint를 Network State가 관리한다.
- Interface Endpoint ENI는 Prod 비용 절감을 위해 AZ-a에 한 개씩 두며 AZ-c는 VPC 내부 경로로 접근한다.
- Data Subnet Route Table에는 Internet 기본 경로를 추가하지 않는다.

### 4.4 트래픽 경로

```text
사용자
  → Route 53
  → CloudFront + WAF
  → CloudFront VPC Origin
  → 내부 ALB (private-app-a, private-app-c)
  → EKS Service / Pod (private-app-a)
  → RDS·ElastiCache Redis 또는 NAT Gateway를 통한 MongoDB Atlas M0
```

- Frontend는 S3에 배포하고 CloudFront OAC를 통해서만 제공한다.
- `/api/*`만 내부 ALB로 전달한다.
- Database, Redis, MongoDB와 내부 관리 Endpoint는 외부에 공개하지 않는다.
- Payment Service의 Toss Test API 호출처럼 승인된 외부 HTTPS 요청만 NAT Gateway를 사용한다.

### 4.5 관리 접속

- EKS Cluster와 Kubernetes Resource는 AWS Console CloudShell에서 EKS Access Entry와 `kubectl`로 관리한다.
- EKS Managed Node Group Instance에는 `AmazonSSMManagedInstanceCore`를 부여해 장애 진단 시 Session Manager로 접속할 수 있게 한다.
- 별도 관리 EC2 1대를 Private Application Subnet에 두고 RDS·Redis·MongoDB 연결 점검에 사용한다.
- 관리 EC2는 Amazon Linux 2023 `t4g.micro`, Public IP 없음, Key Pair 없음, Inbound Security Group Rule 없음으로 구성한다.
- SSH 22번 Port를 공개하지 않고 감사 가능한 전용 Session Document와 IAM 권한을 접속 경계로 사용한다.
- Shell 입출력은 `/doro-erp/prod/ssm-sessions` CloudWatch Log Group에 30일 보존하며 Idle 20분, 최대 60분으로 제한한다.
- 명령 기록이 지원되지 않는 SSM SSH와 Port Forwarding Session은 사용자 정책에서 허용하지 않는다.
- Bootstrap은 `team2-doro-load-group`을 생성하고 `a-student-02`, `a-student-06`, `b-student-05`, `b-student-11`을 정확한 멤버십으로 관리한다.
- Terraform 실행 Role을 Assume하는 운영자는 `a-student-02`, `a-student-06`, `b-student-05`, `b-student-11` 네 명으로 관리한다.
- Bootstrap은 네 운영자를 `doro-erp-prod-terraform-operators` Group에 넣고 `doro-erp-prod-terraform` Role을 Assume하는 Identity Policy도 함께 연결한다.

## 5. EKS와 Application 구성

- EKS Cluster Subnet: `private-app-a`, `private-app-c`
- 관리형 Node Group Subnet: `private-app-a`만 사용
- Kubernetes Version: `1.36`
- Node Instance: `t3.large`, Root Volume `gp3` 50 GiB
- Node 수: Desired/Min/Max를 `2/2/4`로 구성하고 Cluster Autoscaler가 Desired를 조정
- Cell Namespace: `doro-alpha`
- 서비스: Edge, Store Access, Commerce, Payment, Queue, Audit
- 서비스별 Deployment와 HPA 최소 Replica: 2, HPA 최대 Replica: 4
- Edge 단일 HTTPRoute가 Alpha 내부 ALB 1개의 `/api/v1` 경계를 소유하고 Module은 ClusterIP만 소유
- AWS 권한은 서비스별 Pod Identity로 분리
- Redis는 Prod Alpha 전용 ElastiCache 단일 Node로, MongoDB는 발표용 Atlas M0 Free Cluster로 운영

ElastiCache는 Prod 비용 절감을 위해 단일 Node로 구성하므로 자동 Failover를 제공하지 않는다. Atlas M0는 PrivateLink와 Cloud Backup/PIT를 제공하지 않으며 Network Terraform이 만든 NAT Gateway의 고정 공인 IP만 Database Network Access에 허용한다. 발표 데이터는 재생성 가능한 것으로 제한하고 운영 전에는 M10 이상, PrivateLink, Backup, RPO·RTO와 비용을 다시 확정한다.

## 6. 데이터와 Messaging

### 6.1 RDS PostgreSQL

`ap-northeast-2a`의 PostgreSQL `17.10` Single-AZ Instance에 다음 Database를 둔다. Instance Class는 `db.t4g.small`, Storage는 `gp3` 20 GiB를 사용한다.

- `store_access_db`
- `commerce_db`
- `payment_db`
- `queue_db`

서비스별 Runtime Role과 Flyway Migration Role을 분리하고 Application Pod에 Master Credential을 제공하지 않는다. Public Access는 비활성화한다.

### 6.2 SQS FIFO

다음 Main Queue와 각 Queue의 DLQ를 생성한다.

- `doro-erp-prod-alpha-commerce-events.fifo`
- `doro-erp-prod-alpha-queue-events.fifo`
- `doro-erp-prod-alpha-audit-events.fifo`

DLQ 이름은 각 논리 이름 뒤에 `-dlq.fifo`를 붙인다. Queue URL과 ARN은 Terraform Output 또는 배포 설정을 통해 주입하며 Application이 이름을 임의로 조립하지 않는다. 서비스별 Pod Identity에는 필요한 Send 또는 Receive/Delete 권한만 부여한다.

## 7. AWS 접근과 Terraform 권한

Terraform을 직접 실행하는 팀원은 공유 Access Key를 사용하지 않고 자신의 AWS Principal로 인증한다. 로컬 AWS CLI Profile 이름은 `erp-prod`를 사용한다. 인증한 Principal은 같은 Account의 Terraform 실행 Role을 Assume한다. Application 개발·검토만 수행하는 팀원에게는 Terraform Role 접근 권한이 필요하지 않다.

```text
팀원 개인 AWS Principal
  → sts:AssumeRole
  → doro-erp-prod-terraform
  → Prod Terraform 자원 생성·변경
```

- Terraform Role 이름: `doro-erp-prod-terraform`
- Role ARN: `arn:aws:iam::727646470302:role/doro-erp-prod-terraform`
- 현재 Bootstrap Principal: `arn:aws:iam::727646470302:user/b-student-05`
- Trust Policy: 최초에는 현재 Bootstrap Principal만 Assume을 허용하고, Terraform을 직접 실행할 팀원이 생길 때 해당 Principal ARN을 추가
- Permission Policy: 이 문서의 Prod 자원 생성·조회·변경·삭제 범위로 제한
- GitHub Actions: Bootstrap이 계정 공용 `token.actions.githubusercontent.com` OIDC Provider를 읽기 전용으로 재사용하고 프로젝트 전용 Role만 생성한다. 기존 Provider의 태그·Thumbprint·Client ID는 변경하지 않는다. 장기 Access Key를 사용하지 않으며 GitHub Organization ID `305760709`, Service Repository ID `1314731823`과 `prod` Environment를 포함한 Subject로 신원을 제한한다.
- Terraform State: `doro-erp-prod-tfstate-727646470302-ap-northeast-2` S3 Bucket에 Versioning과 암호화를 적용하고 S3 Lockfile 사용
- Credential, Secret 원문, `.env`는 Git과 Terraform 변수 기본값에 저장하지 않음

Terraform Role과 State Backend를 처음 만드는 Bootstrap 작업은 AWS Account 관리 권한을 맡은 팀원이 수행한다. 이후 일반 인프라 변경은 Terraform Role을 통해 실행한다.

현재 설치된 Terraform `1.15.8 windows_386`은 HashiCorp의 공식 Windows 배포 대상이고 AWS Provider도 Windows 386 바이너리를 제공하므로 Bootstrap·Plan·Apply의 필수 교체 대상은 아니다. 다만 64비트 Windows에서는 더 넓은 메모리 주소 공간과 일반적인 도구 구성을 위해 `windows_amd64`를 권장한다. 현재 386 환경에서 `terraform init`, `validate`, `plan`이 모두 성공하면 그대로 진행할 수 있다.

EKS API Endpoint는 Private Access를 활성화하고, 초기 개발 편의를 위해 Public Access도 제한적으로 활성화한다. Public Access CIDR에는 팀원이 사용하는 고정 공인 IP만 등록한다. EKS 권한은 Access Entry로 부여하며 `0.0.0.0/0` 공개와 장기 관리자 Credential 공유는 허용하지 않는다.

### 7.1 다른 팀원의 Terraform 실행 권한 등록 가이드

Application 개발·검토만 수행하는 팀원은 이 등록이 필요하지 않다. Terraform `plan` 또는 `apply`를 직접 실행할 팀원만 다음 절차로 등록한다. Access Key, Secret Access Key와 Session Token은 전달하지 않고 Principal ARN만 공유한다.

#### 1단계: 팀원이 자신의 IAM User 이름 확인

권한을 추가할 팀원이 자신의 AWS 인증으로 다음 명령을 실행한다.

```powershell
aws sts get-caller-identity --profile erp-prod --output json
```

출력의 `Arn`에서 마지막 IAM User 이름을 확인한다. IAM User라면 다음과 같은 형태다.

```text
arn:aws:iam::727646470302:user/IAM_USER_NAME
```

`Account`, `Arn`과 `UserId`는 인증 정보 원문이 아니지만 Terraform에 필요한 값은 IAM User
이름뿐이다. AWS CLI 설정 파일, Access Key, Secret Access Key와 Session Token은 전달하거나
Git에 Commit하지 않는다.

#### 2단계: Terraform 운영자 Group 멤버 추가

Bootstrap의 `terraform_operator_user_names`에 승인된 팀원의 IAM User 이름을 추가한다. IAM
Console에서 Group, 정책 또는 Trust Policy를 수동으로 수정하지 않는다.

```hcl
terraform_operator_user_names = [
  "a-student-02",
  "a-student-06",
  "b-student-05",
  "b-student-11"
]
```

Bootstrap은 이 목록을 `doro-erp-prod-terraform-operators` Group의 정확한 멤버십,
`sts:AssumeRole` Identity Policy와 Role Trust Policy에 함께 반영한다. `*` 또는 Account 전체
`root` Principal로 확대하지 않는다. Role을 Assume할 주체를 추가하는 변경이므로 Pull Request
검토 후 Bootstrap Terraform에서 Apply한다.

#### 3단계: Terraform이 만든 AssumeRole 권한 확인

Bootstrap이 다음 권한의 관리형 정책을 운영자 Group에 연결한다. 사용자에게 같은 정책을
수동으로 다시 붙이지 않는다.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "sts:AssumeRole",
      "Resource": "arn:aws:iam::727646470302:role/doro-erp-prod-terraform"
    }
  ]
}
```

Trust Policy는 **누가 Role을 Assume할 수 있는지** 정의하고, 위 Identity Policy는 **해당 사용자가 어떤 Role에 AssumeRole을 요청할 수 있는지** 정의한다. Permission Boundary 또는 명시적 Deny가 있으면 두 정책이 있어도 요청이 거부될 수 있다.

#### 4단계: 팀원 로컬 AWS Profile 구성

각 팀원은 자신의 인증 Profile과 Terraform Role Profile을 로컬에서 분리한다. 다음은 `%UserProfile%\.aws\config`의 기준 형식이다.

```ini
[profile erp-prod-source]
region = ap-northeast-2
output = json

[profile erp-prod]
role_arn = arn:aws:iam::727646470302:role/doro-erp-prod-terraform
source_profile = erp-prod-source
role_session_name = doro-erp-prod-IAM_USER_NAME
region = ap-northeast-2
output = json
```

- `erp-prod-source`: 팀원 자신의 IAM 인증을 보관하는 로컬 전용 Profile
- `erp-prod`: Terraform Role을 Assume해 임시 Credential을 받는 공통 실행 Profile
- `role_session_name`: CloudTrail에서 실행자를 구분할 수 있도록 팀원 IAM User 이름을 포함

팀원끼리 공유할 수 있는 것은 Profile 구성의 기준 형식뿐이다.

| 항목 | 공유 여부 | 이유 |
|---|---|---|
| Profile 이름, `region`, `output` | 가능 | 인증 정보가 아닌 공통 설정 |
| Terraform `role_arn` | 가능 | 접근 대상 Role의 식별자이며 Secret이 아님 |
| `source_profile` 이름 규칙 | 가능 | 각 팀원의 로컬 인증 Profile을 가리키는 이름 |
| Access Key ID | 금지 | 장기 인증 정보의 일부 |
| Secret Access Key | 금지 | 장기 인증 Secret |
| Session Token·Login Cache | 금지 | 유효 기간 동안 인증에 사용 가능 |
| `%UserProfile%\.aws\credentials` 파일 | 금지 | 개인 Credential 포함 |
| 전체 `%UserProfile%\.aws` 폴더 | 금지 | Credential·Login Cache가 함께 포함될 수 있음 |

하나의 Access Key를 여러 팀원이 복사하면 누가 작업했는지 CloudTrail에서 구분하기 어렵고, 한 명의 유출·탈퇴·권한 회수 때문에 모든 팀원의 Key를 동시에 교체해야 한다. 따라서 공유 Access Key가 이미 있더라도 폐기 대상으로 관리하고, 각 팀원의 개인 Principal에서 `doro-erp-prod-terraform` Role을 Assume한다.

현재 개인 인증에 `erp-prod` 이름을 사용 중이라면 먼저 해당 Profile을 `erp-prod-source`로 옮긴 뒤 Role Profile을 `erp-prod`로 구성한다. Profile 변경 전 기존 `%UserProfile%\.aws\config`와 `credentials`는 외부에 공유하지 않고 로컬에서만 백업한다.

#### 5단계: AssumeRole 검증

```powershell
aws sts get-caller-identity --profile erp-prod --output json
```

성공하면 `Arn`이 다음 STS Assumed Role 형태로 표시돼야 한다.

```text
arn:aws:sts::727646470302:assumed-role/doro-erp-prod-terraform/doro-erp-prod-IAM_USER_NAME
```

IAM User ARN이 그대로 나오면 아직 Source Profile을 사용 중인 것이므로 Terraform을 실행하지 않는다. `AccessDenied`가 발생하면 Role Trust Policy, 팀원 Principal의 `sts:AssumeRole` 권한과 Permission Boundary를 순서대로 확인한다.

#### 6단계: Terraform 실행

Terraform은 개인 Source Profile이 아니라 Role Profile을 사용한다.

```powershell
$env:AWS_PROFILE = "erp-prod"
$env:AWS_REGION = "ap-northeast-2"

terraform init
terraform validate
terraform plan
```

- 최초 실행은 `plan`까지만 수행하고 다른 팀원의 검토를 받는다.
- 동시에 두 명이 `apply`하지 않는다. S3 Backend Lock이 잡혀 있으면 강제로 해제하지 않고 실행자를 확인한다.
- `apply`는 승인된 Plan과 Branch에서 한 명만 실행한다.
- 개인 Profile 이름, Credential과 로컬 경로를 Terraform 코드·변수에 넣지 않는다.
- 긴급한 경우에도 AWS Console에서 Terraform 관리 자원을 직접 수정하지 않는다.

#### 7단계: 권한 회수

팀원이 더 이상 Terraform을 실행하지 않으면 승인된 Principal 목록에서 해당 ARN을 제거하고 Bootstrap Terraform을 Apply한다. 필요한 경우 팀원 Principal에 연결된 `sts:AssumeRole` 정책도 제거한다. 이미 발급된 임시 Role Session은 설정된 Session 만료 시점까지 유효할 수 있으므로 민감한 권한 회수는 활성 Session과 CloudTrail 기록도 함께 확인한다.

참고 문서:

- [AWS IAM Role Trust Policy 변경](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_update-role-trust-policy.html)
- [AWS IAM Principal 요소](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_elements_principal.html)
- [IAM User의 Role 전환 권한](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_use_permissions-to-switch.html)

## 8. 배포 흐름

다음 흐름은 Argo CD 도입 가능 기준을 충족한 이후의 목표 배포 흐름이다. 초기 Foundation·Data 구축과 첫 Application 통합 배포에는 Argo CD를 선행조건으로 두지 않는다.

1. Pull Request에서 Application 테스트와 인프라 정적 검증을 수행한다.
2. 승인된 Commit을 GitHub Actions가 Build한다.
3. Git SHA를 Image Tag로 사용해 ECR에 Push한다.
4. 배포 저장소의 Kustomize Image Tag를 해당 SHA로 갱신한다.
5. Argo CD가 Git의 목표 상태를 EKS에 동기화한다.
6. ALB Health Check와 Application Smoke Test로 배포를 확인한다.

Terraform은 AWS 기반 자원을 관리하고 Argo CD는 Kubernetes 자원을 관리한다. Argo CD에서 Terraform Apply를 실행하지 않는다.

## 9. Argo CD 도입 시기와 가능 기준

### 9.1 도입 원칙

Argo CD는 Prod 인프라의 Bootstrap·Foundation·Data 자원 생성에 필요한 선행 구성요소가 아니다. EKS, ECR, RDS, SQS, Pod Identity와 Application Manifest가 각각 정상 동작하는지 먼저 검증한 뒤 배포 자동화 단계에서 도입한다.

- Argo CD 도입 전에도 Kubernetes Manifest의 정본은 Git의 Kustomize Base와 Prod Alpha Overlay다.
- 초기 배포는 `Doro-ERP-GitOps`에서 `kubectl apply -k deploy/overlays/prod/alpha`처럼 승인된 Overlay 단위로 수행한다.
- `kubectl edit`, AWS Console 또는 임시 `kubectl set image`로 만든 변경을 Git에 반영하지 않은 채 유지하지 않는다.
- Argo CD 도입을 이유로 Deployment·Service·Ingress를 Terraform 관리 대상으로 옮기지 않는다.
- Argo CD 도입 후에는 Git을 통하지 않은 Cluster 변경을 Drift로 탐지하고 Git의 목표 상태로 복구한다.

### 9.2 도입 가능 기준

다음 조건을 모두 충족해야 Argo CD 설치와 Repository 연결을 시작할 수 있다.

- `Doro-ERP-GitOps/deploy/base`에 Edge를 포함한 여섯 서비스의 Deployment·Service와 필요한 공통 Manifest가 존재한다.
- `Doro-ERP-GitOps/deploy/overlays/prod/alpha`를 `kustomize build` 또는 `kubectl kustomize`로 오류 없이 렌더링할 수 있다.
- 여섯 Application Image가 ECR에 Git SHA 또는 Image Digest로 존재하며 EKS에서 Pull할 수 있다.
- 승인된 Prod Alpha Overlay의 수동 적용과 재적용이 성공한다.
- 여섯 Application의 Startup·Readiness·Liveness Probe와 기본 Smoke Test가 통과한다.
- 서비스별 Runtime Credential과 Flyway Migration Credential이 분리되고 Migration Job 실행 순서가 확정된다.
- Secrets Manager·Pod Identity를 통해 Secret을 주입하며 Git과 Manifest에 Secret 원문이 없다.
- Application의 CPU·Memory Request가 정의되어 Argo CD 구성요소를 포함해 단일 Prod Node에서 기동 가능한지 확인했다.
- GitHub Actions가 테스트, 불변 Image Push와 Prod Overlay Image Digest 변경을 수행할 수 있다.
- Argo CD가 읽을 Git 경로, Repository 인증 방식, AppProject와 서비스별 Application 소유권이 확정됐다.

하나라도 충족하지 못하면 Argo CD로 문제를 감추지 않고 수동 Kustomize 배포 단계에서 원인을 해결한다.

### 9.3 단계별 도입

1. Foundation·Data 단계에서는 Argo CD 없이 EKS와 AWS 의존성을 검증한다.
2. 여섯 Application을 Kustomize Prod Alpha Overlay로 수동 배포하고 재현성을 검증한다.
3. Argo CD를 설치한 뒤 서비스별 Application을 생성하고 처음에는 수동 Sync로 Git과 Live State의 Diff를 확인한다.
4. 수동 Sync, Health 판정, Migration과 Rollback 검증이 끝나면 Prod에 자동 Sync를 활성화한다.
5. Git 외부 변경의 Drift 탐지·Self Heal과 Git에서 제거된 자원의 Prune을 안전한 테스트 Resource로 검증한다.
6. Production 후보 환경은 승인된 Overlay 변경 후 Sync하는 정책을 사용하며 Prod 자동 Sync 정책을 그대로 복사하지 않는다.

Prod 자동 Sync의 목표 정책은 `selfHeal=true`, `prune=true`다. 다만 최초 연결과 삭제 영향 검증 전에는 자동 Sync와 Prune을 활성화하지 않는다.

### 9.4 도입 완료 Gate

- 서비스별 Application이 각자의 Kustomize 경로와 ECR Image Digest를 추적한다.
- Git Commit 변경이 대상 서비스에만 반영되고 변경되지 않은 서비스는 재배포되지 않는다.
- 수동 Cluster 변경이 `OutOfSync`로 탐지되고 승인된 정책에 따라 복구된다.
- Migration 실패 시 Application Sync가 중단되고 기존 Ready Version이 유지된다.
- 배포 성공 후 ALB Health Check, Application Smoke Test와 핵심 Event 수렴을 확인한다.
- 실패한 Application은 이전 Image Digest를 가리키는 Git Revert로 복구할 수 있다. 이미 적용된 Flyway Migration은 되돌리지 않고 Forward-fix한다.
- Argo CD Repository Credential, Token과 Secret 원문이 Git, Manifest와 Log에 노출되지 않는다.

## 10. 구현 순서

### 1단계: Bootstrap

- `erp-prod` 로그인과 Account ID 확인 완료
- `ap-northeast-2a`와 `ap-northeast-2c` 및 Zone ID 선택 완료
- Terraform State S3 Backend 생성
- `doro-erp-prod-terraform` Role과 GitHub OIDC Role 구성

### 2단계: Network

- VPC·Subnet 6개·Route Table 3개와 Internet Gateway 1개 생성
- NAT Gateway 1개와 Private Application 기본 Route 생성
- SSM·ECR·Logs·Secrets Manager·SQS·STS Interface Endpoint와 S3 Gateway Endpoint 생성

### 3단계: Foundation

- EKS Cluster, 관리형 Node Group, ECR와 기본 IAM
- EKS Access Entry, Worker Node SSM, 감사 Session Document와 관리 EC2

### 4단계: Cluster Add-on과 Data

- AWS Load Balancer Controller
- RDS PostgreSQL, Secrets Manager, CSI Provider와 SQS FIFO/DLQ
- ElastiCache Redis와 MongoDB Atlas M0·NAT IP Access List 전용 Terraform Stack

### 5단계: Application 수동 통합 배포

- `Doro-ERP-GitOps`가 소유하는 서비스별 Kustomize Base와 Prod Alpha Overlay
- ECR Image Pull, Migration Job과 Secret 주입
- `kubectl apply -k` 재적용, Health Check와 Smoke Test
- 여섯 Application의 독립 배포와 Resource 사용량 검증

### 5단계: Argo CD와 GitOps

- 9.2절의 도입 가능 기준 충족 확인
- Argo CD 설치와 Repository 인증
- 서비스별 AppProject·Application과 초기 수동 Sync
- Prod 자동 Sync·Self Heal·Prune과 Git Revert 검증
- GitHub Actions의 Image Digest 갱신과 Argo CD 배포 경로

### 6단계: Edge

- 내부 ALB와 Edge 단일 Gateway API HTTPRoute
- S3 Frontend, CloudFront VPC Origin, WAF, ACM과 Route 53
- Health Check, Smoke Test와 재배포 검증

## 11. 상용 운영 수준 확장 원칙

현재 `prod`는 프로젝트 최종 배포·시연 환경이며 상용 서비스의 고가용성 환경을 의미하지 않는다. 상용 운영이 필요해지면 현재 State를 즉흥적으로 확장하지 않고 별도 Account·State와 승인된 가용성 기준으로 새 환경을 만든다.

운영 후보 환경에서는 다음을 다시 결정한다.

- Stateless Application을 최소 2개 AZ와 Replica 2개 이상으로 분산
- EKS Node Group 다중 AZ 구성과 Auto Scaling
- RDS Multi-AZ, Backup 보존, RPO·RTO
- ElastiCache Multi-AZ·Replica와 Failover 구성
- MongoDB Atlas Tier·복제 Region, Backup 보존과 TTL 복구 정책
- NAT Gateway 다중 AZ 여부
- 운영 Account 분리 여부와 배포 승인 절차
- Domain, 인증서, WAF 규칙과 관측·경보 기준

현재 Prod 구성의 코드와 배포 규칙은 재사용할 수 있지만, 현재의 1-AZ Workload·Single-AZ RDS·단일 Redis·Atlas M0를 상용 운영 환경으로 판정하지 않는다.

## 12. 단계별 확인이 필요한 값

다음 값은 모두 첫 Bootstrap Apply의 선행조건은 아니며, 해당 자원을 생성하거나 접근 권한을 열기 전에 결정한다.

- Kubernetes Service CIDR
- RDS Backup 보존일
- ElastiCache Snapshot 보존과 운영 Atlas Cloud Backup·PIT 보존 기간
- 팀원별 EKS Public Endpoint 허용 CIDR
- 도메인 등록기관에서 Terraform 출력의 Route 53 네임서버로 `minseok.click` NS 위임
- Argo CD 자체 설치 또는 EKS Managed Capability 선택과 비용
- Argo CD Git Repository 인증, AppProject·Application 구성과 운영 주체
- 추가 팀원이 Terraform을 직접 실행해야 할 경우에만 해당 팀원의 IAM User 이름

## 13. AWS 공식 제약 근거

- [Amazon EKS VPC 및 Subnet 요구사항](https://docs.aws.amazon.com/eks/latest/userguide/network-reqs.html): Cluster 생성 시 서로 다른 AZ의 Subnet을 최소 2개 지정한다.
- [Application Load Balancer Subnet](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/application-load-balancers.html#subnets-load-balancer): Availability Zone Subnet을 최소 2개 선택하며 각 Subnet은 서로 다른 AZ에 있어야 한다.
- [RDS CreateDBSubnetGroup](https://docs.aws.amazon.com/AmazonRDS/latest/APIReference/API_CreateDBSubnetGroup.html): DB Subnet Group은 최소 2개 AZ의 Subnet을 포함한다.
- [CloudFront VPC Origin](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-vpc-origins.html): Private Subnet의 내부 ALB를 CloudFront Origin으로 사용할 수 있다.
