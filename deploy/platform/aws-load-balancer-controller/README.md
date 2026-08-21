# AWS Load Balancer Controller

Dev EKS에는 AWS Load Balancer Controller `v3.5.0`을 Helm Chart `3.5.0`으로 설치한다.
Controller IAM Policy와 Pod Identity Association은 Terraform이 관리하고, Helm은
`kube-system/aws-load-balancer-controller` ServiceAccount와 Controller Runtime을 관리한다.
IAM Policy는 Controller `v3.5.0`의 공식
[`iam_policy.json`](https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v3.5.0/docs/install/iam_policy.json)을
원문 그대로 고정한다.

## 적용 순서

Foundation Terraform을 먼저 적용해 Controller IAM Role과 Pod Identity Association을 만든다.

```bash
cd terraform/environments/dev
terraform init -backend-config=backend.hcl
terraform plan -out=dev.tfplan
terraform apply dev.tfplan
aws eks update-kubeconfig --region ap-northeast-2 --name doro-erp-dev
```

AWS 공식 EKS Chart를 고정 Version으로 설치하거나 갱신한다.

```bash
helm repo add eks https://aws.github.io/eks-charts
helm repo update eks
helm show crds eks/aws-load-balancer-controller --version 3.5.0 \
  | kubectl apply -f -
helm upgrade --install aws-load-balancer-controller \
  eks/aws-load-balancer-controller \
  --namespace kube-system \
  --version 3.5.0 \
  --values deploy/platform/aws-load-balancer-controller/values.yaml \
  --wait \
  --timeout 5m
```

Helm이 CRD를 설치한 다음 Dev Alpha 전용 IngressClass를 적용한다.

```bash
kubectl apply -f deploy/platform/aws-load-balancer-controller/dev-alpha-ingress-class.yaml
kubectl get deployment -n kube-system aws-load-balancer-controller
kubectl get ingressclass doro-alpha-alb
```

`doro-alpha-alb`는 다음 값을 중앙에서 강제한다.

- `doro-alpha` IngressGroup과 내부 ALB 1개
- Private Application Subnet 2개
- Pod IP Target
- `doro-alpha` Namespace Label Selector
- Dev Alpha 공통 AWS Tag

Controller의 Shield·WAF·WAFv2 자동 연결은 끈다. Dev의 WAF는 CloudFront Terraform이
소유하며 Edge Ingress 외의 Module Manifest가 공통 보안 자원을 변경하지 않는다.

Ingress를 먼저 삭제한 후 IngressClass와 Controller를 삭제한다. 반대 순서로 삭제하면
Controller가 ALB를 정리하지 못해 AWS Resource가 남을 수 있다.
