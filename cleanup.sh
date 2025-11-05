#!/bin/bash

# クラウドストレージ環境のクリーンアップスクリプト

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 確認
log_warning "========================================="
log_warning "警告: このスクリプトは以下を削除します:"
log_warning "- cloud-storage namespace"
log_warning "- 全てのデプロイメント"
log_warning "- 全てのPersistentVolumeClaim（データも削除されます）"
log_warning "========================================="
echo ""
log_error "本当に削除しますか? (yes/no)"
read -r answer

if [[ "$answer" != "yes" ]]; then
    log_info "削除をキャンセルしました"
    exit 0
fi

log_info "削除を開始します..."

# namespace削除（全てのリソースが削除される）
log_info "cloud-storage namespaceを削除中..."
kubectl delete namespace cloud-storage --timeout=300s || log_warning "namespaceの削除に失敗しました"

log_info "クリーンアップが完了しました"
