# Kubernetes 배포 Manifest

이 디렉터리는 Doro ERP의 여섯 Spring Boot Application을 EKS에 배포하기 위한 Kustomize Manifest를 소유한다.

## 구조

```text
deploy/
├─ base/
│  ├─ edge-api/
│  ├─ store-access-api/
│  ├─ commerce-api/
│  ├─ payment-api/
│  ├─ queue-api/
│  └─ audit-api/
├─ components/
│  └─ secrets-manager/
├─ platform/
│  └─ aws-load-balancer-controller/
└─ overlays/
   └─ dev/alpha/
```

각 Base는 다음 Resource를 소유한다.

- `ServiceAccount`: Terraform의 EKS Pod Identity Association과 같은 이름을 사용한다.
- `Deployment`: 독립 Image, Health Probe, Resource 요청·제한과 기본 보안 Context를 정의한다.
- `Service`: Application Port를 노출하는 ClusterIP만 정의한다.
- `Ingress`: 브라우저에 공개할 API Prefix만 소유한다.
- `ConfigMap`: Port, Region과 안전한 기본 Feature Flag를 환경 변수로 제공한다.

Dev Alpha Overlay는 여섯 Base를 `doro-alpha` Namespace에 배치하고
[`secrets-manager`](components/secrets-manager/README.md) Component를 결합한다.

## 현재 적용 가능 범위

Manifest 구조와 Secrets Manager 연결은 구현되어 있지만, EKS에 적용할 Release 값은 아직 완성되지 않았다.

- Image Tag는 의도적으로 `unconfigured`다. ECR에 Push된 Git SHA 또는 Digest로 교체해야 한다.
- RDS PostgreSQL URL, Redis Endpoint, MongoDB 연결과 SQS Queue URL을 환경 Overlay에 추가해야 한다.
- `prod` Profile의 서비스 간 호출은 HTTPS를 요구한다. 내부 TLS 인증서와 JVM TrustStore 주입을 먼저 구현해야 한다.
- NetworkPolicy, PodDisruptionBudget, HPA와 Argo CD Application은 아직 포함하지 않는다.
- PostgreSQL Flyway Migration Credential과 Runtime Credential을 분리하는 배포 절차가 필요하다.

이 조건을 채우기 전에 Application Overlay를 `kubectl apply`하거나 Argo CD Sync하지 않는다.
Controller IAM·Helm과 IngressClass는 Application Release보다 먼저 준비할 수 있다.

## 기본 동작

Base의 비동기 Consumer와 Outbox는 실제 Queue URL이 준비되기 전까지 Fail-Closed 상태로 비활성화한다.

| Application | 기본 Port | 기본 비활성화 항목 |
|---|---:|---|
| Edge | 8080 | 해당 없음 |
| Store Access | 8081 | Audit Outbox |
| Commerce | 8082 | Payment Event Consumer, Queue·Audit Outbox, Payment Eligibility Provider |
| Payment | 8083 | Commerce Eligibility, Outbox |
| Queue | 8084 | Order Event Consumer, Audit Outbox, Internal Fulfillment |
| Audit | 8085 | SQS Listener, DLQ Monitoring |

실제 AWS Resource와 IAM 권한을 확인한 뒤 Overlay에서 필요한 기능만 활성화한다.

## ALB와 공개 Route

AWS Load Balancer Controller는 AWS 공식 Helm Chart `3.5.0`으로 설치하며 Controller
`v3.5.0` IAM Policy와 Pod Identity는 Terraform이 관리한다. 설치와 검증 순서는
[`platform/aws-load-balancer-controller`](platform/aws-load-balancer-controller/README.md)를 따른다.

Base의 `doro-cell-alb`는 재사용용 논리 이름이며 Dev Alpha Overlay가 이를
`doro-alpha-alb`로 교체한다. `IngressClassParams`가 내부 ALB, `doro-alpha`
IngressGroup, 두 Private Application Subnet과 IP Target을 중앙에서 강제한다.

| Ingress 소유 서비스 | 공개 Prefix | 실제 Provider |
|---|---|---|
| Edge | `/api/v1/payments`, `/api/v1/audits` | Edge가 Session 검증 후 Payment·Audit에 내부 HMAC 전달 |
| Store Access | `/api/v1/auth`, `/api/v1/kiosk-auth`, `/api/v1/kiosk-devices`, `/api/v1/security-history`, `/api/v1/store`, `/api/v1/employees`, `/api/v1/tables` | Store Access |
| Commerce | `/api/v1/catalog`, `/api/v1/orders`, `/api/v1/sales` | Commerce |
| Queue | `/api/v1/queues` | Queue |

Payment와 Audit은 직접적인 Public Ingress를 갖지 않는다. Payment 공개 계약은 Edge가
세션을 확인하고 서명해서 전달하며 Audit은 `/internal/v1/audits`만 제공한다. 두 서비스를
직접 ALB에 연결하면 Payment의 Edge 인증 경계를 우회하거나 Audit Route가 동작하지 않는다.
`/internal/**`와 `/actuator/**`도 Ingress에 등록하지 않는다.

## 렌더링 검증

Cluster 접속 없이 다음 명령으로 Base와 Dev Alpha Overlay가 정상 조합되는지 확인한다.

```bash
kubectl kustomize deploy/base
kubectl kustomize deploy/overlays/dev/alpha
```

Dev Alpha 결과에는 다음이 포함되어야 한다.

- Namespace 1개
- ServiceAccount, ConfigMap, Service, Deployment 각각 6개
- 공개 Ingress 4개
- SecretProviderClass 6개
- 각 Deployment의 ConfigMap `envFrom`과 서비스별 Runtime Secret `envFrom`
- 각 Deployment의 Secrets Store CSI Volume

Secret 원문은 렌더링 결과나 Git에 포함되지 않아야 한다.

## Release 값 반영

이미지는 Overlay의 `images` 항목에서 변경한다.

```yaml
images:
  - name: doro-erp-payment
    newName: 727646470302.dkr.ecr.ap-northeast-2.amazonaws.com/doro-erp-payment
    newTag: GIT_SHA
```

`GIT_SHA`는 설명용 자리표시자다. 배포에서는 ECR에 존재하는 불변 Tag나 Digest만 사용한다.

일반 설정은 ConfigMap Patch로, Credential과 HMAC Key는 AWS Secrets Manager로 전달한다. 실제 Secret 값과 값이 채워진 환경 파일은 커밋하지 않는다.
