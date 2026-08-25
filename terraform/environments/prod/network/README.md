# Prod Terraform-managed Network

Doro ERP Prod Alpha가 사용하는 VPC 전체를 별도 Terraform State로 관리한다. 기존
`team2-DoroLoad` VPC의 고정 ID를 재사용하지 않는다. 새 Prod S3 Backend Bucket은 Bootstrap
State가 소유하며 Network Stack에서는 조회만 한다.

## 구성

```text
VPC 10.24.0.0/16
├─ Internet Gateway 1개
├─ Public Subnet 2개 (AZ-a, AZ-c)
│  └─ AZ-a NAT Gateway 1개 + Elastic IP 1개
├─ Private App Subnet 2개 (AZ-a, AZ-c)
│  ├─ EKS Control Plane ENI와 Worker
│  ├─ Gateway API Internal ALB
│  └─ SSM 관리 EC2
└─ Private Data Subnet 2개 (AZ-a, AZ-c)
   ├─ RDS PostgreSQL
   └─ ElastiCache Redis
```

Prod 비용을 줄이기 위해 NAT Gateway와 Interface VPC Endpoint ENI는 AZ-a에 하나씩 둔다.
AZ-c Workload도 VPC 내부 경로로 이를 사용한다. 이 구성은 AZ-a 장애 시 외부 통신과 AWS
Private API 통신이 중단될 수 있으므로 Production 구성으로 사용하지 않는다.

Interface Endpoint는 `ssm`, `ssmmessages`, `ec2messages`, ECR API/DKR, Logs,
Secrets Manager, SQS와 STS를 만든다. 관리 EC2는 Public IP와 Inbound Security Group Rule
없이 SSM으로만 접속한다.

모든 Taggable Resource에는 다음 공통 Tag가 적용된다.

```text
Team=team2
Project=Doro-ERP
Environment=prod
Cell=alpha
ManagedBy=terraform
```

## Remote State

```text
Bucket: doro-erp-prod-tfstate-727646470302-ap-northeast-2
Key: environments/prod/network/terraform.tfstate
```

Foundation, Redis와 MongoDB Atlas Stack은 이 State의 Output을 읽는다. 따라서 Network를
가장 먼저 Apply하고 가장 마지막에 Destroy해야 한다.

## 새 Network 적용

```bash
cd ~/Doro-ERP-Infra/terraform/environments/prod/network

cp terraform.tfvars.example terraform.tfvars

terraform init -reconfigure -backend-config=backend.hcl
terraform fmt -check -recursive
terraform validate
terraform plan -out=/tmp/doro-prod-network.tfplan
terraform show -no-color /tmp/doro-prod-network.tfplan
```

Plan에서 다음을 확인한다.

- VPC는 1개다.
- Internet Gateway는 1개다.
- NAT Gateway와 NAT EIP는 각각 1개다.
- Public·App·Data Subnet은 각각 2개다.
- 기존 S3 Bucket이나 다른 State의 자원 삭제가 없다.
- 모든 Taggable Resource에 `Team=team2`가 있다.
- VPC 생성 시 자동 생성되는 Default Security Group·Route Table·Network ACL에도 `Team=team2`가 있다.
- Default Security Group에는 Inbound와 Outbound Rule이 모두 없다.

검토한 저장 Plan만 적용한다.

```bash
terraform apply /tmp/doro-prod-network.tfplan
terraform output
```

## 확인

```bash
terraform output vpc_id
terraform output internet_gateway_id
terraform output nat_public_ip
terraform output subnet_ids

aws ec2 describe-internet-gateways \
  --filters Name=attachment.vpc-id,Values="$(terraform output -raw vpc_id)" \
  --region ap-northeast-2 \
  --query 'InternetGateways[].InternetGatewayId' \
  --output table

aws ec2 describe-vpc-endpoints \
  --filters Name=vpc-id,Values="$(terraform output -raw vpc_id)" \
  --region ap-northeast-2 \
  --query 'VpcEndpoints[].{Service:ServiceName,State:State,Type:VpcEndpointType}' \
  --output table
```

## 기존 환경 전체 삭제 후 전환

기존 VPC는 이 State가 소유하지 않으므로 새 Network Terraform이 삭제하지 않는다. 기존
환경은 기존 Terraform Revision과 기존 State를 이용해 모두 Destroy하고, VPC에 남은
ALB·ENI·Endpoint·NAT가 없는지 확인한 후 기존 VPC를 별도로 삭제한다.

중요한 전환 원칙은 다음과 같다.

1. 기존 Kubernetes Gateway·Application과 AWS Load Balancer를 정리한다.
2. 기존 Atlas·Redis·Foundation Stack을 기존 Revision에서 Destroy한다.
3. 기존 Frontend S3의 객체와 Version을 포함해 프로젝트 S3를 정리한다.
4. 기존 VPC의 잔존 ENI와 연결 자원을 확인한 후 기존 VPC를 삭제한다.
5. 기존 Bootstrap State를 Local로 안전하게 이전한 후 기존 State Bucket과 IAM을 정리한다.
6. 새 Prod Bootstrap을 Local State로 적용해 Prod State Bucket과 실행 Role을 만든다.
7. 이 Network Stack, Foundation, Redis, Atlas 순서로 Apply한다.
8. Gateway API와 Application을 배포한다.

삭제 범위는 Doro ERP 기존 환경이 소유한 자원이다. Terraform 실행에 필요한 개인 IAM User,
`minseok.click` Domain 등록과 계정 공용 GitHub OIDC Provider는 외부 선행조건이다. 팀 운영자
Group과 Route 53 Hosted Zone은 새 Bootstrap State가 생성·관리하므로 Network 전환 중 삭제하지 않는다.

새 Network State가 아직 없을 때 Foundation·Redis·Atlas의 새 Revision을 Plan하면 Remote
State를 읽을 수 없어 실패한다. 반드시 Network Apply를 먼저 완료한다.

## 삭제

Network는 가장 마지막에 삭제한다. 먼저 Kubernetes Gateway와 ALB, Atlas, Redis,
Foundation 등 VPC 의존 자원을 제거한다. Prod State Bucket은 Bootstrap State가 소유하므로
Network Destroy에는 포함되지 않는다.

```bash
terraform plan -destroy -out=/tmp/doro-prod-network-destroy.tfplan
terraform show -no-color /tmp/doro-prod-network-destroy.tfplan
terraform apply /tmp/doro-prod-network-destroy.tfplan
```

Network Destroy Plan에 이 State가 소유하지 않는 S3, Route 53 또는 Atlas 자원이 나타나면
적용하지 않는다.
