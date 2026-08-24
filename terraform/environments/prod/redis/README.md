# Prod Alpha Redis Terraform

Store Access의 Spring Session과 로그인 Rate Limit을 위한 단일 ElastiCache for Redis OSS 7.1 Stack이다. Terraform 관리형 Prod VPC의 Data Subnet 두 개를 Network Remote State에서 읽으며 EKS와 SSM 관리 EC2에서만 TLS `6379` 접근을 허용한다.

## 사전 작업: 비밀번호 사용자 생성

ElastiCache User의 비밀번호를 Terraform으로 만들면 평문이 Terraform State에 저장된다. 따라서 **User 한 개만 AWS Console에서 생성**하고 User Group과 Redis는 Terraform으로 관리한다.

AWS Console에서 `ElastiCache → User management → Create user`로 이동해 다음과 같이 입력한다.

- User ID: `doro-erp-prod-alpha-default`
- User name: `default`
- Engine: `Redis`
- Authentication: Password
- Access string: `on ~* &* +@all`
- Tags: `Team=team2`, `Project=Doro-ERP`, `Environment=prod`, `Cell=alpha`, `ManagedBy=console-secret-bootstrap`

강한 비밀번호를 생성해 `doro-erp/prod/alpha/store-access` Secret의 `STORE_ACCESS_REDIS_USERNAME=default`, `STORE_ACCESS_REDIS_PASSWORD=<비밀번호>`에 저장한다. 비밀번호를 `terraform.tfvars`, Shell History, Git에 기록하지 않는다.

## 실행

Network와 Foundation Stack이 먼저 적용되어 `doro-erp-prod` EKS와 `doro-erp-prod-management` Security Group이 존재해야 한다.

```bash
cd ~/Doro-ERP-Infra/terraform/environments/prod/redis
mkdir -p ~/.terraform.d/plugin-cache
export TF_PLUGIN_CACHE_DIR="$HOME/.terraform.d/plugin-cache"
cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars
terraform init -backend-config=backend.hcl
terraform fmt -check -recursive
terraform validate
terraform plan -out=redis.tfplan
terraform show -no-color redis.tfplan
terraform apply redis.tfplan
```

Provider Cache는 Foundation·Redis·Atlas Stack이 큰 AWS Provider Binary를 각각 중복 저장해 CloudShell 용량이 부족해지는 것을 막는다. CloudShell을 다시 열면 `TF_PLUGIN_CACHE_DIR`만 다시 설정한다.

Apply 후 Secret에 비밀이 아닌 연결 설정을 반영한다.

```bash
terraform output store_access_secret_values
```

Secret에는 다음 값이 최종적으로 있어야 한다.

- `STORE_ACCESS_REDIS_HOST`: `redis_primary_endpoint` Output
- `STORE_ACCESS_REDIS_PORT`: `6379`
- `STORE_ACCESS_REDIS_USERNAME`: `default`
- `STORE_ACCESS_REDIS_PASSWORD`: Console에서 만든 비밀번호
- `STORE_ACCESS_REDIS_SSL_ENABLED`: `true`

이 Stack은 Spring Session Indexed Repository에 필요한 `notify-keyspace-events=Egx`와 세션 장애 시 조용한 Eviction을 막기 위한 `maxmemory-policy=noeviction`을 설정한다.

## 확인

```bash
terraform output
aws elasticache describe-replication-groups \
  --replication-group-id doro-erp-prod-alpha-session \
  --region ap-northeast-2 \
  --query 'ReplicationGroups[0].[Status,TransitEncryptionEnabled,AtRestEncryptionEnabled,UserGroupIds]' \
  --output table
```

SSM 관리 EC2에서 Redis CLI를 사용할 때 반드시 TLS 옵션을 사용한다.

```bash
redis-cli --tls -h REDIS_PRIMARY_ENDPOINT -p 6379 --user default --askpass PING
```

정상 응답은 `PONG`이다.

## 삭제

Store Access Pod를 먼저 중지하거나 Redis 연결을 제거한 뒤 실행한다.

```bash
terraform plan -destroy -out=redis-destroy.tfplan
terraform show -no-color redis-destroy.tfplan
terraform apply redis-destroy.tfplan
```

Console에서 만든 ElastiCache User와 Secrets Manager의 값은 이 State가 소유하지 않으므로 자동 삭제되지 않는다. 다른 자원에서 사용하지 않는 것을 확인한 후 별도로 정리한다.
