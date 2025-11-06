#!/bin/bash

# 各サービスの状態を確認するスクリプト

set -e

NAMESPACE="cloud-storage"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}クラウドストレージ環境 - ステータス確認${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Podの状態
echo -e "${YELLOW}[Pods]${NC}"
kubectl get pods -n $NAMESPACE -o wide

echo ""
echo -e "${YELLOW}[Services]${NC}"
kubectl get svc -n $NAMESPACE

echo ""
echo -e "${YELLOW}[PersistentVolumeClaims]${NC}"
kubectl get pvc -n $NAMESPACE

echo ""
echo -e "${YELLOW}[Deployments]${NC}"
kubectl get deployments -n $NAMESPACE

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}各サービスの健全性チェック${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# MinIOのチェック
echo -e "${YELLOW}[MinIO]${NC}"
if kubectl get pod -n $NAMESPACE -l app=minio -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q "Running"; then
    echo -e "${GREEN}✓ MinIO is running${NC}"
    MINIO_POD=$(kubectl get pod -n $NAMESPACE -l app=minio -o jsonpath='{.items[0].metadata.name}')
    echo "  Pod: $MINIO_POD"
else
    echo -e "${RED}✗ MinIO is not running${NC}"
fi

echo ""
# NextCloud DBのチェック
echo -e "${YELLOW}[NextCloud Database]${NC}"
if kubectl get pod -n $NAMESPACE -l app=nextcloud-db -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q "Running"; then
    echo -e "${GREEN}✓ NextCloud DB is running${NC}"
    DB_POD=$(kubectl get pod -n $NAMESPACE -l app=nextcloud-db -o jsonpath='{.items[0].metadata.name}')
    echo "  Pod: $DB_POD"
else
    echo -e "${RED}✗ NextCloud DB is not running${NC}"
fi

echo ""
# NextCloudのチェック
echo -e "${YELLOW}[NextCloud]${NC}"
if kubectl get pod -n $NAMESPACE -l app=nextcloud -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q "Running"; then
    echo -e "${GREEN}✓ NextCloud is running${NC}"
    NC_POD=$(kubectl get pod -n $NAMESPACE -l app=nextcloud -o jsonpath='{.items[0].metadata.name}')
    echo "  Pod: $NC_POD"
else
    echo -e "${RED}✗ NextCloud is not running${NC}"
fi

echo ""
# Collaboraのチェック
echo -e "${YELLOW}[Collabora Online]${NC}"
if kubectl get pod -n $NAMESPACE -l app=collabora -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q "Running"; then
    echo -e "${GREEN}✓ Collabora is running${NC}"
    COLLAB_POD=$(kubectl get pod -n $NAMESPACE -l app=collabora -o jsonpath='{.items[0].metadata.name}')
    echo "  Pod: $COLLAB_POD"
else
    echo -e "${RED}✗ Collabora is not running${NC}"
fi

echo ""
# Immichのチェック
echo -e "${YELLOW}[Immich]${NC}"
if kubectl get pod -n $NAMESPACE -l app=immich-server -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q "Running"; then
    echo -e "${GREEN}✓ Immich Server is running${NC}"
    IMMICH_POD=$(kubectl get pod -n $NAMESPACE -l app=immich-server -o jsonpath='{.items[0].metadata.name}')
    echo "  Pod: $IMMICH_POD"
else
    echo -e "${RED}✗ Immich Server is not running${NC}"
fi

if kubectl get pod -n $NAMESPACE -l app=immich-machine-learning -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q "Running"; then
    echo -e "${GREEN}✓ Immich ML is running${NC}"
else
    echo -e "${RED}✗ Immich ML is not running${NC}"
fi

if kubectl get pod -n $NAMESPACE -l app=immich-postgres -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q "Running"; then
    echo -e "${GREEN}✓ Immich PostgreSQL is running${NC}"
else
    echo -e "${RED}✗ Immich PostgreSQL is not running${NC}"
fi

if kubectl get pod -n $NAMESPACE -l app=immich-redis -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q "Running"; then
    echo -e "${GREEN}✓ Immich Redis is running${NC}"
else
    echo -e "${RED}✗ Immich Redis is not running${NC}"
fi

echo ""
# Nginx Proxy Managerのチェック
echo -e "${YELLOW}[Nginx Proxy Manager]${NC}"
if kubectl get pod -n $NAMESPACE -l app=nginx-proxy-manager -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q "Running"; then
    echo -e "${GREEN}✓ Nginx Proxy Manager is running${NC}"
    NPM_POD=$(kubectl get pod -n $NAMESPACE -l app=nginx-proxy-manager -o jsonpath='{.items[0].metadata.name}')
    echo "  Pod: $NPM_POD"
else
    echo -e "${RED}✗ Nginx Proxy Manager is not running${NC}"
fi

echo ""
# Tailscaleのチェック
echo -e "${YELLOW}[Tailscale]${NC}"
if kubectl get pod -n $NAMESPACE -l app=tailscale-subnet-router -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q "Running"; then
    echo -e "${GREEN}✓ Tailscale is running${NC}"
    TS_POD=$(kubectl get pod -n $NAMESPACE -l app=tailscale-subnet-router -o jsonpath='{.items[0].metadata.name}')
    echo "  Pod: $TS_POD"
    
    # Tailscaleの状態を確認
    echo ""
    echo -e "  ${BLUE}Tailscale Status:${NC}"
    kubectl exec -n $NAMESPACE $TS_POD -- tailscale status 2>/dev/null || echo -e "  ${YELLOW}Unable to get Tailscale status${NC}"
else
    echo -e "${RED}✗ Tailscale is not running${NC}"
fi

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}クイックアクセスコマンド${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

cat << EOF
MinIO Console:
  kubectl port-forward -n $NAMESPACE svc/minio 9001:9001
  http://localhost:9001

NextCloud:
  kubectl port-forward -n $NAMESPACE svc/nextcloud 8080:80
  http://localhost:8080

Collabora Online:
  kubectl port-forward -n $NAMESPACE svc/collabora 9980:9980
  http://localhost:9980

Immich:
  kubectl port-forward -n $NAMESPACE svc/immich-server 3001:3001
  http://localhost:3001

Nginx Proxy Manager:
  kubectl port-forward -n $NAMESPACE svc/nginx-proxy-manager 8081:81
  http://localhost:8081

ログ確認:
  kubectl logs -n $NAMESPACE -l app=nextcloud -f
  kubectl logs -n $NAMESPACE -l app=minio -f
  kubectl logs -n $NAMESPACE -l app=collabora -f
  kubectl logs -n $NAMESPACE -l app=immich-server -f
EOF

echo ""
