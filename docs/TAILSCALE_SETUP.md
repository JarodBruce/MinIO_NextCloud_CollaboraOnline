# Tailscale設定ガイド

## 概要

このガイドでは、k3sクラスタへのTailscaleを使用したセキュアなリモートアクセス設定方法を説明します。

## Tailscaleとは

Tailscaleは、WireGuardベースのメッシュVPNです。複雑なファイアウォール設定やポート開放なしに、デバイス間でセキュアな接続を確立できます。

## セットアップ手順

### 1. Tailscaleアカウントの作成

1. https://tailscale.com にアクセス
2. アカウントを作成（Google、Microsoft、GitHubアカウントでログイン可能）

### 2. Auth Keyの取得

1. Tailscale管理画面にログイン: https://login.tailscale.com/admin
2. Settings > Keys に移動
3. "Generate auth key" をクリック
4. 設定:
   - **Reusable**: ✓ チェック（複数デバイスで使用可能）
   - **Ephemeral**: ✗ チェックしない（永続的な接続）
   - **Tags**: `tag:k8s` を追加（オプション）
   - **Expiration**: 90 days または Never expire を選択
5. "Generate key" をクリックしてキーをコピー

### 3. Auth Keyの設定

#### 方法1: デプロイスクリプト使用時

```bash
./deploy.sh
```

スクリプトが自動的にAuth Keyの入力を求めます。

#### 方法2: 手動設定

`k8s/06-tailscale.yaml`を編集：

```yaml
stringData:
  TS_AUTHKEY: "tskey-auth-xxxxxxxxxxxxx-yyyyyyyyyyyyyyyyyyyy"
```

**セキュリティ注意**: Auth KeyをGitにコミットしないでください！

### 4. Tailscaleのデプロイ

```bash
kubectl apply -f k8s/06-tailscale.yaml
```

### 5. Subnet Routerの承認

1. Tailscale管理画面にアクセス: https://login.tailscale.com/admin/machines
2. k3sクラスタのマシンを探す（`tailscale-subnet-router-xxx` という名前）
3. マシンをクリック
4. "Edit route settings..." をクリック
5. Subnet routes セクションで `10.43.0.0/16` を承認（Approve）
6. 必要に応じて `10.42.0.0/16` も承認（Pod CIDR）

### 6. 接続確認

Tailscaleがインストールされた別のデバイスから：

```bash
# Tailscale IPの確認
tailscale status

# k3sクラスタへの接続テスト
curl http://10.43.x.x:81  # Nginx Proxy Manager
```

## ACL（アクセス制御リスト）の設定

### 基本的なACL設定

Tailscale管理画面 > Access Controls で設定：

```json
{
  "tagOwners": {
    "tag:k8s": ["your-email@example.com"],
    "tag:admin": ["your-email@example.com"]
  },
  "acls": [
    // k8sタグを持つマシンへのアクセス（全員）
    {
      "action": "accept",
      "src": ["*"],
      "dst": ["tag:k8s:*"]
    },
    // 管理者のみk8s管理ポートへアクセス可能
    {
      "action": "accept",
      "src": ["tag:admin"],
      "dst": ["tag:k8s:81,9001"]
    }
  ]
}
```

### より詳細なACL例

```json
{
  "tagOwners": {
    "tag:k8s": ["admin@example.com"],
    "tag:user": ["admin@example.com"],
    "tag:guest": ["admin@example.com"]
  },
  "acls": [
    // 管理者は全てにアクセス可能
    {
      "action": "accept",
      "src": ["tag:admin"],
      "dst": ["*:*"]
    },
    // ユーザーはNextCloudとCollaboraにアクセス可能
    {
      "action": "accept",
      "src": ["tag:user"],
      "dst": ["tag:k8s:80,443,9980"]
    },
    // ゲストはNextCloudのみアクセス可能
    {
      "action": "accept",
      "src": ["tag:guest"],
      "dst": ["tag:k8s:80,443"]
    }
  ]
}
```

## DNS設定（MagicDNS）

TailscaleのMagicDNS機能を使用すると、IPアドレスの代わりにホスト名でアクセスできます。

### MagicDNSの有効化

1. Tailscale管理画面 > DNS
2. "Enable MagicDNS" をクリック
3. Nameserversを設定（オプション）

### 使用例

```bash
# IPアドレスの代わりに
curl http://10.43.x.x:81

# ホスト名を使用
curl http://tailscale-subnet-router:81
```

## Nginx Proxy Managerとの統合

### 1. Tailscale経由のアクセス設定

Nginx Proxy Managerで各サービスのプロキシホストを設定：

```
Domain: nextcloud.tailnet-xxxx.ts.net
Scheme: http
Forward Hostname/IP: nextcloud.cloud-storage.svc.cluster.local
Forward Port: 80
```

### 2. カスタムドメインの使用

TailscaleのHTTPS証明書を使用：

1. Tailscale管理画面 > DNS > HTTPS Certificates
2. "Enable HTTPS" をクリック
3. 各マシンで証明書が自動発行される
4. `https://<machine-name>.<tailnet-name>.ts.net` でアクセス可能

## トラブルシューティング

### Tailscale Podが起動しない

```bash
# ログ確認
kubectl logs -n cloud-storage -l app=tailscale-subnet-router

# よくある問題:
# - Auth Keyが無効または期限切れ
# - ネットワーク権限不足（NET_ADMIN capability）
```

**解決方法:**
```bash
# Auth Keyを再生成して更新
kubectl delete secret tailscale-auth -n cloud-storage
kubectl create secret generic tailscale-auth \
  --from-literal=TS_AUTHKEY='新しいAuthKey' \
  -n cloud-storage

# Podを再起動
kubectl rollout restart deployment/tailscale-subnet-router -n cloud-storage
```

### Subnet Routesが表示されない

```bash
# Tailscale状態確認
kubectl exec -n cloud-storage <tailscale-pod> -- tailscale status

# ルート確認
kubectl exec -n cloud-storage <tailscale-pod> -- ip route
```

**確認事項:**
- IP Forwardingが有効か
- TS_ROUTESパラメータが正しいか
- SecurityContextが正しく設定されているか

### クラスタ内サービスにアクセスできない

```bash
# Service IPの確認
kubectl get svc -n cloud-storage

# ネットワーク接続テスト
kubectl exec -n cloud-storage <tailscale-pod> -- ping <service-ip>
```

**チェックポイント:**
- Subnet routesが承認されているか
- ファイアウォールルールが干渉していないか
- k3s Service CIDRが正しく設定されているか

## セキュリティのベストプラクティス

### 1. Auth Keyの管理

- ✓ Reusableキーは必要最小限に使用
- ✓ 定期的にキーをローテーション
- ✓ 不要になったキーは削除
- ✗ Auth KeyをGitリポジトリにコミットしない

### 2. ACLの設定

- ✓ 最小権限の原則を適用
- ✓ タグベースのアクセス制御を使用
- ✓ 定期的にアクセスログを確認
- ✓ 不要なルールは削除

### 3. ネットワーク分離

```yaml
# Tailscale専用のネットワークポリシー
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-from-tailscale
  namespace: cloud-storage
spec:
  podSelector:
    matchLabels:
      app: nginx-proxy-manager
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: tailscale-subnet-router
    ports:
    - protocol: TCP
      port: 80
    - protocol: TCP
      port: 443
```

### 4. 監査とログ

```bash
# Tailscaleのログ確認
kubectl logs -n cloud-storage -l app=tailscale-subnet-router -f

# 接続状態の監視
watch -n 5 'kubectl exec -n cloud-storage <tailscale-pod> -- tailscale status'
```

## 高度な設定

### Exit Nodeとしての使用

クラスタをExit Node（全トラフィックをルーティング）として設定：

```yaml
env:
- name: TS_EXTRA_ARGS
  value: "--advertise-exit-node --advertise-tags=tag:k8s"
```

### カスタムDNS設定

```yaml
env:
- name: TS_ACCEPT_DNS
  value: "true"
- name: TS_EXTRA_ARGS
  value: "--accept-dns=true --advertise-tags=tag:k8s"
```

### 複数Subnet Routeの追加

```yaml
env:
- name: TS_ROUTES
  value: "10.43.0.0/16,10.42.0.0/16,192.168.1.0/24"
```

## クライアント設定

### モバイルデバイス

1. Tailscaleアプリをインストール
   - iOS: App Store
   - Android: Google Play
2. アカウントでログイン
3. 自動的にネットワークに参加

### デスクトップ

#### macOS/Linux

```bash
# インストール
brew install tailscale  # macOS
# または
curl -fsSL https://tailscale.com/install.sh | sh  # Linux

# 認証
sudo tailscale up

# 状態確認
tailscale status
```

#### Windows

1. https://tailscale.com/download/windows からインストーラーをダウンロード
2. インストール後、タスクバーアイコンからログイン

## 料金プラン

- **Free**: 個人使用、最大20デバイス、1ユーザー
- **Personal Pro**: $5/月、追加機能
- **Team**: $15/ユーザー/月、チーム向け機能
- **Enterprise**: カスタム価格、エンタープライズ機能

このプロジェクトは無料プランで十分に動作します。

## 参考リンク

- [Tailscale公式ドキュメント](https://tailscale.com/kb/)
- [Subnet Routersガイド](https://tailscale.com/kb/1019/subnets/)
- [ACL設定](https://tailscale.com/kb/1018/acls/)
- [Kubernetes統合](https://tailscale.com/kb/1185/kubernetes/)
- [MagicDNS](https://tailscale.com/kb/1081/magicdns/)

---

**最終更新**: 2025年11月5日
