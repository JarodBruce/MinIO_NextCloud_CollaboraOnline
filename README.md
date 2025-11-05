# k3s クラウドストレージ環境
# MinIO + NextCloud + Collabora Online + Cloudflare Tunnel

このプロジェクトは、k3s上にMinIO、NextCloud、Collabora Onlineを構築し、Cloudflare Tunnel経由で安全にアクセスできるクラウドストレージ環境を提供します。

## 📋 目次

- [概要](#概要)
- [アーキテクチャ](#アーキテクチャ)
- [前提条件](#前提条件)
- [クイックスタート](#クイックスタート)
- [詳細なセットアップ手順](#詳細なセットアップ手順)
- [各サービスの設定](#各サービスの設定)
- [トラブルシューティング](#トラブルシューティング)
- [アンインストール](#アンインストール)

## 🎯 概要

このプロジェクトは以下のコンポーネントで構成されています：

- **MinIO**: S3互換のオブジェクトストレージ（NextCloudのバックエンドストレージ）
- **NextCloud**: ファイル共有・同期プラットフォーム
- **Collabora Online**: オンラインオフィススイート（NextCloudと統合）
- **Cloudflare Tunnel**: ゼロトラストネットワークアクセス（外部からの安全なアクセス）
- **PostgreSQL**: NextCloudのデータベース

## 🏗️ アーキテクチャ

```
Internet
   |
   | (Cloudflare Network)
   |
   v
Cloudflare Tunnel (cloudflared)
   |
   |-- nextcloud.yourdomain.com --> NextCloud (80) --> PostgreSQL (5432)
   |                                             \
   |                                              \--> MinIO (9000)
   |
   |-- collabora.yourdomain.com --> Collabora Online (9980)
   |
   \-- minio.yourdomain.com --> MinIO Console (9001)
```

**特徴:**
- Cloudflare Tunnelが外部公開のエントリーポイント
- 自動SSL/TLS証明書管理
- DDoS保護とWAF（Cloudflareが提供）
- IP制限やアクセスポリシーの設定が可能
- VPN不要で安全にアクセス可能

全てのサービスは同じ `cloud-storage` ネームスペースにデプロイされます。

## 📦 前提条件

### 必須要件

- **k3s**: Kubernetes軽量ディストリビューション
  - 最小メモリ: 4GB RAM
  - 推奨メモリ: 8GB RAM以上
  - ストレージ: 100GB以上の空き容量

- **kubectl**: Kubernetesコマンドラインツール
  - k3sインストール時に自動的に利用可能

- **Cloudflareアカウント**: 
  - https://cloudflare.com でアカウント作成（無料プランで利用可能）
  - ドメインをCloudflareに登録
  - Zero Trustアカウントのセットアップ

### 必須

- **カスタムドメイン**: Cloudflareに登録したドメイン（必須）

## 🚀 クイックスタート

### 1. リポジトリのクローン

```bash
git clone <repository-url>
cd MinIO_NextCloud_CollaboraOnline
```

### 2. Cloudflare Tunnelの設定

Cloudflareダッシュボードでトンネルを作成し、トークンを取得します。
詳細な手順は `docs/CLOUDFLARE_TUNNEL_SETUP.md` を参照してください。

```bash
# Cloudflareダッシュボードを開く
open https://dash.cloudflare.com/

# Zero Trust → Networks → Tunnels でトンネルを作成
# トンネルトークンを取得後、k8s/06-cloudflare-tunnel.yaml の TUNNEL_TOKEN を置き換え
```

### 3. デプロイの実行

```bash
# スクリプトに実行権限を付与
chmod +x deploy.sh

# デプロイを実行（sudoが必要な場合があります）
./deploy.sh
```

デプロイスクリプトは以下を自動的に行います：
- k3sの存在確認（未インストールの場合はインストール）
- Tailscale Auth Keyの確認と設定
- 全てのKubernetesマニフェストの適用
- デプロイメントの起動待機
- アクセス情報の表示

### 4. サービスへのアクセス

デプロイ完了後、以下のコマンドでローカルからアクセスできます：

```bash
# MinIO Console
kubectl port-forward -n cloud-storage svc/minio 9001:9001
# http://localhost:9001 (minioadmin / minioadmin123)

# NextCloud
kubectl port-forward -n cloud-storage svc/nextcloud 8080:80
# http://localhost:8080 (admin / admin123)

# Nginx Proxy Manager
kubectl port-forward -n cloud-storage svc/nginx-proxy-manager 8081:81
# http://localhost:8081 (admin@example.com / changeme)

# Collabora Online
kubectl port-forward -n cloud-storage svc/collabora 9980:9980
# http://localhost:9980
```

## 🔧 詳細なセットアップ手順

### ステップ1: MinIOの初期設定

1. MinIO Consoleにアクセス（http://localhost:9001）
2. 認証情報でログイン：
   - Username: `minioadmin`
   - Password: `minioadmin123`
3. バケットの作成：
   - バケット名: `nextcloud`
   - アクセス: Private

### ステップ2: Cloudflare Tunnelの設定

詳細な手順は `docs/CLOUDFLARE_TUNNEL_SETUP.md` を参照してください。

**概要:**

1. Cloudflareダッシュボードでトンネルを作成
2. Public Hostnameを設定：
   - `nextcloud.yourdomain.com` → `http://nextcloud.cloud-storage.svc.cluster.local:80`
   - `collabora.yourdomain.com` → `http://collabora.cloud-storage.svc.cluster.local:9980`
   - `minio.yourdomain.com` → `http://minio.cloud-storage.svc.cluster.local:9001`

3. トンネルトークンを取得し、`k8s/06-cloudflare-tunnel.yaml`に設定

4. アクセスポリシーの設定（オプション）：
   - Zero Trust → Access → Applications
   - 特定のユーザーやIPアドレスのみアクセスを許可

### ステップ3: NextCloudの設定

1. NextCloudにアクセス（初回アクセス時に自動セットアップ）

2. **Collabora Onlineアプリのインストール:**
   - 設定 > アプリ
   - 「Collabora Online」を検索してインストール
   - または「Nextcloud Office」をインストール

3. **Collabora Onlineサーバーの設定:**
   - 設定 > Nextcloud Office (または Collabora Online)
   - "Use your own server" を選択
   - URL: `https://collabora.yourdomain.com`
   - または内部アクセス: `http://collabora.cloud-storage.svc.cluster.local:9980`

4. **信頼されたドメインの追加:**
   ```bash
   # NextCloudのPodに入る
   kubectl exec -it -n cloud-storage <nextcloud-pod-name> -- bash
   
   # config.phpを編集
   vi /var/www/html/config/config.php
   
   # trusted_domains に追加
   'trusted_domains' => 
     array (
       0 => 'localhost',
       1 => 'nextcloud.yourdomain.com',
       2 => '*.cloud-storage.svc.cluster.local',
       3 => '*.cfargotunnel.com',  # Cloudflare Tunnel用
     ),
   ```

5. **MinIOストレージの確認:**
   - 設定 > 管理 > 追加のストレージ
   - Primary storage: Object Storage (S3)
   - 設定が正しく適用されていることを確認

6. **Cloudflareプロキシ設定の最適化:**
   - CloudflareダッシュボードでSSL/TLSモードを「Full」に設定
   - WebSocketsを有効化
   - 大きなファイルアップロード用にタイムアウトを調整

## 📊 各サービスの設定

### MinIO設定

**デフォルト認証情報:**
- Access Key: `minioadmin`
- Secret Key: `minioadmin123`

**変更方法:**
`k8s/02-minio.yaml`のSecretセクションを編集：
```yaml
stringData:
  rootUser: "your-new-user"
  rootPassword: "your-new-password"
```

**バケットポリシーの設定:**
```bash
# mc (MinIO Client) のインストール
kubectl exec -it -n cloud-storage <minio-pod> -- bash

# バケットポリシーの設定
mc alias set myminio http://localhost:9000 minioadmin minioadmin123
mc mb myminio/nextcloud
mc policy set private myminio/nextcloud
```

### NextCloud設定

**デフォルト管理者:**
- Username: `admin`
- Password: `admin123`

**重要な設定項目:**

1. **キャッシュ設定（推奨）:**
   ```bash
   kubectl exec -it -n cloud-storage <nextcloud-pod> -- bash
   
   # APCuを有効化
   apt-get update && apt-get install -y php-apcu
   
   # config.phpに追加
   'memcache.local' => '\OC\Memcache\APCu',
   ```

2. **バックグラウンドジョブ:**
   - 設定 > 管理 > 基本設定
   - Cron を選択（推奨）
   - CronJobをk8sに追加:
     ```yaml
     apiVersion: batch/v1
     kind: CronJob
     metadata:
       name: nextcloud-cron
       namespace: cloud-storage
     spec:
       schedule: "*/5 * * * *"
       jobTemplate:
         spec:
           template:
             spec:
               containers:
               - name: nextcloud-cron
                 image: nextcloud:latest
                 command: ["php", "-f", "/var/www/html/cron.php"]
               restartPolicy: OnFailure
     ```

3. **メール設定:**
   - 設定 > 管理 > 基本設定 > メールサーバー
   - SMTPサーバー情報を入力

### Collabora Online設定

**環境変数によるカスタマイズ:**

`k8s/04-collabora.yaml`のConfigMapを編集：

```yaml
data:
  domain: "nextcloud\\.yourdomain\\.com"  # エスケープ必要
  username: "admin"
  password: "secure-password"
  extra_params: "--o:ssl.enable=false --o:ssl.termination=true --o:logging.level=warning"
  dictionaries: "en_US ja zh_CN"  # 必要な言語を追加
```

**パフォーマンスチューニング:**
```yaml
env:
- name: extra_params
  value: "--o:ssl.enable=false --o:ssl.termination=true --o:child_root_path=/opt/lool/child-roots --o:mount_jail_tree=false --o:logging.level=warning --o:per_document.idle_timeout_secs=3600 --o:per_document.max_concurrency=4"
```

### Cloudflare Tunnel設定

**環境変数:**

`k8s/06-cloudflare-tunnel.yaml`で設定：

```yaml
env:
- name: TUNNEL_TOKEN
  valueFrom:
    secretKeyRef:
      name: cloudflare-tunnel-token
      key: TUNNEL_TOKEN
- name: TUNNEL_METRICS
  value: "0.0.0.0:2000"
- name: TUNNEL_LOGLEVEL
  value: "info"
```

**アクセスポリシー（Cloudflareダッシュボード）:**

Zero Trust → Access → Applications で設定：
- Email認証
- IP制限
- 国別制限
- デバイス認証（Cloudflare WARP使用時）

**パフォーマンスチューニング:**
- Cloudflareダッシュボード → Speed → Optimization
- Auto Minify有効化
- Brotli圧縮有効化
- キャッシュルールの設定

## 🔍 監視とメンテナンス

### ログの確認

```bash
# 全Podのログ
kubectl logs -n cloud-storage -l app=nextcloud

# 特定のPodのログ
kubectl logs -n cloud-storage <pod-name> -f

# 前のPodのログ（クラッシュした場合）
kubectl logs -n cloud-storage <pod-name> --previous
```

### リソース使用状況

```bash
# Pod毎のリソース使用状況
kubectl top pods -n cloud-storage

# ノードのリソース使用状況
kubectl top nodes

# PVCの使用状況
kubectl get pvc -n cloud-storage
```

### バックアップ

**MinIOデータのバックアップ:**
```bash
# mc (MinIO Client) でバックアップ
kubectl exec -it -n cloud-storage <minio-pod> -- bash
mc mirror myminio/nextcloud /backup/nextcloud-$(date +%Y%m%d)
```

**NextCloud設定のバックアップ:**
```bash
# ConfigとData
kubectl exec -n cloud-storage <nextcloud-pod> -- tar czf /tmp/nextcloud-backup.tar.gz /var/www/html/config /var/www/html/data
kubectl cp cloud-storage/<nextcloud-pod>:/tmp/nextcloud-backup.tar.gz ./nextcloud-backup.tar.gz
```

**データベースのバックアップ:**
```bash
# PostgreSQLダンプ
kubectl exec -n cloud-storage <nextcloud-db-pod> -- pg_dump -U nextcloud nextcloud > nextcloud-db-backup.sql
```

### アップデート

```bash
# イメージの更新
kubectl set image deployment/nextcloud nextcloud=nextcloud:latest -n cloud-storage

# ローリングアップデート
kubectl rollout restart deployment/nextcloud -n cloud-storage

# アップデート状況の確認
kubectl rollout status deployment/nextcloud -n cloud-storage
```

## 🐛 トラブルシューティング

### 一般的な問題

#### 1. Podが起動しない

```bash
# Pod状態の確認
kubectl get pods -n cloud-storage

# 詳細情報
kubectl describe pod <pod-name> -n cloud-storage

# イベント確認
kubectl get events -n cloud-storage --sort-by='.lastTimestamp'
```

**よくある原因:**
- PVCがバウンドされていない
- イメージのPullに失敗
- リソース不足

#### 2. NextCloudがMinIOに接続できない

```bash
# NextCloudのログ確認
kubectl logs -n cloud-storage -l app=nextcloud | grep -i "s3\|minio\|objectstore"

# MinIOの接続テスト
kubectl exec -n cloud-storage <nextcloud-pod> -- curl http://minio:9000
```

**チェックポイント:**
- MinIOのバケットが作成されているか
- 認証情報が正しいか
- ネットワークポリシーが干渉していないか

#### 3. Collabora OnlineがNextCloudと連携できない

```bash
# Collaboraのログ確認
kubectl logs -n cloud-storage -l app=collabora

# NextCloudからの接続テスト
kubectl exec -n cloud-storage <nextcloud-pod> -- curl http://collabora:9980
```

**チェックポイント:**
- domainパラメータが正しくエスケープされているか
- NextCloudの信頼されたドメインに追加されているか
- SSL設定が整合しているか

#### 4. Tailscale経由でアクセスできない

```bash
# Tailscale Podの状態確認
kubectl logs -n cloud-storage -l app=tailscale-subnet-router

# ルーティング確認
kubectl exec -n cloud-storage <tailscale-pod> -- tailscale status
kubectl exec -n cloud-storage <tailscale-pod> -- tailscale netcheck
```

**チェックポイント:**
- Auth Keyが有効か
- Subnet routesが承認されているか
- ファイアウォール設定

#### 5. PVC が Pending 状態

```bash
# PVC状態確認
kubectl get pvc -n cloud-storage
kubectl describe pvc <pvc-name> -n cloud-storage

# StorageClass確認
kubectl get storageclass
```

**解決方法:**
```bash
# デフォルトのlocal-pathストレージクラスを使用
kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

### パフォーマンスチューニング

#### NextCloudが遅い場合

1. **PHPメモリ制限の増加:**
```yaml
# k8s/03-nextcloud.yaml
env:
- name: PHP_MEMORY_LIMIT
  value: "512M"
- name: PHP_UPLOAD_LIMIT
  value: "10G"
```

2. **レプリカ数の増加:**
```yaml
# k8s/03-nextcloud.yaml
spec:
  replicas: 2  # 水平スケーリング
```

3. **リソース制限の調整:**
```yaml
resources:
  requests:
    memory: "1Gi"
    cpu: "500m"
  limits:
    memory: "4Gi"
    cpu: "2000m"
```

#### MinIOのパフォーマンス改善

```yaml
# k8s/02-minio.yaml
args:
- server
- /data
- --console-address
- ":9001"
env:
- name: MINIO_CACHE
  value: "on"
- name: MINIO_CACHE_DRIVES
  value: "/cache"
- name: MINIO_CACHE_QUOTA
  value: "80"
```

## 🗑️ アンインストール

### クリーンアップスクリプトの使用

```bash
# スクリプトに実行権限を付与
chmod +x cleanup.sh

# クリーンアップ実行
./cleanup.sh
```

### 手動でのアンインストール

```bash
# namespace削除（全リソースが削除される）
kubectl delete namespace cloud-storage

# PVの確認と削除（必要に応じて）
kubectl get pv
kubectl delete pv <pv-name>
```

## 📚 参考リンク

- [MinIO Documentation](https://min.io/docs/minio/kubernetes/upstream/)
- [NextCloud Documentation](https://docs.nextcloud.com/)
- [Collabora Online Documentation](https://sdk.collaboraonline.com/)
- [Cloudflare Tunnel Documentation](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/)
- [Cloudflare Zero Trust](https://developers.cloudflare.com/cloudflare-one/)
- [k3s Documentation](https://docs.k3s.io/)

## 🤝 貢献

プロジェクトへの貢献を歓迎します！

## 📄 ライセンス

MIT License

## 🔐 セキュリティに関する注意

- 本番環境では必ず全てのデフォルトパスワードを変更してください
- Cloudflare Tunnelは自動的にSSL/TLS証明書を管理します
- 定期的なバックアップを実施してください
- セキュリティアップデートを適用してください
- Cloudflare Zero Trustアクセスポリシーを適切に設定してください
- Cloudflare WAFでセキュリティルールを設定することを推奨

## ⚙️ カスタマイズ

### ストレージ容量の変更

各PVCの容量は以下のファイルで変更できます：

- MinIO: `k8s/02-minio.yaml` (デフォルト: 50Gi)
- NextCloud: `k8s/03-nextcloud.yaml` (デフォルト: 30Gi)
- NextCloud DB: `k8s/03-nextcloud.yaml` (デフォルト: 10Gi)
- NPM: `k8s/05-nginx-proxy-manager.yaml` (デフォルト: 5Gi)

### レプリカ数の変更

高可用性が必要な場合、レプリカ数を増やせます：

```yaml
spec:
  replicas: 3  # 3つのレプリカ
```

**注意**: データベースとMinIOは単一レプリカを推奨（StatefulSetへの変更が必要）

### ネームスペースの変更

全ての`.yaml`ファイル内の`cloud-storage`を別の名前に変更してください。

---

**作成日**: 2025年11月5日
**更新日**: 2025年11月5日
