#!/bin/bash
set -e

echo "=== 노드 준비 ==="
kubectl get nodes -o wide
echo ""
read -p "SSD 노드 이름: " SSD_NODE
read -p "HDD 노드 이름: " HDD_NODE
echo ""
echo "라벨 설정 중..."
kubectl label nodes $SSD_NODE disk-type=ssd --overwrite
kubectl label nodes $HDD_NODE disk-type=hdd --overwrite
echo "✅ 노드 준비 완료"
kubectl get nodes --show-labels | grep -E "NAME|disk-type"
