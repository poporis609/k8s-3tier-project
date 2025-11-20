#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() { echo -e "${BLUE}$1${NC}"; }
print_success() { echo -e "${GREEN}✅ $1${NC}"; }
print_info() { echo -e "${YELLOW}ℹ️  $1${NC}"; }

echo "╔═══════════════════════════════════════════╗"
echo "║     부하 테스트 (HPA 포함)                ║"
echo "╚═══════════════════════════════════════════╝"
echo ""

NODE_IP=$(kubectl get nodes -o wide | awk 'NR==2 {print $6}')
INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)

echo "📊 Grafana: http://$NODE_IP:30000 (admin/admin123)"
echo "🌐 Ingress IP: $INGRESS_IP"
echo "🌐 SSD Tier: http://ilove.k8s.com/ssd"
echo "🌐 HDD Tier: http://ilove.k8s.com/hdd"
echo ""

# HPA 확인
print_header "=== 현재 HPA 상태 ==="
kubectl get hpa -n ssd-tier 2>/dev/null || print_info "SSD HPA 없음 (kubectl apply -f 07-hpa.yaml 실행 필요)"
kubectl get hpa -n hdd-tier 2>/dev/null || print_info "HDD HPA 없음 (kubectl apply -f 07-hpa.yaml 실행 필요)"
echo ""

read -p "HPA를 활성화하시겠습니까? (y/n): " enable_hpa
if [[ $enable_hpa == "y" ]]; then
    print_info "HPA 활성화 중..."
    kubectl apply -f 06-hpa.yaml
    sleep 10
    print_success "HPA 활성화 완료"
fi
echo ""

# 테스트 옵션 선택
echo "테스트 옵션을 선택하세요:"
echo "  1) SSD Tier 부하 테스트 (CPU 25% 목표)"
echo "  2) HDD Tier 부하 테스트 (CPU 50% 목표)"
echo "  3) 둘 다 동시 테스트"
echo "  4) 웹 접속 테스트 (curl)"
read -p "선택 (1-4): " choice

case $choice in
    1)
        print_header "=== SSD Tier 부하 테스트 ==="
        cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: stress-ssd
  namespace: ssd-tier
spec:
  nodeSelector:
    disk-type: ssd
  tolerations:
  - key: storage
    operator: Equal
    value: ssd
    effect: NoSchedule
  containers:
  - name: stress
    image: polinux/stress
    command: ["stress","--cpu","2","--timeout","300s"]
    resources:
      limits:
        cpu: 300m
  restartPolicy: Never
EOF
        print_success "SSD 부하 테스트 시작 (5분간)"
        ;;
    2)
        print_header "=== HDD Tier 부하 테스트 ==="
        cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: stress-hdd
  namespace: hdd-tier
spec:
  nodeSelector:
    disk-type: hdd
  tolerations:
  - key: storage
    operator: Equal
    value: hdd
    effect: NoSchedule
  containers:
  - name: stress
    image: polinux/stress
    command: ["stress","--cpu","4","--timeout","300s"]
    resources:
      limits:
        cpu: 600m
  restartPolicy: Never
EOF
        print_success "HDD 부하 테스트 시작 (5분간)"
        ;;
    3)
        print_header "=== 전체 부하 테스트 ==="
        cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: stress-ssd
  namespace: ssd-tier
spec:
  nodeSelector:
    disk-type: ssd
  tolerations:
  - key: storage
    operator: Equal
    value: ssd
    effect: NoSchedule
  containers:
  - name: stress
    image: polinux/stress
    command: ["stress","--cpu","2","--timeout","300s"]
    resources:
      limits:
        cpu: 300m
  restartPolicy: Never
---
apiVersion: v1
kind: Pod
metadata:
  name: stress-hdd
  namespace: hdd-tier
spec:
  nodeSelector:
    disk-type: hdd
  tolerations:
  - key: storage
    operator: Equal
    value: hdd
    effect: NoSchedule
  containers:
  - name: stress
    image: polinux/stress
    command: ["stress","--cpu","4","--timeout","300s"]
    resources:
      limits:
        cpu: 600m
  restartPolicy: Never
EOF
        print_success "전체 부하 테스트 시작 (5분간)"
        ;;
    4)
        print_header "=== 웹 접속 테스트 ==="
        echo "SSD Tier 테스트..."
        curl -s http://ilove.k8s.com/ssd | grep -E "(SSD Tier|Connection Success)" || echo "접속 실패"
        echo ""
        echo "HDD Tier 테스트..."
        curl -s http://ilove.k8s.com/hdd | grep -E "(HDD Tier|Connection Success)" || echo "접속 실패"
        echo ""
        print_success "웹 접속 테스트 완료"
        exit 0
        ;;
    *)
        echo "잘못된 선택"
        exit 1
        ;;
esac

echo ""
print_info "부하 테스트 모니터링 시작 (5분간, 30초마다 갱신)"
echo ""

# 모니터링 루프
for i in {1..10}; do
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "[$i/10] $(date '+%Y-%m-%d %H:%M:%S')"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # SSD Tier 상태
    print_header "=== SSD Tier ==="
    kubectl top pods -n ssd-tier 2>/dev/null | grep -E "NAME|nginx|tom|stress" || echo "메트릭 수집 중..."
    kubectl get hpa -n ssd-tier 2>/dev/null | grep -E "NAME|nginx" || echo "HPA 없음"
    kubectl get pods -n ssd-tier -o wide | grep -E "NAME|nginx" | awk '{print $1, $3, $7}'
    echo ""
    
    # HDD Tier 상태
    print_header "=== HDD Tier ==="
    kubectl top pods -n hdd-tier 2>/dev/null | grep -E "NAME|nginx|tom|stress" || echo "메트릭 수집 중..."
    kubectl get hpa -n hdd-tier 2>/dev/null | grep -E "NAME|nginx" || echo "HPA 없음"
    kubectl get pods -n hdd-tier -o wide | grep -E "NAME|nginx" | awk '{print $1, $3, $7}'
    echo ""
    
    if [ $i -lt 10 ]; then
        sleep 30
    fi
done

echo ""
print_success "테스트 완료!"
echo ""
print_info "정리 중..."
kubectl delete pod stress-ssd -n ssd-tier 2>/dev/null || true
kubectl delete pod stress-hdd -n hdd-tier 2>/dev/null || true

echo ""
print_header "=== 최종 상태 ==="
kubectl get pods -n ssd-tier -o wide
echo ""
kubectl get pods -n hdd-tier -o wide
echo ""

print_success "모든 테스트 완료!"
echo ""
echo "📊 Grafana에서 상세 메트릭 확인: http://$NODE_IP:30000"
echo "   - Dashboards → Kubernetes / Compute Resources / Namespace (Pods)"
echo "   - namespace: ssd-tier, hdd-tier 선택"
