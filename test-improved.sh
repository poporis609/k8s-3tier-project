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
print_error() { echo -e "${RED}❌ $1${NC}"; }

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
kubectl get hpa -n ssd-tier 2>/dev/null || print_info "SSD HPA 없음 (kubectl apply -f 06-hpa.yaml 실행 필요)"
kubectl get hpa -n hdd-tier 2>/dev/null || print_info "HDD HPA 없음 (kubectl apply -f 06-hpa.yaml 실행 필요)"
echo ""

read -p "HPA를 활성화하시겠습니까? (y/n): " enable_hpa
if [[ $enable_hpa == "y" ]]; then
    print_info "HPA 활성화 중..."
    kubectl apply -f 06-hpa.yaml
    sleep 10
    print_success "HPA 활성화 완료"
fi
echo ""

read -p "부하테스트를 위해 wrk를 install 하겠습니다. (y/n): " install_wrk
if [[ $install_wrk == "y" ]]; then
    print_info "wrk install 중..."
    apt install -y wrk
    sleep 10
    print_success "wrk install 완료"
fi
echo ""

# 실시간 모니터링 함수
monitor_pods_hpa() {
    local duration=$1
    local end_time=$((SECONDS + duration))
    
    print_header "=== 실시간 모니터링 시작 (${duration}초) ==="
    
    while [ $SECONDS -lt $end_time ]; do
        clear
        echo "╔═══════════════════════════════════════════════════════════╗"
        echo "║          실시간 Pod & HPA 모니터링                         ║"
        echo "║          남은 시간: $((end_time - SECONDS))초                         ║"
        echo "╚═══════════════════════════════════════════════════════════╝"
        echo ""
        
        print_header "📦 SSD Tier Pods:"
        kubectl get pods -n ssd-tier -o wide --no-headers | awk '{printf "  %-40s %-15s %-10s %s\n", $1, $3, $4, $7}'
        echo ""
        
        print_header "📦 HDD Tier Pods:"
        kubectl get pods -n hdd-tier -o wide --no-headers | awk '{printf "  %-40s %-15s %-10s %s\n", $1, $3, $4, $7}'
        echo ""
        
        print_header "📊 HPA 상태:"
        kubectl get hpa -n ssd-tier 2>/dev/null | tail -n +2 | awk '{printf "  SSD: %s/%s replicas, CPU: %s\n", $3, $4, $5}'
        kubectl get hpa -n hdd-tier 2>/dev/null | tail -n +2 | awk '{printf "  HDD: %s/%s replicas, CPU: %s\n", $3, $4, $5}'
        echo ""
        
        print_header "🔥 리소스 사용량:"
        kubectl top pods -n ssd-tier --no-headers 2>/dev/null | awk '{sum_cpu+=$2; sum_mem+=$3} END {print "  SSD Total: CPU=" sum_cpu ", Memory=" sum_mem}' || echo "  SSD: 메트릭 수집 중..."
        kubectl top pods -n hdd-tier --no-headers 2>/dev/null | awk '{sum_cpu+=$2; sum_mem+=$3} END {print "  HDD Total: CPU=" sum_cpu ", Memory=" sum_mem}' || echo "  HDD: 메트릭 수집 중..."
        
        sleep 5
    done
    
    print_success "모니터링 완료!"
}

# 테스트 옵션 선택
echo "테스트 옵션을 선택하세요:"
echo "  1) SSD Tier 부하 테스트 (CPU 25% 목표)"
echo "  2) HDD Tier 부하 테스트 (CPU 50% 목표)"
echo "  3) 두 Tier 동시 부하 테스트"
echo "  4) 실시간 Pod & HPA 모니터링 (1분)"
echo "  5) 웹 접속 테스트 (curl)"
read -p "선택 (1-5): " choice

case $choice in
    1)
        print_header "=== SSD Tier 부하 테스트 ==="
        print_info "부하 테스트 시작 (1분간)..."
        wrk -t8 -c500 -d60s http://ilove.k8s.com/ssd/ > /tmp/ssd_load.log 2>&1 &
        LOAD_PID=$!
        
        monitor_pods_hpa 60
        
        wait $LOAD_PID
        print_success "SSD 부하 테스트 완료"
        echo ""
        print_header "테스트 결과:"
        cat /tmp/ssd_load.log
        ;;
    2)
        print_header "=== HDD Tier 부하 테스트 ==="
        print_info "부하 테스트 시작 (1분간)..."
        wrk -t10 -c1000 -d60s http://ilove.k8s.com/hdd/ > /tmp/hdd_load.log 2>&1 &
        LOAD_PID=$!
        
        monitor_pods_hpa 60
        
        wait $LOAD_PID
        print_success "HDD 부하 테스트 완료"
        echo ""
        print_header "테스트 결과:"
        cat /tmp/hdd_load.log
        ;;
    3)
        print_header "=== 두 Tier 동시 부하 테스트 ==="
        print_info "SSD & HDD 동시 부하 테스트 시작 (1분간)..."
        
        # 백그라운드에서 두 부하 테스트 동시 실행
        wrk -t8 -c500 -d60s http://ilove.k8s.com/ssd/ > /tmp/ssd_load.log 2>&1 &
        SSD_PID=$!
        
        wrk -t10 -c1000 -d60s http://ilove.k8s.com/hdd/ > /tmp/hdd_load.log 2>&1 &
        HDD_PID=$!
        
        print_success "두 Tier 부하 테스트 시작됨 (PID: SSD=$SSD_PID, HDD=$HDD_PID)"
        
        # 실시간 모니터링
        monitor_pods_hpa 60
        
        # 두 프로세스 모두 완료 대기
        wait $SSD_PID
        wait $HDD_PID
        
        print_success "동시 부하 테스트 완료"
        echo ""
        print_header "=== SSD Tier 테스트 결과 ==="
        cat /tmp/ssd_load.log
        echo ""
        print_header "=== HDD Tier 테스트 결과 ==="
        cat /tmp/hdd_load.log
        ;;
    4)
        print_header "=== 실시간 모니터링 모드 ==="
        monitor_pods_hpa 60
        ;;
    5)
        print_header "=== 웹 접속 테스트 ==="
        echo "SSD Tier 테스트..."
        curl -s http://ilove.k8s.com/ssd | grep -E "(SSD Tier|Connection Success)" || print_error "접속 실패"
        echo ""
        echo "HDD Tier 테스트..."
        curl -s http://ilove.k8s.com/hdd | grep -E "(HDD Tier|Connection Success)" || print_error "접속 실패"
        echo ""
        print_success "웹 접속 테스트 완료"
        exit 0
        ;;
    *)
        print_error "잘못된 선택"
        exit 1
        ;;
esac

echo ""
print_success "모든 테스트 완료! 종료합니다."
echo ""

# 최종 상태 확인
print_header "=== 최종 상태 ==="
kubectl get hpa -n ssd-tier 2>/dev/null
kubectl get hpa -n hdd-tier 2>/dev/null
echo ""
kubectl get pods -n ssd-tier
echo ""
kubectl get pods -n hdd-tier
