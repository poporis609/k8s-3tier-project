#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

print_success() { echo -e "${GREEN}✅ $1${NC}"; }
print_error() { echo -e "${RED}❌ $1${NC}"; }

echo "╔════════════════════════════════════════════════╗"
echo "║        Kubernetes 3-Tier Cleanup Script        ║"
echo "╚════════════════════════════════════════════════╝"

# Delete Ingress resources
echo "Deleting Ingress resources..."
kubectl delete ingress ssd-ingress -n ssd-tier 2>/dev/null || true
kubectl delete ingress hdd-ingress -n hdd-tier 2>/dev/null || true

# Delete HPA resources
echo "Deleting HPA resources..."
kubectl delete hpa ssd-nginx-hpa -n ssd-tier 2>/dev/null || true
kubectl delete hpa hdd-nginx-hpa -n hdd-tier 2>/dev/null || true

# Delete SSD tier resources
echo "Deleting SSD tier resources..."
kubectl delete all --all -n ssd-tier 2>/dev/null || true
kubectl delete pvc --all -n ssd-tier 2>/dev/null || true
kubectl delete pv ssd-tom-pv 2>/dev/null || true
kubectl delete configmap --all -n ssd-tier 2>/dev/null || true
kubectl delete secret --all -n ssd-tier 2>/dev/null || true

# Delete HDD tier resources
echo "Deleting HDD tier resources..."
kubectl delete all --all -n hdd-tier 2>/dev/null || true
kubectl delete pvc --all -n hdd-tier 2>/dev/null || true
kubectl delete pv hdd-tom-pv 2>/dev/null || true
kubectl delete configmap --all -n hdd-tier 2>/dev/null || true
kubectl delete secret --all -n hdd-tier 2>/dev/null || true

# Delete monitoring resources
echo "Deleting monitoring resources..."
kubectl delete all --all -n monitoring 2>/dev/null || true
kubectl delete configmap --all -n monitoring 2>/dev/null || true
kubectl delete secret --all -n monitoring 2>/dev/null || true

# Delete namespaces
echo "Deleting namespaces..."
kubectl delete namespace ssd-tier 2>/dev/null || true
kubectl delete namespace hdd-tier 2>/dev/null || true
kubectl delete namespace monitoring 2>/dev/null || true

# Delete StorageClass
echo "Deleting StorageClass..."
kubectl delete sc nfs-storage 2>/dev/null || true

# Delete Helm releases
echo "Deleting Helm releases..."
helm uninstall metrics-server -n kube-system 2>/dev/null || true
helm uninstall kube-prometheus -n monitoring 2>/dev/null || true

# Untaint nodes
echo "Removing taints from nodes..."
kubectl taint nodes worker-1 storage=ssd:NoSchedule- || true
kubectl taint nodes worker-2 storage=ssd:NoSchedule- || true
kubectl taint nodes master node-role.kubernetes.io/control-plane:NoSchedule- || true

print_success "Cleanup and Taint removal completed successfully!"

