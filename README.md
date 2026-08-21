# Doro-ERP-Infra

Doro SaaS POS·Kiosk의 로컬 통합 환경, Cloud 자원, 배포 Manifest와 운영 계약을 소유한다.

> 현재 상태: Local 통합 환경, Dev Alpha AWS Foundation·ElastiCache Redis·MongoDB Atlas Terraform과 여섯 Application의 Kustomize Base·Secrets Manager 연결, AWS Load Balancer Controller 권한·설치 값, Edge 단일 Public Ingress와 Dev Alpha NetworkPolicy가 구현되어 있다. 모든 Runtime은 최소 2 Replica와 서비스별 HPA·PDB를 사용한다. Dev Worker는 비용과 현재 운영 제약을 반영해 단일 AZ에서 서로 다른 Node로 분산하며, Managed Node Group과 Cluster Autoscaler가 Node 2대에서 최대 4대까지 확장한다. EKS Metrics Server, CloudWatch Observability Add-on, Container Insights Log 보존, 운영 SNS Topic과 Node·Pod·DLQ·ALB 최소 경보도 코드에 반영되어 있다. GitHub OIDC 기반 ECR Push Role과 Service Image 게시 Workflow도 정의되어 있다. ALB HTTPS Listener·Regional ACM 인증서와 CloudFront HTTPS VPC Origin 구성도 코드에 반영되어 있지만 실제 AWS Listener·인증서 연결, Autoscaler Scale-out/in, Log 수집·Alarm 전달, CNI Policy Enforcement와 가용성 장애 검증은 별도로 확인해야 한다. 자동 CD와 Argo CD는 Dev 수동 Release를 검증한 뒤 도입한다.
>
> 목표 구조와 구현 완료를 혼동하지 않는다. 실제 인프라가 추가되면 실행 명령, 검증 명령과 복구 절차를 같은 변경에 포함한다.

상위 제품·기술 기준은 다음 문서를 따른다.

- [Doro SaaS POS·Kiosk 제품·시스템 개요](../Docs/Doro_SaaS_POS_Kiosk.md)
- [AWS EKS 셀 기반 인프라 설계](Docs/AWS_EKS_셀_기반_인프라_설계.md)
- [ERP 기술 스택](<../Docs/의사결정/ERP 기술 스택.md>)
- [개발 일정 WBS](<../Docs/의사결정/개발 일정 WBS.md>)
- [MSA 서비스 컨텍스트](../Docs/Specifications/MSA/README.md)

Dev 실행 진입점은 [Foundation Terraform](terraform/environments/dev/README.md), [Redis Terraform](terraform/environments/dev/redis/README.md), [MongoDB Atlas Terraform](terraform/environments/dev/mongodb-atlas/README.md) 순서로 사용한다.

## 목표 Runtime

```text
Vue POS·Kiosk
→ API Routing
   ├─ Store Access Service
   ├─ Commerce Service
   ├─ Payment Service
   ├─ Queue Service
   └─ Audit Service

Data
├─ PostgreSQL
│  ├─ store_access_db
│  ├─ commerce_db
│  ├─ payment_db
│  └─ queue_db
├─ MongoDB audit
├─ Redis Session
└─ SQS FIFO
   ├─ commerce-events + DLQ
   ├─ queue-events + DLQ
   └─ audit-events + DLQ
```

관계형 업무 Database는 PostgreSQL로 통일한다. 개발 환경에서는 하나의 Instance에 네 Database를 둘 수 있지만 서비스별 Runtime Role과 Migration Role을 분리한다. Store Access Session은 ElastiCache Redis, Audit 문서는 MongoDB Atlas를 사용하고 둘 다 Dev Alpha 전용으로 격리한다.

## Application 배포 단위

Backend는 하나의 Git 저장소에 있지만 다음 다섯 업무 App과 Stateless Edge Runtime, 총 여섯 개를 별도 JAR와 Container Image로 빌드하고 독립 배포한다. `platform/*`, `test-support`, `architecture-tests`는 배포 단위가 아니다.

| 서비스 | Gradle Project | 기본 Port | 기본 Image | Runtime 의존성 |
|---|---|---:|---|---|
| Edge | `:apps:edge-api` | 8080 | `doro-erp-edge` | 내부 HTTP Routing·HMAC, Database 없음 |
| Store Access | `:apps:store-access-api` | 8081 | `doro-erp-store-access` | PostgreSQL `store_access_db`, Redis, SQS |
| Commerce | `:apps:commerce-api` | 8082 | `doro-erp-commerce` | PostgreSQL `commerce_db`, SQS |
| Payment | `:apps:payment-api` | 8083 | `doro-erp-payment` | PostgreSQL `payment_db`, Toss Test API, SQS |
| Queue | `:apps:queue-api` | 8084 | `doro-erp-queue` | PostgreSQL `queue_db`, SQS |
| Audit | `:apps:audit-api` | 8085 | `doro-erp-audit` | MongoDB `audit`, SQS |

Image는 Service 저장소의 Spring Boot Buildpacks 설정으로 만든다. 배포에서는 Git SHA Tag가 가리키는 검증된 ECR Digest를 Manifest에 기록하고 `latest`만으로 Release를 식별하지 않는다.

```bash
cd ../Doro-ERP-Service
./gradlew bootJars
./gradlew :apps:edge-api:bootBuildImage --imageName=REGISTRY/doro-erp-edge:GIT_SHA
./gradlew :apps:store-access-api:bootBuildImage --imageName=REGISTRY/doro-erp-store-access:GIT_SHA
./gradlew :apps:commerce-api:bootBuildImage --imageName=REGISTRY/doro-erp-commerce:GIT_SHA
./gradlew :apps:payment-api:bootBuildImage --imageName=REGISTRY/doro-erp-payment:GIT_SHA
./gradlew :apps:queue-api:bootBuildImage --imageName=REGISTRY/doro-erp-queue:GIT_SHA
./gradlew :apps:audit-api:bootBuildImage --imageName=REGISTRY/doro-erp-audit:GIT_SHA
```

위 `REGISTRY`와 `GIT_SHA`는 로컬 명령을 위한 설명용 자리표시자다. 실제 게시에서는 Service 저장소의
`.github/workflows/publish-ecr.yml`이 ECR Registry와 전체 Git SHA Tag를 전달한다.

## 저장소 구조

```text
Doro-ERP-Infra/
├─ compose/
│  ├─ compose.yaml
│  └─ bootstrap/
├─ terraform/
│  └─ environments/dev/
│     ├─ redis/
│     └─ mongodb-atlas/
└─ deploy/
   ├─ base/                   # 여섯 Application 공통 Manifest
   ├─ components/             # Secrets Manager 등 선택 기능
   ├─ platform/               # Cluster 공통 Controller와 IngressClass
   └─ overlays/dev/alpha/     # Dev Alpha 조합
```

Foundation, Redis, MongoDB Atlas는 서로 다른 S3 State Key를 사용하므로 각각 독립적으로 Plan·Apply·Destroy한다.
Kubernetes Manifest의 현재 범위와 배포 전 필수 조건은 [deploy README](deploy/README.md)를 따른다.

## 환경별 책임

| 환경 | 목적 | 필수 구성 | 데이터 성격 |
|---|---|---|---|
| Local | 개발과 재현 가능한 통합 테스트 | PostgreSQL, MongoDB, Redis, LocalStack SQS | 폐기 가능한 개발 데이터 |
| CI | PR 검증과 장애·계약 테스트 | 격리된 임시 의존성, 여섯 App Health | Job 종료 시 폐기 |
| Dev | 팀 통합·시연 | 불변 Image, 실제 또는 승인된 SQS 환경, 환경별 Secret | Test Key·비운영 데이터만 사용 |
| Production 후보 | 향후 운영 | 관리형 제품, TLS, Backup, 관측, Rollback | RPO·RTO·비용 목표 결정 후 활성화 |

- Local과 CI는 고정 Version, Health Check와 재실행 가능한 Bootstrap을 사용한다.
- Dev와 운영 후보는 동일 Image를 사용하고 설정·Secret만 환경별로 분리한다.
- 목표 배포 플랫폼은 AWS EKS·Argo CD로 확정했다. Kustomize Base, Dev Alpha 조합,
  AWS Load Balancer Controller IAM·설치 값과 Public Ingress는 구현되어 있고 실제 Runtime 설정·GitOps는 후속 단계다.
- `.env`와 실제 Credential은 커밋하지 않는다. 예시 파일에는 이름과 형식만 둔다.

## Routing과 신뢰 경계

Frontend는 공개 Routing 계층을 통해 업무 API를 호출하고 Database, Redis, MongoDB와 SQS에 직접 연결하지 않는다. 목표 Routing은 Route 53→CloudFront·WAF→Cell별 내부 ALB→Edge Ingress이며 다음 논리 경계를 유지한다.

- 외부 TLS 종료와 API Route는 환경별로 한 진입점을 제공한다.
- POS와 Kiosk의 공개 API 범위는 Backend 인증·인가로 최종 제한한다.
- 서비스 간 동기 호출은 내부 주소와 서비스 자격증명을 사용하고 사용자 Session 전달을 신뢰 근거로 삼지 않는다.
- Database, Redis, MongoDB와 SQS Endpoint는 공개 Internet Inbound를 허용하지 않는다.
- Audit 조회는 `OWNER`, `MANAGER`용 POS 경로만 노출하고 Kiosk에는 노출하지 않는다.
- CORS, Cookie Domain, Secure·SameSite, CSRF Origin은 Front 배포 Origin과 함께 환경별 설정으로 관리한다.

## Database 권한 계약

| 주체 | 권한 |
|---|---|
| 서비스 Runtime Role | 자기 Database의 승인된 DML과 Sequence만 사용 |
| 서비스 Migration Role | 자기 Database의 Flyway DDL·DML만 사용 |
| Audit Runtime | MongoDB `audit`의 `audit_records` 읽기·쓰기 |
| Audit Index Bootstrap | 필요한 Unique·조회·TTL Index 관리 |

- 서비스는 다른 서비스 Database Credential을 받지 않는다.
- Database 전체 Superuser Credential을 Application Pod에 주입하지 않는다.
- PostgreSQL 연결은 운영에서 TLS와 Server Identity 검증을 사용한다.
- Credential 회전은 새 Secret 발급→배포 Rollout→새 Connection 확인→기존 Connection Drain→구 Credential 폐기 순서다.
- Backup·복구 뒤 외부 Traffic을 열기 전에 Flyway Version, MongoDB Index와 만료 정책을 확인한다.

서비스가 다른 서비스 Database를 직접 조회하거나 Cross-Database Foreign Key·Join을 만드는 것은 금지한다. 서비스 간 참조는 소유 API 또는 Versioned Event로만 해결한다.

## SQS 계약

| Queue | Consumer | 대표 Event |
|---|---|---|
| `commerce-events.fifo` | Commerce | `PaymentApproved`, `PaymentCancelled` |
| `queue-events.fifo` | Queue | `OrderAccepted`, `OrderCancelled` |
| `audit-events.fifo` | Audit | 모든 서비스 Audit Event |

각 Main Queue에는 FIFO DLQ와 Redrive Policy를 연결한다.

- Producer IAM은 필요한 목적지 Queue의 `SendMessage`만 허용한다.
- Consumer IAM은 자기 Queue의 Receive·Delete·Visibility 변경만 허용한다.
- Queue URL과 ARN은 환경 설정으로 주입하고 Access Key 원문을 저장소에 두지 않는다.
- Visibility Timeout, 최대 수신 횟수와 Message 보존 기간은 Application 처리 시간·재시도 정책과 함께 검증한다.
- 하나의 Queue에서 서로 다른 서비스 Consumer를 경쟁시키지 않는다.
- Queue 이름은 환경 Prefix 또는 Account 격리로 충돌을 막고 Application에는 URL·ARN을 설정으로 주입한다.
- SQS는 업무 상태 저장소가 아니다. POS·Kiosk 화면은 각 서비스 API가 Database에서 조회한 상태를 사용한다.
- `MessageGroupId`와 `MessageDeduplicationId`는 [비동기 Event 계약](../Docs/Specifications/비동기_Event_계약.md)의 Event별 공식을 따른다. Infra에서 임의로 다른 공식을 만들지 않는다.
- 전달은 최소 한 번을 전제로 하며 Commerce·Queue는 PostgreSQL Inbox, Audit은 MongoDB Unique Index로 중복 효과를 제거한다.

## Runtime Secret 주입

```text
환경별 Secret Store
→ 배포 플랫폼의 Workload Identity
→ 서비스별 Secret 참조
→ Application 환경 변수
```

- Store Access는 `store_access_db`, Redis, 자체 멱등성 HMAC Key와 필요한 SQS 설정만 받는다.
- Commerce는 `commerce_db`, 자체 멱등성 HMAC Key, `commerce-events` 소비와 `queue-events`·`audit-events` 발행 설정만 받는다.
- Payment는 `payment_db`, 자체 멱등성 HMAC Key, Toss Test Secret과 `commerce-events`·`audit-events` 발행 설정만 받는다.
- Queue는 `queue_db`, 자체 멱등성 HMAC Key, `queue-events` 소비와 `audit-events` 발행 설정만 받는다.
- Audit는 MongoDB와 `audit-events` 소비 설정만 받는다.
- Secret 원문·Digest를 Terraform Output, Plan, CI Log, Container Image와 Application Metric에 출력하지 않는다.

EKS Workload의 AWS 자원 권한은 Pod Identity로 분리한다. Dev Alpha는 AWS 공식 `aws-secrets-store-csi-driver-provider` EKS Add-on과 Secrets Store CSI Driver를 사용한다. 서비스별 Secret과 방향별 HMAC Secret을 `SecretProviderClass`로 선택해 Kubernetes Secret에 동기화하고, Deployment는 `envFrom`으로 주입한다. 실행 중인 JVM 환경변수는 자동 갱신되지 않으므로 Secret 회전 뒤 대상 Deployment를 Rollout한다.

## Idempotency Key Material 회전

Store Access·Commerce·Payment·Queue는 자신이 처리하는 멱등 요청의 Request HMAC Key를 각각 소유한다. 하나의 전역 Key를 모든 서비스가 공유하지 않는다.

1. 대상 서비스의 멱등 쓰기 Endpoint 신규 요청을 제한된 유지보수 Gate로 차단한다.
2. 진행 중 요청을 Drain하고 구 Instance Writer가 없는지 확인한다.
3. 활성·직전 Key Version Pair를 Secret Store에 갱신한다.
4. 대상 서비스 Instance를 모두 Rollout한다.
5. 모든 Ready Instance가 같은 활성 Version을 사용함을 확인한다.
6. Gate를 해제하고 신규 요청과 기존 성공 결과 재생을 검증한다.
7. 최대 멱등 Record 보존 시간보다 길게 직전 Key를 유지한 뒤 폐기한다.

Key 원문과 Request HMAC은 Log·Metric·상태 Endpoint에 노출하지 않는다. Key Version을 저장한 기존 멱등 Record를 재생할 수 있도록 활성·직전 Key의 호환 기간을 해당 Record 보존 기간보다 짧게 두지 않는다. Gate는 EKS의 신규 쓰기 요청 차단·Drain·Rollout을 자동화할 때 구체화한다.

## Audit Retention Infra

- 중앙 Audit 보존 기간은 설정으로 관리하고 초기값은 90일이다.
- Document 생성 시 `expiresAt`을 확정하며 정책 변경을 기존 Document에 암묵적으로 소급하지 않는다.
- Audit MongoDB Document의 `expiresAt`에 TTL Index를 생성한다.
- TTL 삭제가 즉시 실행된다고 가정하지 않고 Application Query도 만료 문서를 제외한다.
- MongoDB Backup·Snapshot의 보존은 Live TTL과 별도 정책으로 관리한다.
- Audit Consumer Lag, DLQ와 가장 오래된 미처리 Event를 관찰한다.
- Domain History와 결제·주문 정본은 각 PostgreSQL Database의 별도 보존 정책을 따른다.

Legal Hold, S3 Object Lock, HMAC Chain, 삭제 승인 전용 Workload와 장기 불변 증적은 MVP Infra 범위가 아니다.

감사 데이터의 만료·권한·복구·MVP 이후 외부 증적은 다음 통합 문서에서 관리한다.

- [감사 데이터 보존 및 보안 설계](Docs/감사_데이터_보존_및_보안_설계.md)

## 로컬 통합 환경 완료 조건

- PostgreSQL·MongoDB·Redis·LocalStack이 고정 Version과 Health Check로 기동한다.
- 네 PostgreSQL Database와 서비스별 Runtime·Migration Role이 Bootstrap된다.
- MongoDB Unique·조회·TTL Index가 재실행 가능한 방식으로 구성된다.
- 세 FIFO Main Queue와 FIFO DLQ·Redrive Policy가 생성된다.
- 각 Application이 자기 Database에 연결하고 다른 Database 접근은 실패한다.
- Application 중단·SQS 중복·MongoDB 중단 뒤 Outbox·Inbox·DLQ 복구가 검증된다.
- 실제 Secret과 운영 인증정보가 저장소에 포함되지 않는다.

구현 후 README에는 최소한 기동, 종료, 초기화, Health 확인, Queue 확인과 전체 통합 테스트 명령을 정확히 기록한다. 데이터 초기화 명령은 명시적인 대상 확인 없이 기본 흐름에 포함하지 않는다.

## 관측성과 운영 신호

여섯 App은 구조화 JSON Log, Health Probe와 Metric을 각각 제공한다. Infra는 수집 Backend 제품보다 먼저 다음 신호 이름과 경보 의도를 맞춘다.

| 영역 | 최소 신호 |
|---|---|
| Application | 요청 수·오류율·지연, Instance Ready 상태, JVM·Connection Pool |
| Outbox | `PENDING`·`FAILED` 수, 가장 오래된 미발행 Record, 발행 재시도 |
| SQS | Main Queue 지연·가시 Message, DLQ Message와 가장 오래된 Message |
| Consumer | 성공·실패·중복 수, 처리 지연, 마지막 성공 시각 |
| PostgreSQL | 연결·용량·Slow Query, Flyway Version, Backup 성공 |
| MongoDB | 연결·용량·Query 지연, 필수 Index, TTL 상태, Backup 성공 |
| Redis | 연결·메모리·Eviction, Session 장애 |
| Payment | Toss 호출 지연·실패, `REVIEW_REQUIRED` 수 |

Log에는 `traceId`, 서비스명, 안전하게 확인된 Tenant·Actor 유형과 결과 Code만 구조화한다. Header·Cookie·Body 전체, 비밀번호, Token, Kiosk Secret, Toss Secret·전체 Payment Key와 원문 `Idempotency-Key`는 수집하지 않는다.

## CI/CD 기준

Infra 구현 시 Pipeline은 다음 순서와 책임을 갖는다.

1. PR에서 Markdown Link, Compose·Terraform·Manifest 정적 검증과 Secret 검사를 수행한다.
2. 관련 저장소의 Required Check로 Service Root `./gradlew check`와 Front의 Lint·Unit·Build를 통과시킨다.
3. 여섯 App Image를 같은 Git SHA Tag로 개별 생성하고 취약점·구성 검사를 수행한다.
4. Dev에서는 ECR Tag와 Digest의 일치를 확인하고 대상 서비스 Digest만 Infra Manifest에 기록한 뒤 환경 승인과 배포 Diff를 검토한다.
5. Database Migration은 서비스별 Migration Credential을 쓰는 제한된 단계에서 실행한다.
6. 새 Version을 Rollout하고 Health·Smoke·핵심 Event 수렴을 확인한다.
7. 실패하면 Git에 기록한 이전 Image Digest로 Application을 되돌리되, 이미 적용된 Database Migration은 Forward-fix 원칙을 따른다.

현재 Dev CD는 자동화하지 않는다. 운영자가 승인한 Digest를 `deploy/scripts/record-dev-alpha-image.sh`로 기록하고 수동 Apply한다. Argo CD는 이 절차와 관측 신호를 Dev에서 검증한 뒤 같은 Git 목표 상태를 읽는 방식으로 도입한다.

Application 코드 변경이 없는 서비스는 다시 배포하지 않을 수 있지만, 공통 계약·Platform 또는 Infra 설정 변경의 영향 서비스는 명시적으로 선택한다.

## 구현 순서

[개발 일정 WBS](<../Docs/의사결정/개발 일정 WBS.md>)와 다음 순서를 맞춘다.

1. Sprint 0: PostgreSQL 4 DB·MongoDB·Redis·LocalStack, 역할·Queue Bootstrap과 Health 기준
2. Sprint 1: Store Access Database·Redis·Secret·Session·보안 Origin
3. Sprint 2: Commerce Database와 Front–API Routing
4. Sprint 3: Payment·Queue Database, 세 FIFO Queue·DLQ·IAM과 장애 재현
5. Sprint 4: Audit MongoDB Index·Retention, 관측·백업/복구·Release 검증

각 Sprint에서 Application과 Infra를 함께 검증하며 모든 Backend 구현이 끝난 뒤 Infra를 한 번에 붙이는 방식으로 미루지 않는다.

## AWS 구현 전 결정 사항

AWS, `ap-northeast-2`, EKS·Argo CD GitOps, Cell별 CloudFront·ALB와 Edge 단일 Ingress는 목표 방향으로 확정했다. 실제 자원을 만들기 전에는 다음 운영 수치와 제품 선택을 확정한다.

- RDS PostgreSQL의 Instance Class·Multi-AZ·Cell별 분리 수준
- MongoDB Atlas 운영 Tier·PrivateLink·백업 보존·복구 목표
- ElastiCache Redis Multi-AZ·Failover와 Session 가용성 목표
- EKS Node Group Size·Replica·HPA와 운영 후보 NetworkPolicy 검증 방식
- 운영 후보 환경의 Secret Rotation 자동 Rollout 방식
- CloudWatch 중심 관측 범위와 비용 한도
- RPO·RTO, Backup 보존, Release·Rollback 전략

이 선택이 완료되기 전에는 AWS 목표 구조를 실제 운영 완료 상태로 표현하지 않는다.

## Infra 변경 완료 기준

- 선언 파일과 실제 생성 자원의 이름·Port·Database·Queue 계약이 일치한다.
- 새 개발자가 README 명령만으로 대상 환경을 기동하고 Health를 확인할 수 있다.
- 여섯 App이 독립 Image와 Credential로 실행되고 다른 서비스 저장소 접근은 실패한다.
- 깨끗한 환경 Bootstrap과 반복 적용이 성공하며 필요한 Migration·Index가 검증된다.
- SQS 중복·지연·DLQ, PostgreSQL·MongoDB·Redis 중단과 재기동 뒤 상태 복구를 재현한다.
- Secret·Token·개인정보가 Git, Image, Terraform State·Plan, Manifest, Log와 Metric에 없다.
- 변경된 구성의 Rollback 또는 Forward-fix 절차와 남은 운영 위험이 문서화된다.
