#!/bin/bash

# k3sクラウドストレージ環境デプロイスクリプト
# MinIO + NextCloud + Collabora Online + Nginx Proxy Manager + Tailscale

set -e

# カラー設定
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ロギング関数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# エラーハンドリング
error_exit() {
    log_error "$1"
    exit 1
}

# k3sがインストールされているか確認
check_k3s() {
    log_info "k3sの存在を確認中..."
    if ! command -v k3s &> /dev/null; then
        log_error "k3sがインストールされていません"
        log_info "k3sをインストールしますか? (y/n)"
        read -r answer
        if [[ "$answer" =~ ^[Yy]$ ]]; then
            install_k3s
        else
            error_exit "k3sが必要です"
        fi
    else
        log_success "k3sが見つかりました"
    fi
}

# k3sのインストール
install_k3s() {
    log_info "k3sをインストール中..."
    curl -sfL https://get.k3s.io | sh -
    
    # kubectlエイリアスの設定
    export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
    sudo chmod 644 /etc/rancher/k3s/k3s.yaml
    
    log_success "k3sのインストールが完了しました"
}

# kubectlの設定確認
check_kubectl() {
    log_info "kubectlアクセスを確認中..."
    if ! kubectl get nodes &> /dev/null; then
        log_warning "kubectlが正しく設定されていません"
        export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
        
        if ! kubectl get nodes &> /dev/null; then
            error_exit "kubectlの設定に失敗しました。sudo権限が必要な可能性があります"
        fi
    fi
    log_success "kubectl設定OK"
}

# Tailscale Auth Keyの確認
check_tailscale_auth() {
    log_info "Tailscale認証キーを確認中..."
    
    if grep -q "tskey-auth-XXXXXXXXXX" k8s/06-tailscale.yaml; then
        log_warning "Tailscale Auth Keyが設定されていません"
        log_info "Tailscale管理画面からAuth Keyを取得してください:"
        log_info "https://login.tailscale.com/admin/settings/keys"
        log_info ""
        log_info "Auth Keyを入力してください (スキップする場合はEnter):"
        read -r ts_authkey
        
        if [[ -n "$ts_authkey" ]]; then
            # macOSとLinuxの両方で動作するsed
            if [[ "$OSTYPE" == "darwin"* ]]; then
                sed -i '' "s|tskey-auth-XXXXXXXXXX-XXXXXXXXXXXXXXXXXXXX|${ts_authkey}|g" k8s/06-tailscale.yaml
            else
                sed -i "s|tskey-auth-XXXXXXXXXX-XXXXXXXXXXXXXXXXXXXX|${ts_authkey}|g" k8s/06-tailscale.yaml
            fi
            log_success "Tailscale Auth Keyを設定しました"
        else
            log_warning "Tailscaleの設定をスキップします（後で手動で設定してください）"
        fi
    else
        log_success "Tailscale Auth Keyは設定済みです"
    fi
}

# マニフェストの適用
apply_manifests() {
    log_info "Kubernetesマニフェストを適用中..."
    
    # 順番に適用
    local manifests=(
        "00-namespace.yaml"
        "01-storage.yaml"
        "02-minio.yaml"
        "03-nextcloud.yaml"
        "04-collabora.yaml"
        "05-nginx-proxy-manager.yaml"
        "06-tailscale.yaml"
    )
    
    for manifest in "${manifests[@]}"; do
        log_info "適用中: $manifest"
        kubectl apply -f "k8s/$manifest" || error_exit "$manifest の適用に失敗しました"
        sleep 2
    done
    
    log_success "全てのマニフェストを適用しました"
}

# デプロイメントの状態確認
wait_for_deployments() {
    log_info "デプロイメントの準備を待機中..."
    
    local deployments=(
        "minio"
        "nextcloud-db"
        "nextcloud"
        "collabora"
        "nginx-proxy-manager"
    )
    
    for deployment in "${deployments[@]}"; do
        log_info "待機中: $deployment"
        kubectl rollout status deployment/"$deployment" -n cloud-storage --timeout=600s || \
            log_warning "$deployment の起動に時間がかかっています（バックグラウンドで続行）"
    done
    
    log_success "全てのデプロイメントが起動しました"
}

# ステータス表示
show_status() {
    echo ""
    log_info "========================================="
    log_info "デプロイメント完了！"
    log_info "========================================="
    echo ""
    
    log_info "Podの状態:"
    kubectl get pods -n cloud-storage
    
    echo ""
    log_info "Serviceの状態:"
    kubectl get svc -n cloud-storage
    
    echo ""
    log_info "PVCの状態:"
    kubectl get pvc -n cloud-storage
    
    echo ""
    log_success "========================================="
    log_success "アクセス情報"
    log_success "========================================="
    echo ""
    
    # ポートフォワード用のコマンドを表示
    cat << EOF
各サービスへのアクセス方法:

1. MinIO Console:
   kubectl port-forward -n cloud-storage svc/minio 9001:9001
   ブラウザ: http://localhost:9001
   ユーザー名: minioadmin
   パスワード: minioadmin123

2. NextCloud:
   kubectl port-forward -n cloud-storage svc/nextcloud 8080:80
   ブラウザ: http://localhost:8080
   ユーザー名: admin
   パスワード: admin123

3. Collabora Online:
   kubectl port-forward -n cloud-storage svc/collabora 9980:9980
   ブラウザ: http://localhost:9980

4. Nginx Proxy Manager:
   kubectl port-forward -n cloud-storage svc/nginx-proxy-manager 8081:81
   ブラウザ: http://localhost:8081
   初期ユーザー名: admin@example.com
   初期パスワード: changeme

5. Tailscaleの状態確認:
   kubectl logs -n cloud-storage -l app=tailscale-subnet-router

========================================
次のステップ:
========================================

1. MinIOでNextCloud用のバケット作成
   - MinIO Consoleにログイン
   - 'nextcloud' という名前のバケットを作成

2. Nginx Proxy Managerの設定
   - 管理画面にログイン後、パスワードを変更
   - 各サービスのプロキシホストを設定

3. Tailscaleの設定
   - Tailscale管理画面でサブネットルーターを承認
   - https://login.tailscale.com/admin/machines

4. NextCloudの設定
   - 初回アクセス時に管理者アカウントでログイン
   - Collabora Onlineアプリをインストール
   - 設定 > Collabora Online > サーバーURLを設定

5. SSL証明書の設定（オプション）
   - Nginx Proxy ManagerでLet's Encrypt証明書を取得

========================================
EOF
}

# メイン処理
main() {
    log_info "k3sクラウドストレージ環境のデプロイを開始します"
    echo ""
    
    # 前提条件チェック
    check_k3s
    check_kubectl
    
    # Tailscale設定確認
    check_tailscale_auth
    
    # デプロイ開始確認
    log_warning "デプロイを開始しますか? (y/n)"
    read -r answer
    if [[ ! "$answer" =~ ^[Yy]$ ]]; then
        log_info "デプロイをキャンセルしました"
        exit 0
    fi
    
    # マニフェスト適用
    apply_manifests
    
    # デプロイメント待機
    wait_for_deployments
    
    # ステータス表示
    show_status
    
    log_success "デプロイが完了しました！"
}

# スクリプト実行
main "$@"
