#!/bin/bash
set -e

echo "=== 모니터링 스택 설치 ==="
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/ 2>/dev/null || true
helm repo update

kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

echo "[1/2] Metrics Server..."
helm upgrade --install metrics-server metrics-server/metrics-server \
  -n kube-system \
  --set args[0]="--kubelet-insecure-tls" \
  --set args[1]="--kubelet-preferred-address-types=InternalIP" \
  --wait --timeout=5m

echo "[2/2] Prometheus + Grafana..."

helm upgrade --install kube-prometheus prometheus-community/kube-prometheus-stack \
  -n monitoring \
  --set prometheus.prometheusSpec.retention=7d \
  --set grafana.adminPassword=admin123 \
  --set grafana.service.type=NodePort \
  --set grafana.service.nodePort=30000 \
  --set alertmanager.enabled=false \
  --timeout=10m \
  --wait

echo "✅ 완료"
NODE_IP=$(kubectl get nodes -o wide | awk 'NR==2 {print $6}')
echo "Grafana: http://$NODE_IP:30000 (admin/admin123)"
