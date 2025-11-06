#!/bin/bash

# k3sクラウドストレージ環境デプロイスクリプト
# MinIO + NextCloud + Collabora Online + Cloudflare Tunnel

set -e

# カラー設定
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# .envファイルの読み込み
if [ -f .env ]; then
    log_info ".envファイルを読み込み中..." 2>/dev/null || echo "[INFO] .envファイルを読み込み中..."
    export $(cat .env | grep -v '^#' | xargs)
else
    echo -e "${YELLOW}[WARNING]${NC} .envファイルが見つかりません"
    echo -e "${BLUE}[INFO]${NC} .env.exampleをコピーして.envを作成してください"
    echo -e "${BLUE}[INFO]${NC} cp .env.example .env"
    exit 1
fi

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

# Cloudflare Tunnel Tokenの確認と適用
check_cloudflare_token() {
    log_info "Cloudflare Tunnel Tokenを確認中..."
    
    if [[ -z "$TUNNEL_TOKEN" ]] || [[ "$TUNNEL_TOKEN" == "your_cloudflare_tunnel_token_here" ]]; then
        log_warning "Cloudflare Tunnel Tokenが設定されていません"
        log_info "Cloudflareダッシュボードからトンネルトークンを取得してください:"
        log_info "https://dash.cloudflare.com/ → Zero Trust → Networks → Tunnels"
        log_info ""
        log_info ".envファイルにTUNNEL_TOKENを設定してください"
        log_warning "Cloudflare Tunnelの設定をスキップしますか? (y/n)"
        read -r answer
        if [[ ! "$answer" =~ ^[Yy]$ ]]; then
            error_exit "Cloudflare Tunnel Tokenを設定してから再実行してください"
        fi
        return
    fi
    
    # Secretを動的に作成
    log_info "Cloudflare Tunnel Secretを作成中..."
    kubectl create secret generic cloudflare-tunnel-token \
        --from-literal=TUNNEL_TOKEN="$TUNNEL_TOKEN" \
        -n cloud-storage \
        --dry-run=client -o yaml | kubectl apply -f -
    
    log_success "Cloudflare Tunnel Tokenを設定しました"
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
        "05-immich.yaml"
        "06-cloudflare-tunnel.yaml"
    )
    
    for manifest in "${manifests[@]}"; do
        log_info "適用中: $manifest"
        kubectl apply -f "k8s/$manifest" || error_exit "$manifest の適用に失敗しました"
        
        # namespaceを作成した後にCloudflare Tunnel Secretを作成
        if [[ "$manifest" == "00-namespace.yaml" ]]; then
            check_cloudflare_token
        fi
        
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
        "immich-postgres"
        "immich-redis"
        "immich-server"
        "immich-machine-learning"
        "cloudflare-tunnel"
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

4. Immich:
   kubectl port-forward -n cloud-storage svc/immich-server 3001:3001
   ブラウザ: http://localhost:3001

5. Cloudflare Tunnelの状態確認:
   kubectl logs -n cloud-storage -l app=cloudflare-tunnel

========================================
次のステップ:
========================================

1. MinIOでバケット作成
   - MinIO Consoleにログイン
   - 'nextcloud' という名前のバケットを作成
   - 'immich' という名前のバケットを作成

2. Cloudflare Tunnelの設定
   - Cloudflareダッシュボードでトンネルを作成
   - Public Hostnameを設定して各サービスをルーティング
   - 詳細: docs/CLOUDFLARE_TUNNEL_SETUP.md を参照

3. NextCloudの設定
   - 初回アクセス時に管理者アカウントでログイン
   - Collabora Onlineアプリをインストール
   - 設定 > Collabora Online > サーバーURLを設定
   - Cloudflareドメインを信頼されたドメインに追加

4. Collabora OnlineのWOPI設定
   - NextCloudのドメインをCollabora側で許可

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
    
    # デプロイ開始確認
    log_warning "デプロイを開始しますか? (y/n)"
    read -r answer
    if [[ ! "$answer" =~ ^[Yy]$ ]]; then
        log_info "デプロイをキャンセルしました"
        exit 0
    fi
    
    # マニフェスト適用（Cloudflare Tokenはnamespace作成後に適用される）
    apply_manifests
    
    # デプロイメント待機
    wait_for_deployments
    
    # ステータス表示
    show_status
    
    log_success "デプロイが完了しました！"
}

# スクリプト実行
main "$@"
