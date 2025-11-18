#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_step() { echo -e "${BLUE}[Step $1/$2]${NC} $3"; }
print_success() { echo -e "${GREEN}✅ $1${NC}"; }
print_error() { echo -e "${RED}❌ $1${NC}"; }
print_wait() { echo -e "${YELLOW}⏳ $1${NC}"; }

wait_for_pods() {
    local namespace=$1
    local timeout=${2:-300}
    print_wait "Namespace '$namespace'의 Pod 준비 대기 중..."
    if kubectl wait --for=condition=Ready pods --all -n $namespace --timeout=${timeout}s 2>/dev/null; then
        print_success "Namespace '$namespace' 준비 완료"
        return 0
    else
        kubectl get pods -n $namespace
        return 1
    fi
}

echo "╔═══════════════════════════════════════════╗"
echo "║  Kubernetes 3-Tier 프로젝트 자동 배포     ║"
echo "╚═══════════════════════════════════════════╝"
echo ""

# 사전 확인
print_step 1 9 "사전 확인..."
command -v kubectl &> /dev/null || { print_error "kubectl 없음"; exit 1; }
command -v helm &> /dev/null || { print_error "Helm 없음"; exit 1; }
kubectl cluster-info &> /dev/null || { print_error "클러스터 연결 실패"; exit 1; }
print_success "사전 확인 완료"

# 노드 준비
print_step 2 9 "노드 준비..."
chmod +x 01-prepare.sh
./01-prepare.sh
echo ""
read -p "SSD 노드 이름: " SSD_NODE
read -p "HDD 노드 이름: " HDD_NODE
read -p "NFS 서버 IP [172.16.101.10]: " NFS_SERVER
NFS_SERVER=${NFS_SERVER:-172.16.101.10}

# MetalLB 실행
print_step 3 9 "MetalLB 실행..."
kubectl apply -f metallb-native.yaml
kubectl wait --for=condition=ready pod -n metallb-system --all --timeout=180s
cat <<EOF | kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: first-pool
  namespace: metallb-system
spec:
  addresses:
  - 172.16.101.200-172.16.101.240
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: example
  namespace: metallb-system
EOF
print_success "MetalLB 설치 완료"

# Nginx Ingress Controller 설치
print_step 4 9 "Nginx Ingress Controller 설치..."
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.10.0/deploy/static/provider/cloud/deploy.yaml
sleep 15
kubectl wait --for=condition=ready pod -n ingress-nginx -l app.kubernetes.io/component=controller --timeout=300s
print_success "Ingress Controller 설치 완료"

# 인프라
print_step 5 9 "인프라 배포..."
kubectl apply -f 02-infrastructure.yaml
sleep 5
print_success "인프라 완료"

# 모니터링
print_step 6 9 "모니터링 설치..."
chmod +x 05-monitoring.sh
./05-monitoring.sh
wait_for_pods "monitoring" 600 || { print_error "모니터링 실패"; exit 1; }

# NFS 확인
print_step 7 9 "NFS 디렉토리 확인..."
echo "   NFS 서버($NFS_SERVER)에서:"
echo "   mkdir -p /shared/{ssd,hdd} && chmod 777 -R /shared"
read -p "   완료했으면 Enter..."

# 3-Tier 배포
print_step 8 9 "3-Tier 배포..."
sed "s/SERVER_IP/$NFS_SERVER/g" 03-ssd-tier.yaml | kubectl apply -f -
sed "s/SERVER_IP/$NFS_SERVER/g" 04-hdd-tier.yaml | kubectl apply -f -
sleep 60
wait_for_pods "ssd-tier" 300 || true
wait_for_pods "hdd-tier" 300 || true

# Ingress 및 Taint
print_step 9 9 "Ingress 및 Taint 설정..."
kubectl apply -f unified-ingress.yaml
kubectl taint nodes $SSD_NODE storage=ssd:NoSchedule --overwrite 2>/dev/null || true
kubectl taint nodes $HDD_NODE storage=hdd:NoSchedule --overwrite 2>/dev/null || true
print_success "설정 완료"

echo ""
echo "╔═══════════════════════════════════════════╗"
echo "║           배포 완료!                       ║"
echo "╚═══════════════════════════════════════════╝"
echo ""

# Ingress IP 대기
print_wait "Ingress External IP 할당 대기 중..."
for i in {1..30}; do
    INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
    if [ ! -z "$INGRESS_IP" ]; then
        break
    fi
    sleep 2
done

kubectl get pods -n ssd-tier -o wide
echo ""
kubectl get pods -n hdd-tier -o wide
echo ""
kubectl get ingress -A
echo ""

NODE_IP=$(kubectl get nodes -o wide | awk 'NR==2 {print $6}')
echo "📊 Grafana: http://$NODE_IP:30000 (admin/admin123)"
echo "🌐 Ingress External IP: $INGRESS_IP"
echo "🌐 SSD: http://ilove.k8s.com/ssd"
echo "🌐 HDD: http://ilove.k8s.com/hdd"
echo ""
echo "다음 단계:"
if [ ! -z "$INGRESS_IP" ]; then
    echo "  echo '$INGRESS_IP ilove.k8s.com' | sudo tee -a /etc/hosts"
else
    echo "  kubectl get svc -n ingress-nginx  # External IP 확인"
    echo "  echo '<EXTERNAL_IP> ilove.k8s.com' | sudo tee -a /etc/hosts"
fi
echo "  kubectl apply -f 07-hpa.yaml  # HPA 활성화"
echo "  ./test.sh                     # 부하 테스트"
