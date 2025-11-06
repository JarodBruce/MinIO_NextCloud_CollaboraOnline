#!/bin/bash

# Collabora + Cloudflare Access 問題のクイックフィックス
# このスクリプトは、Collaboraの設定を更新し、Cloudflare Accessの設定手順を表示します

set -e

# カラー定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Collabora + Cloudflare Access クイックフィックス${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# 問題の説明
echo -e "${YELLOW}【問題】${NC}"
echo "CollaboraがNextCloudのWOPIエンドポイントにアクセスしようとすると、"
echo "Cloudflare Accessの認証画面にリダイレクトされ、404エラーが発生します。"
echo ""

# 解決策の説明
echo -e "${GREEN}【解決策】${NC}"
echo "1. Collaboraの設定を更新（このスクリプトで実行）"
echo "2. Cloudflare AccessでWOPIエンドポイントをバイパス（手動設定）"
echo ""

# 確認
read -p "続行しますか？ (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${RED}中止しました${NC}"
    exit 1
fi

echo ""
echo -e "${BLUE}ステップ1: Collabora設定の更新${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Collabora設定を適用
echo "Collabora ConfigMapを更新しています..."
kubectl apply -f k8s/04-collabora.yaml

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Collabora ConfigMap更新完了${NC}"
else
    echo -e "${RED}✗ Collabora ConfigMap更新失敗${NC}"
    exit 1
fi

# Collabora Podを再起動
echo ""
echo "Collabora Deploymentを再起動しています..."
kubectl rollout restart deployment/collabora -n cloud-storage

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Collabora再起動開始${NC}"
else
    echo -e "${RED}✗ Collabora再起動失敗${NC}"
    exit 1
fi

# 再起動完了を待機
echo ""
echo "再起動完了を待っています..."
kubectl rollout status deployment/collabora -n cloud-storage --timeout=300s

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Collabora再起動完了${NC}"
else
    echo -e "${RED}✗ タイムアウト: Podの状態を確認してください${NC}"
fi

echo ""
echo -e "${BLUE}ステップ2: Cloudflare Access設定（手動作業）${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo -e "${YELLOW}以下の手順を手動で実行してください：${NC}"
echo ""
echo "1. Cloudflare Zero Trust Dashboardにアクセス"
echo -e "   ${BLUE}https://one.dash.cloudflare.com/${NC}"
echo ""
echo "2. 新しいApplicationを作成"
echo "   Access → Applications → Add an application"
echo ""
echo "3. Application Configurationを設定"
echo ""
echo -e "   ${GREEN}Application name:${NC} NextCloud WOPI (No Auth)"
echo -e "   ${GREEN}Application domain:${NC} nextcloud.jarodbruce.f5.si"
echo -e "   ${GREEN}Path:${NC} /index.php/apps/richdocuments/wopi"
echo -e "   ${GREEN}Include all subpaths:${NC} ✓ チェック（重要！）"
echo ""
echo "4. Identity Providersを選択"
echo "   任意のプロバイダーを選択（実際には使用されません）"
echo ""
echo "5. Policy設定"
echo ""
echo -e "   ${GREEN}Policy name:${NC} Bypass everyone"
echo -e "   ${GREEN}Action:${NC} Bypass"
echo -e "   ${GREEN}Include:${NC} Everyone を選択"
echo ""
echo "   ${YELLOW}これだけです！他のルールは不要です。${NC}"
echo ""
echo "6. 保存"
echo "   Add application をクリック
echo ""
echo "5. 保存して数分待つ"
echo "   Save application をクリック"
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}注意:${NC}"
echo "• ポリシーの反映には数分かかる場合があります"
echo "• ブラウザのキャッシュをクリアすることを推奨します"
echo "• Cloudflareのキャッシュもパージしてください"
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${GREEN}動作確認:${NC}"
echo ""
echo "1. NextCloudにログイン"
echo "   https://nextcloud.jarodbruce.f5.si"
echo ""
echo "2. 新しいドキュメントを作成（または既存のドキュメントを開く）"
echo "   Files → + → New document"
echo ""
echo "3. Collaboraログを確認"
echo -e "   ${BLUE}kubectl logs -n cloud-storage -l app=collabora -f --tail=50${NC}"
echo ""
echo "   成功時のログ（これが表示されればOK）:"
echo -e "   ${GREEN}INF  WOPI::CheckFileInfo success for URI${NC}"
echo ""
echo "   失敗時のログ（これが出る場合は設定を再確認）:"
echo -e "   ${RED}ERR  WOPI::CheckFileInfo returned 404${NC}"
echo -e "   ${RED}ERR  Access denied to CheckFileInfo${NC}"
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${GREEN}トラブルシューティング:${NC}"
echo ""
echo "問題が解決しない場合は、以下を確認してください:"
echo ""
echo "1. Cloudflare Accessポリシーの順序"
echo "   Bypassが最初に評価されているか？"
echo ""
echo "2. 正規表現のテスト"
echo "   URLの例: /index.php/apps/richdocuments/wopi/files/7_xxx"
echo "   正規表現: ^/index\\.php/apps/richdocuments/wopi/.*"
echo ""
echo "3. Collaboraのログで実際のURLを確認"
echo -e "   ${BLUE}kubectl logs -n cloud-storage -l app=collabora | grep WOPI${NC}"
echo ""
echo "4. キャッシュのクリア"
echo "   • ブラウザのキャッシュ（Ctrl+Shift+Delete）"
echo "   • Cloudflareのキャッシュ（Dashboard → Caching → Purge Everything）"
echo ""
echo "5. 詳細なガイド"
echo -e "   ${BLUE}docs/COLLABORA_CLOUDFLARE_ACCESS_FIX.md${NC}"
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${GREEN}✓ スクリプト完了${NC}"
echo ""
echo "Cloudflare Accessの設定を完了したら、動作確認を行ってください。"
echo ""
