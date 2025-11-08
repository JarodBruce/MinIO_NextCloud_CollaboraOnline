# MinIO + NextCloud + Collabora Online on k3s with Cloudflare Tunnel

Cloudflare Tunnelを使用してk3s上にセキュアなクラウドストレージ環境を構築します。VPNやポート開放不要で、世界中どこからでも安全にアクセスできます。

## 📋 目次

- [概要](#概要)
- [アーキテクチャ](#アーキテクチャ)
- [前提条件](#前提条件)
- [クイックスタート](#クイックスタート)
- [Cloudflare Tunnelのセットアップ](#cloudflare-tunnelのセットアップ)
- [各サービスの設定](#各サービスの設定)
- [運用とメンテナンス](#運用とメンテナンス)
- [トラブルシューティング](#トラブルシューティング)
- [アンインストール](#アンインストール)

## 🎯 概要

このプロジェクトは、以下のコンポーネントで構成される完全なクラウドストレージソリューションです：

- **MinIO** - S3互換オブジェクトストレージ（NextCloud・Immichのバックエンド）
- **NextCloud** - Webベースのファイル共有・同期プラットフォーム
- **Collabora Online** - オンラインOfficeスイート（Word/Excel/PowerPoint編集）
- **Immich** - セルフホスト型写真・動画管理プラットフォーム（Google Photos代替）
- **PostgreSQL** - NextCloud・Immichデータベース
- **Redis** - Immichキャッシュ
- **Cloudflare Tunnel** - セキュアな外部アクセス（ゼロトラストアーキテクチャ）

## 🏗️ アーキテクチャ

```
                                   Internet
                                      |
                        ┌─────────────┴─────────────┐
                        │   Cloudflare Network     │
                        │  (DDoS Protection, WAF)   │
                        └─────────────┬─────────────┘
                                      |
                        ┌─────────────┴─────────────┐
                        │  Cloudflare Tunnel        │
                        │    (cloudflared)          │
                        └─────────────┬─────────────┘
                                      |
                    ┌─────────────────┼─────────────────┐
                    |                 |                 |
        nextcloud.example.com  collabora.example.com  minio.example.com
                    |                 |                 |
            ┌───────▼────────┐  ┌────▼─────┐  ┌───────▼────────┐
            │   NextCloud    │  │Collabora │  │ MinIO Console  │
            │   Service      │  │  Online  │  │   (9001)       │
            │   (Port 80)    │  │  (9980)  │  └────────────────┘
            └───────┬────────┘  └──────────┘
                    |
        ┌───────────┴────────────┐
        |                        |
   ┌────▼──────┐          ┌─────▼────┐
   │PostgreSQL │          │  MinIO   │
   │  Database │          │ Storage  │
   │  (5432)   │          │  (9000)  │
   └───────────┘          └──────────┘

全て cloud-storage namespace で実行
```

**主な特徴:**

✅ **ゼロトラストセキュリティ** - ファイアウォール設定やポート開放不要  
✅ **自動SSL/TLS** - 証明書の取得・更新を自動管理  
✅ **DDoS保護** - Cloudflareの強力なDDoS対策  
✅ **グローバルCDN** - 世界中のエッジサーバーで高速アクセス  
✅ **アクセス制御** - IP制限、Email認証、MFAなど柔軟な認証  
✅ **簡単デプロイ** - スクリプト一発でk3s環境を構築

## 📦 前提条件

### システム要件

| 項目 | 最小スペック | 推奨スペック |
|------|-------------|-------------|
| CPU | 2コア | 4コア以上 |
| メモリ | 4GB RAM | 8GB RAM以上 |
| ストレージ | 50GB | 100GB以上 |
| OS | Linux (Ubuntu/Debian/CentOS等) | Ubuntu 22.04 LTS |

### 必要なもの

1. **Cloudflareアカウント** (無料プランでOK)
   - https://cloudflare.com でアカウント作成
   - ドメインをCloudflareに登録（必須）
   - Zero Trustダッシュボードへのアクセス

2. **独自ドメイン**
   - Cloudflareで管理するドメイン
   - 例: `example.com`, `mydomain.net` など

3. **サーバー環境**
   - Linux サーバー（物理/VM/クラウド）
   - Root権限またはsudo権限
   - インターネット接続

### 事前にインストールされるもの

以下はデプロイスクリプトが自動でインストールします：

- **k3s** - 軽量Kubernetes
- **kubectl** - Kubernetesコマンドラインツール
- 必要なDockerイメージ（MinIO、NextCloud、Collabora、PostgreSQL、cloudflared）

## 🚀 クイックスタート

### ステップ1: リポジトリのクローン

```bash
git clone https://github.com/JarodBruce/MinIO_NextCloud_CollaboraOnline.git
cd MinIO_NextCloud_CollaboraOnline
```

### ステップ2: 環境変数の設定

1. **`.env`ファイルを作成**
   ```bash
   # .env.exampleをコピー
   cp .env.example .env
   ```

2. **Cloudflareダッシュボードにログイン**
   ```bash
   # ブラウザで以下のURLを開く
   https://one.dash.cloudflare.com/
   ```

3. **トンネルを作成**
   - `Zero Trust` > `Networks` > `Tunnels` に移動
   - `Create a tunnel` をクリック
   - トンネル名を入力（例: `k3s-cloud-storage`）
   - `Cloudflared` を選択して `Save tunnel` をクリック

4. **トンネルトークンをコピー**
   - トンネル作成後に表示される **トークン** をコピー
   - または、`Install and run a connector` セクションのDocker実行コマンドから `--token` の後の文字列をコピー

5. **トークンを`.env`ファイルに設定**
   ```bash
   # .envファイルを編集
   nano .env
   
   # TUNNEL_TOKENの値を実際のトークンに置き換え
   TUNNEL_TOKEN=eyJhIjoiXXXXXXXXXXX...
   ```

   **重要**: `.env`ファイルは`.gitignore`に含まれているため、GitHubにプッシュされません。

### ステップ3: Public Hostnameの設定

Cloudflareダッシュボードのトンネル設定で、以下のPublic Hostnameを追加：

| Public Hostname | Service | Type |
|----------------|---------|------|
| `nextcloud.yourdomain.com` | `nextcloud.cloud-storage.svc.cluster.local:80` | HTTP |
| `collabora.yourdomain.com` | `collabora.cloud-storage.svc.cluster.local:9980` | HTTP |
| `minio.yourdomain.com` | `minio.cloud-storage.svc.cluster.local:9001` | HTTP |
| `immich.yourdomain.com` | `immich-server.cloud-storage.svc.cluster.local:3001` | HTTP |

**注意**: `yourdomain.com` を実際のドメインに置き換えてください。

### ステップ4: デプロイの実行

**重要**: デプロイ前に`.env`ファイルに`TUNNEL_TOKEN`が設定されていることを確認してください。

```bash
# デプロイスクリプトに実行権限を付与
chmod +x deploy.sh status.sh cleanup.sh port-forward.sh

# デプロイを実行
./deploy.sh
```

デプロイスクリプトは自動的に：
- ✅ k3sのインストール（未インストールの場合）
- ✅ namespaceの作成
- ✅ ストレージのプロビジョニング
- ✅ 全サービスのデプロイ
- ✅ Cloudflare Tunnelの起動
- ✅ サービスの起動待機

デプロイには5〜10分程度かかります。

### ステップ5: サービスへのアクセス

デプロイが完了したら、設定したドメインでアクセスできます：

#### インターネット経由（Cloudflare Tunnel）

- **NextCloud**: `https://nextcloud.yourdomain.com`
  - ユーザー名: `admin`
  - パスワード: `admin123`
  - 初回セットアップが自動実行されます
  - 管理者アカウントは自動作成されます

- **Collabora Online**: `https://collabora.yourdomain.com`
  - NextCloudから自動的にアクセスされます

- **MinIO Console**: `https://minio.yourdomain.com`
  - ユーザー名: `minioadmin`
  - パスワード: `minioadmin123`

- **Immich**: `https://immich.yourdomain.com`
  - 初回アクセス時に管理者アカウントを作成します
  - 写真・動画を自動的にMinIO(S3)に保存します

#### ローカルアクセス（ポートフォワード）

開発やデバッグ用にローカルからもアクセスできます：

```bash
# ポートフォワードスクリプトを実行
./port-forward.sh
```

または個別に：

```bash
# MinIO Console
kubectl port-forward -n cloud-storage svc/minio 9001:9001
# → http://localhost:9001

# NextCloud
kubectl port-forward -n cloud-storage svc/nextcloud 8080:80
# → http://localhost:8080

# Collabora Online
kubectl port-forward -n cloud-storage svc/collabora 9980:9980
# → http://localhost:9980
```

## 🔧 Cloudflare Tunnelのセットアップ

### 完全なセットアップガイド

詳細な手順は `docs/CLOUDFLARE_TUNNEL_SETUP.md` を参照してください。ここでは概要を説明します。

### 1. Cloudflare Zero Trustのセットアップ

```bash
# ブラウザでCloudflare Zero Trustダッシュボードを開く
https://one.dash.cloudflare.com/
```

初回の場合、Zero Trustアカウントの作成が必要です（無料プランで十分）。

### 2. トンネルの作成

1. `Networks` → `Tunnels` → `Create a tunnel`
2. トンネル名を入力（例: `k3s-cloud-storage`）
3. コネクタータイプ: `Cloudflared` を選択
4. `Save tunnel` をクリック

### 3. トンネルトークンの取得と設定

トンネル作成後に表示される画面で：

```bash
# Docker実行コマンドの例が表示されます
docker run cloudflare/cloudflared:latest tunnel --no-autoupdate run --token eyJhIjoiXXXXXXXXXXX...

# この --token の後の長い文字列がトンネルトークンです
```

トークンを `k8s/06-cloudflare-tunnel.yaml` に設定：

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: cloudflare-tunnel-token
  namespace: cloud-storage
type: Opaque
stringData:
  TUNNEL_TOKEN: "eyJhIjoiXXXXXXXXXXX..."  # ここに実際のトークンをペースト
```

### 4. Public Hostnameの設定

Cloudflareダッシュボードで、トンネルの `Public Hostname` タブを開き、以下を追加：

#### NextCloud

- **Subdomain**: `nextcloud`
- **Domain**: `yourdomain.com`
- **Service**: 
  - Type: `HTTP`
  - URL: `nextcloud.cloud-storage.svc.cluster.local:80`

#### Collabora Online

- **Subdomain**: `collabora`
- **Domain**: `yourdomain.com`
- **Service**: 
  - Type: `HTTP`
  - URL: `collabora.cloud-storage.svc.cluster.local:9980`

#### MinIO Console

- **Subdomain**: `minio`
- **Domain**: `yourdomain.com`
- **Service**: 
  - Type: `HTTP`
  - URL: `minio.cloud-storage.svc.cluster.local:9001`

#### Immich

- **Subdomain**: `immich`
- **Domain**: `yourdomain.com`
- **Service**: 
  - Type: `HTTP`
  - URL: `immich-server.cloud-storage.svc.cluster.local:3001`

### 5. 追加設定（オプション）

#### SSL/TLS設定の最適化

Cloudflareダッシュボード → `SSL/TLS` で：

- SSL/TLSモード: **Full** に設定
- Edge Certificates: 自動管理（デフォルト）
- Always Use HTTPS: 有効化

#### パフォーマンス設定

`Speed` → `Optimization` で：

- Auto Minify: HTML, CSS, JS を有効化
- Brotli: 有効化
- HTTP/2: 有効化（デフォルト）
- HTTP/3 (QUIC): 有効化

#### アクセスポリシー（セキュリティ強化）

`Zero Trust` → `Access` → `Applications` で各サービスにアクセス制御を追加：

**例: NextCloudへのアクセスを特定のEmailのみに制限**

1. `Add an application` をクリック
2. Application type: `Self-hosted`
3. Application domain: `nextcloud.yourdomain.com`
4. Policy設定:
   - Policy name: `Allow specific users`
   - Action: `Allow`
   - Include: `Emails` → 許可するメールアドレスを追加

**例: MinIO ConsoleへのアクセスをIPアドレスで制限**

1. Application domain: `minio.yourdomain.com`
2. Policy設定:
   - Include: `IP ranges` → `192.168.1.0/24` など

### 6. Cloudflare Access認証の設定（推奨）

Cloudflare Accessを使用すると、全てのサービスに対して統一された認証レイヤーを追加できます。

#### Cloudflare Accessの有効化手順

1. **Cloudflare Zero Trustダッシュボードにアクセス**
   ```
   https://one.dash.cloudflare.com/
   ```

2. **Access Applicationの作成**
   
   **NextCloud用:**
   - `Access` → `Applications` → `Add an application`
   - Application type: `Self-hosted`
   - Application name: `NextCloud`
   - Application domain: `nextcloud.yourdomain.com`
   - Session duration: `24 hours`（お好みで調整）
   
   **ポリシー設定:**
   - Policy name: `Allow authorized users`
   - Action: `Allow`
   - Include: 以下のいずれかを選択
     - `Emails`: 特定のメールアドレス（例: admin@example.com）
     - `Email domains`: ドメイン全体（例: @yourcompany.com）
     - `Everyone`: 全員（推奨しません）
     - `IP ranges`: 特定のIPアドレス範囲
   - Session duration: `24 hours`

   **Immich用:**
   - Application name: `Immich`
   - Application domain: `immich.yourdomain.com`
   - 同様のポリシーを設定

   **Collabora用:**
   - Application name: `Collabora Online`
   - Application domain: `collabora.yourdomain.com`
   - 同様のポリシーを設定

   **MinIO Console用:**
   - Application name: `MinIO Console`
   - Application domain: `minio.yourdomain.com`
   - より厳格なポリシー（管理者のみ）を推奨

3. **Cloudflare Access設定の確認**
   
   `k8s/07-cloudflare-access.yaml`を編集して、実際の設定値に更新：
   
   ```yaml
   data:
     CLOUDFLARE_ACCESS_TEAM_DOMAIN: "your-team.cloudflareaccess.com"
     NEXTCLOUD_POLICY_AUD: "your-actual-nextcloud-aud-tag"
     IMMICH_POLICY_AUD: "your-actual-immich-aud-tag"
     COLLABORA_POLICY_AUD: "your-actual-collabora-aud-tag"
   ```
   
   **Audience Tag (AUD)の取得方法:**
   - Cloudflare Dashboard → Access → Applications
   - 各アプリケーションをクリック → `Overview`タブ
   - `Application Audience (AUD) Tag`をコピー

4. **設定の適用**
   
   ```bash
   kubectl apply -f k8s/07-cloudflare-access.yaml
   ```

5. **動作確認**
   
   - ブラウザで `https://nextcloud.yourdomain.com` にアクセス
   - Cloudflare Accessのログイン画面が表示されます
   - 設定したポリシーに従って認証（Email、OTP、SSO等）
   - 認証成功後、NextCloudにリダイレクトされます

#### Cloudflare Accessの利点

✅ **統一された認証**: 全サービスで同じ認証フローを使用  
✅ **多要素認証(MFA)**: Google Authenticatorなどと統合可能  
✅ **SSO対応**: Google、Azure AD、Okta等と連携  
✅ **詳細なログ**: アクセスログと監査証跡  
✅ **デバイス認証**: 特定のデバイスからのみアクセス許可  
✅ **地理的制限**: 特定の国からのアクセスをブロック

#### トラブルシューティング

**認証ループが発生する場合:**

NextCloudの`config.php`に以下を追加：
```bash
kubectl exec -it -n cloud-storage deployment/nextcloud -- bash
vi /var/www/html/config/config.php

# 以下を追加
'overwriteprotocol' => 'https',
'overwrite.cli.url' => 'https://nextcloud.yourdomain.com',
'trusted_proxies' => array(
  '10.0.0.0/8',
  '173.245.48.0/20',
  '103.21.244.0/22',
  // ... Cloudflare IPレンジ全て
),
```

**Collaboraが動作しない場合:**

Collaboraは通常、NextCloudを経由してアクセスするため、Cloudflare AccessのポリシーでNextCloudドメインを信頼する設定が必要です：

- Collabora Applicationの設定で`Bypass`ポリシーを追加
- Include: `IP ranges` → NextCloudのPod CIDR（例: `10.42.0.0/16`）

## ⚙️ 各サービスの設定

### NextCloudの初期設定

NextCloudに初めてアクセスすると、自動セットアップが実行されます。

#### 1. Collabora Onlineの統合

NextCloudにログイン後：

1. **アプリのインストール**
   - 右上のアイコン → `アプリ`
   - `Office & text` カテゴリ
   - `Nextcloud Office` または `Collabora Online` を検索してインストール

2. **Collaboraサーバーの設定**
   - `設定` → `管理` → `Nextcloud Office`
   - `Use your own server` を選択
   - サーバーURL: `https://collabora.yourdomain.com`
   - `保存` をクリック

3. **動作確認**
   - ファイルアプリで `.docx`, `.xlsx`, `.pptx` ファイルをアップロード
   - クリックして編集できることを確認

#### 2. 信頼されたドメインの追加

Cloudflare Tunnel経由でアクセスする場合、信頼されたドメインを追加：

```bash
# NextCloudのPod名を確認
kubectl get pods -n cloud-storage -l app=nextcloud

# Podに入る
kubectl exec -it -n cloud-storage <nextcloud-pod-name> -- bash

# config.phpを編集
vi /var/www/html/config/config.php
```

以下を追加：

```php
'trusted_domains' => 
  array (
    0 => 'localhost',
    1 => 'nextcloud.yourdomain.com',  # 実際のドメインに置き換え
    2 => '*.cloud-storage.svc.cluster.local',
  ),
'trusted_proxies' => array('10.0.0.0/8'),  # k8s内部ネットワーク
'overwriteprotocol' => 'https',  # Cloudflare Tunnel経由はHTTPS
'overwrite.cli.url' => 'https://nextcloud.yourdomain.com',
```

#### 3. パフォーマンスの最適化

**APCuキャッシュの有効化**（推奨）:

```bash
kubectl exec -it -n cloud-storage <nextcloud-pod-name> -- bash

# APCuのインストール
apt-get update && apt-get install -y php-apcu

# config.phpに追加
echo "'memcache.local' => '\OC\Memcache\APCu'," >> /var/www/html/config/config.php
```

**Cronジョブの設定**:

NextCloudの管理画面で：
- `設定` → `管理` → `基本設定`
- バックグラウンドジョブ: `Cron` を選択

### MinIOの設定

#### デフォルト認証情報

- **Access Key**: `minioadmin`
- **Secret Key**: `minioadmin123`

#### 本番環境での認証情報変更（推奨）

`k8s/02-minio.yaml` を編集：

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: minio-secret
  namespace: cloud-storage
type: Opaque
stringData:
  rootUser: "your-secure-username"      # 変更する
  rootPassword: "your-secure-password"  # 変更する
```

変更後、再デプロイ：

```bash
kubectl apply -f k8s/02-minio.yaml
kubectl rollout restart deployment/minio -n cloud-storage
```

#### バケットの確認

MinIO Consoleにアクセスして、`nextcloud` バケットが作成されていることを確認。

### Collabora Onlineの設定

#### ドメイン設定

`k8s/04-collabora.yaml` でNextCloudのドメインを指定：

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: collabora-config
  namespace: cloud-storage
data:
  domain: "nextcloud\\.yourdomain\\.com"  # バックスラッシュでエスケープ
  username: "admin"
  password: "collabora-admin-password"  # 変更推奨
  extra_params: "--o:ssl.enable=false --o:ssl.termination=true"
```

**複数ドメインを許可する場合**:

```yaml
domain: "nextcloud\\.yourdomain\\.com|nextcloud\\.otherdomain\\.com"
```

#### 日本語サポート

日本語フォントと辞書を追加：

```yaml
env:
- name: dictionaries
  value: "en_US ja"
```

### Immichの設定

Immichは自己ホスト型の写真・動画管理プラットフォームで、Google Photosの代替として人気です。

#### 初期セットアップ

1. **Immichへアクセス**
   - `https://immich.yourdomain.com` を開く

2. **管理者アカウントの作成**
   - メールアドレスとパスワードを入力
   - 「サインアップ」をクリック

3. **MinIOバケットの作成**
   
   Immichが使用するS3バケットを作成します：
   
   ```bash
   # MinIO Podに入る
   kubectl exec -it -n cloud-storage deployment/minio -- sh
   
   # MinIO Clientを設定
   mc alias set local http://localhost:9000 minioadmin minioadmin123
   
   # immichバケットを作成
   mc mb local/immich
   
   # バケットポリシーを設定（プライベート）
   mc anonymous set none local/immich
   ```

4. **ストレージ設定の確認**
   
   Immichは自動的にMinIO(S3)を使用するように設定されています：
   - エンドポイント: `http://minio:9000`
   - バケット名: `immich`
   - リージョン: `us-east-1`

#### モバイルアプリの設定

1. **アプリのインストール**
   - iOS: [App Store](https://apps.apple.com/app/immich/id1613945652)
   - Android: [Google Play](https://play.google.com/store/apps/details?id=app.alextran.immich)

2. **サーバー接続**
   - サーバーURL: `https://immich.yourdomain.com`
   - ログイン情報を入力

3. **自動バックアップの設定**
   - アプリ設定で「自動バックアップ」を有効化
   - バックアップするアルバムを選択

#### 機能

- ✅ **顔認識** - 機械学習による自動顔認識
- ✅ **オブジェクト検出** - 写真内のオブジェクトを自動タグ付け
- ✅ **位置情報** - GPSデータから地図上に表示
- ✅ **アルバム共有** - 家族や友人とアルバムを共有
- ✅ **ライブ写真** - iOSのLive Photosをサポート
- ✅ **RAW画像** - プロ向けRAWフォーマットに対応
- ✅ **動画変換** - 効率的なストリーミング用に変換

#### パフォーマンスの最適化

**Machine Learningリソースの調整:**

大量の写真を処理する場合、ML用のリソースを増やします：

```yaml
# k8s/05-immich.yaml
resources:
  requests:
    memory: "2Gi"
    cpu: "1000m"
  limits:
    memory: "8Gi"
    cpu: "4000m"
```

**Redis接続の確認:**

```bash
# Redisへの接続テスト
kubectl exec -n cloud-storage deployment/immich-server -- \
  redis-cli -h immich-redis ping
```

#### バックアップ

**データベースバックアップ:**

```bash
# Immich PostgreSQLをバックアップ
kubectl exec -n cloud-storage deployment/immich-postgres -- \
  pg_dump -U immich immich > immich-db-$(date +%Y%m%d).sql

# 復元
cat immich-db-20250115.sql | \
  kubectl exec -i -n cloud-storage deployment/immich-postgres -- \
  psql -U immich immich
```

**写真・動画のバックアップ:**

すべてのメディアはMinIOに保存されているため、MinIOのバックアップで対応：

```bash
# MinIO Clientでバックアップ
kubectl exec -n cloud-storage deployment/minio -- \
  mc mirror local/immich /backup/immich-$(date +%Y%m%d)
```

#### トラブルシューティング

**機械学習が動作しない:**

```bash
# Machine Learningのログを確認
kubectl logs -n cloud-storage -l app=immich-machine-learning

# Podの再起動
kubectl rollout restart deployment/immich-machine-learning -n cloud-storage
```

**写真がアップロードできない:**

```bash
# Immich Serverのログを確認
kubectl logs -n cloud-storage -l app=immich-server

# MinIOへの接続を確認
kubectl exec -n cloud-storage deployment/immich-server -- \
  curl -v http://minio:9000
```

**データベース接続エラー:**

```bash
# PostgreSQLの状態確認
kubectl logs -n cloud-storage -l app=immich-postgres

# 接続テスト
kubectl exec -n cloud-storage deployment/immich-server -- \
  nc -zv immich-postgres 5432
```

### Cloudflare Tunnelの管理

#### トンネルの状態確認

```bash
# cloudflaredのログを確認
kubectl logs -n cloud-storage -l app=cloudflare-tunnel -f

# トンネルの接続状態
# Cloudflareダッシュボード → Networks → Tunnels で確認
```

#### トンネルの再起動

```bash
kubectl rollout restart deployment/cloudflare-tunnel -n cloud-storage
```

#### メトリクスの確認

cloudflaredはメトリクスエンドポイントを公開しています：

```bash
# メトリクスポートをフォワード
kubectl port-forward -n cloud-storage svc/cloudflare-tunnel 2000:2000

# メトリクスにアクセス
curl http://localhost:2000/metrics
```

## 🔍 運用とメンテナンス

### ステータスの確認

便利なスクリプトを用意しています：

```bash
# 全サービスの状態を確認
./status.sh
```

または手動で：

```bash
# Pod一覧
kubectl get pods -n cloud-storage

# サービス一覧
kubectl get svc -n cloud-storage

# PVC一覧
kubectl get pvc -n cloud-storage
```

### ログの確認

#### 各サービスのログ

```bash
# NextCloud
kubectl logs -n cloud-storage -l app=nextcloud -f

# MinIO
kubectl logs -n cloud-storage -l app=minio -f

# Collabora Online
kubectl logs -n cloud-storage -l app=collabora -f

# Cloudflare Tunnel
kubectl logs -n cloud-storage -l app=cloudflare-tunnel -f

# PostgreSQL
kubectl logs -n cloud-storage -l app=nextcloud-db -f
```

#### 問題発生時のログ確認

```bash
# Pod名を確認
kubectl get pods -n cloud-storage

# 特定のPodのログ（リアルタイム）
kubectl logs -n cloud-storage <pod-name> -f

# クラッシュしたPodの前回のログ
kubectl logs -n cloud-storage <pod-name> --previous
```

### リソース監視

```bash
# Podのリソース使用状況
kubectl top pods -n cloud-storage

# ノードのリソース使用状況
kubectl top nodes

# PVCストレージ使用状況
kubectl get pvc -n cloud-storage
```

出力例：
```
NAME                      STATUS   VOLUME   CAPACITY   ACCESS MODES
minio-storage             Bound    pv-xxx   50Gi       RWO
nextcloud-storage         Bound    pv-yyy   30Gi       RWO
nextcloud-db-storage      Bound    pv-zzz   10Gi       RWO
```

### バックアップ戦略

#### 1. データベースバックアップ（重要）

```bash
# PostgreSQLをバックアップ
kubectl exec -n cloud-storage deployment/nextcloud-db -- \
  pg_dump -U nextcloud nextcloud > nextcloud-db-$(date +%Y%m%d).sql

# バックアップの復元
cat nextcloud-db-20250115.sql | \
  kubectl exec -i -n cloud-storage deployment/nextcloud-db -- \
  psql -U nextcloud nextcloud
```

#### 2. MinIOデータバックアップ

```bash
# MinIOのPodに入る
kubectl exec -it -n cloud-storage deployment/minio -- sh

# mc (MinIO Client) でバックアップ
mc alias set local http://localhost:9000 minioadmin minioadmin123
mc mirror local/nextcloud /backup/nextcloud-$(date +%Y%m%d)
```

#### 3. NextCloud設定バックアップ

```bash
# 設定ファイルをバックアップ
kubectl exec -n cloud-storage deployment/nextcloud -- \
  tar czf - /var/www/html/config > nextcloud-config-$(date +%Y%m%d).tar.gz

# 復元
kubectl cp nextcloud-config-20250115.tar.gz \
  cloud-storage/nextcloud-xxx:/tmp/
kubectl exec -n cloud-storage deployment/nextcloud -- \
  tar xzf /tmp/nextcloud-config-20250115.tar.gz -C /
```

#### 4. 自動バックアップ（CronJob）

`k8s/backup-cronjob.yaml` を作成：

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: nextcloud-backup
  namespace: cloud-storage
spec:
  schedule: "0 2 * * *"  # 毎日午前2時
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: backup
            image: postgres:15
            command:
            - /bin/sh
            - -c
            - pg_dump -h nextcloud-db -U nextcloud nextcloud > /backup/nextcloud-$(date +\%Y\%m\%d).sql
            env:
            - name: PGPASSWORD
              value: "nextcloud123"
            volumeMounts:
            - name: backup
              mountPath: /backup
          volumes:
          - name: backup
            hostPath:
              path: /backup/nextcloud
          restartPolicy: OnFailure
```

### アップデート

#### イメージの更新

```bash
# NextCloudを最新版に更新
kubectl set image deployment/nextcloud \
  nextcloud=nextcloud:latest -n cloud-storage

# 特定のバージョンを指定
kubectl set image deployment/nextcloud \
  nextcloud=nextcloud:28 -n cloud-storage
```

#### ローリングアップデート

```bash
# NextCloud
kubectl rollout restart deployment/nextcloud -n cloud-storage

# MinIO
kubectl rollout restart deployment/minio -n cloud-storage

# Collabora
kubectl rollout restart deployment/collabora -n cloud-storage

# Cloudflare Tunnel
kubectl rollout restart deployment/cloudflare-tunnel -n cloud-storage
```

#### アップデート状況の確認

```bash
# ローリングアップデートの進行状況
kubectl rollout status deployment/nextcloud -n cloud-storage

# 履歴確認
kubectl rollout history deployment/nextcloud -n cloud-storage

# ロールバック
kubectl rollout undo deployment/nextcloud -n cloud-storage
```

### スケーリング

#### 水平スケーリング（レプリカ数の変更）

```bash
# NextCloudのレプリカ数を増やす
kubectl scale deployment/nextcloud --replicas=3 -n cloud-storage

# Collaboraのレプリカ数を増やす
kubectl scale deployment/collabora --replicas=2 -n cloud-storage
```

**注意**: MinIOとPostgreSQLは単一レプリカ推奨（StatefulSetへの変更が必要）

#### 垂直スケーリング（リソース制限の変更）

`k8s/03-nextcloud.yaml` を編集：

```yaml
resources:
  requests:
    memory: "2Gi"    # 増やす
    cpu: "1000m"     # 増やす
  limits:
    memory: "4Gi"    # 増やす
    cpu: "2000m"     # 増やす
```

再適用：

```bash
kubectl apply -f k8s/03-nextcloud.yaml
```

## 🐛 トラブルシューティング

### よくある問題と解決方法

#### 1. Podが起動しない（Pending/CrashLoopBackOff）

**状態確認:**
```bash
# Pod一覧を確認
kubectl get pods -n cloud-storage

# 詳細情報を確認
kubectl describe pod <pod-name> -n cloud-storage

# イベントログを確認
kubectl get events -n cloud-storage --sort-by='.lastTimestamp'
```

**よくある原因と対処:**

| 症状 | 原因 | 解決方法 |
|------|------|---------|
| Pending状態 | PVCがBoundされていない | `kubectl get pvc -n cloud-storage` で確認。StorageClassを設定 |
| ImagePullBackOff | イメージのダウンロード失敗 | インターネット接続を確認。プロキシ設定が必要な場合は設定 |
| CrashLoopBackOff | コンテナ起動失敗 | `kubectl logs -n cloud-storage <pod-name>` でログ確認 |
| Insufficient resources | リソース不足 | `kubectl top nodes` でリソース確認。不要なPodを削除 |

#### 2. Cloudflare Tunnel経由でアクセスできない

**チェックリスト:**

```bash
# cloudflaredのログを確認
kubectl logs -n cloud-storage -l app=cloudflare-tunnel -f
```

確認ポイント：

- [ ] トンネルトークンが正しく設定されているか
- [ ] Cloudflareダッシュボードでトンネルが「HEALTHY」状態か
- [ ] Public Hostnameが正しく設定されているか
- [ ] DNS設定が反映されているか（最大48時間かかる場合あり）

**トンネル状態の確認:**

Cloudflareダッシュボード → `Zero Trust` → `Networks` → `Tunnels` で確認

**よくあるエラー:**

```
Unable to reach the origin service
```
→ Service URLが間違っている。`service-name.namespace.svc.cluster.local` の形式を確認

```
Authentication error
```
→ トンネルトークンが間違っている。`k8s/06-cloudflare-tunnel.yaml` を確認

#### 3. NextCloudにアクセスできない

**診断コマンド:**

```bash
# NextCloudのログ確認
kubectl logs -n cloud-storage -l app=nextcloud --tail=100

# NextCloud Podの状態確認
kubectl get pods -n cloud-storage -l app=nextcloud

# データベース接続テスト
kubectl exec -n cloud-storage deployment/nextcloud -- \
  nc -zv nextcloud-db 5432
```

**よくある問題:**

- **「信頼されたドメインではありません」エラー**
  ```bash
  kubectl exec -it -n cloud-storage deployment/nextcloud -- bash
  vi /var/www/html/config/config.php
  # trusted_domains に使用するドメインを追加
  ```

- **データベース接続エラー**
  ```bash
  # データベースの状態確認
  kubectl logs -n cloud-storage -l app=nextcloud-db
  ```

- **ストレージ容量不足**
  ```bash
  # PVCの容量確認
  kubectl get pvc -n cloud-storage
  kubectl describe pvc nextcloud-storage -n cloud-storage
  ```

#### 4. Collabora OnlineがNextCloudと連携しない

**チェックポイント:**

```bash
# Collaboraのログ確認
kubectl logs -n cloud-storage -l app=collabora --tail=50

# NextCloudからCollaboraへの接続テスト
kubectl exec -n cloud-storage deployment/nextcloud -- \
  curl -v http://collabora.cloud-storage.svc.cluster.local:9980
```

**設定確認:**

1. **domain設定が正しいか確認**
   ```bash
   kubectl get configmap collabora-config -n cloud-storage -o yaml
   ```
   ドメインが正しくエスケープされているか確認（`nextcloud\\.yourdomain\\.com`）

2. **NextCloudのCollabora設定**
   - NextCloud管理画面 → `設定` → `Nextcloud Office`
   - サーバーURL: `https://collabora.yourdomain.com`

3. **WOPIアクセス確認**
   Collaboraログで以下のエラーがないか確認：
   ```
   WOPI::CheckFileInfo failed
   ```

#### 5. MinIO接続エラー

**診断:**

```bash
# MinIOのログ確認
kubectl logs -n cloud-storage -l app=minio

# MinIOへの接続テスト
kubectl exec -n cloud-storage deployment/nextcloud -- \
  curl -v http://minio.cloud-storage.svc.cluster.local:9000

# バケット確認
kubectl exec -it -n cloud-storage deployment/minio -- sh
mc alias set local http://localhost:9000 minioadmin minioadmin123
mc ls local/
```

**よくあるエラー:**

- **バケットが存在しない**
  ```bash
  mc mb local/nextcloud
  mc policy set private local/nextcloud
  ```

- **認証エラー**
  `k8s/02-minio.yaml` と `k8s/03-nextcloud.yaml` の認証情報が一致しているか確認

#### 6. PVCがPending状態

**原因確認:**

```bash
kubectl describe pvc <pvc-name> -n cloud-storage
```

**解決方法:**

```bash
# StorageClassを確認
kubectl get storageclass

# デフォルトStorageClassが設定されていない場合
kubectl patch storageclass local-path -p \
  '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

# k3s特有の問題の場合
sudo systemctl restart k3s
```

### パフォーマンスの改善

#### NextCloudが重い場合

1. **PHPメモリを増やす**
   
   `k8s/03-nextcloud.yaml` に追加：
   ```yaml
   env:
   - name: PHP_MEMORY_LIMIT
     value: "512M"
   - name: PHP_UPLOAD_LIMIT
     value: "10G"
   ```

2. **APCuキャッシュを有効化**
   ```bash
   kubectl exec -it -n cloud-storage deployment/nextcloud -- bash
   apt-get update && apt-get install -y php-apcu
   echo "'memcache.local' => '\OC\Memcache\APCu'," >> /var/www/html/config/config.php
   ```

3. **レプリカを増やす**
   ```bash
   kubectl scale deployment/nextcloud --replicas=2 -n cloud-storage
   ```

#### ファイルアップロードが遅い場合

**Cloudflare設定の最適化:**

1. Cloudflareダッシュボード → `Speed` → `Optimization`
   - Auto Minify: 無効化（大きなファイルでは不要）
   - Brotli: 有効化

2. `Rules` → `Configuration Rules`
   - NextCloudドメインに対してキャッシュを無効化
   - タイムアウトを延長

3. `Network`
   - HTTP/2: 有効化
   - HTTP/3 (QUIC): 有効化
   - WebSockets: 有効化

#### Collaboraが遅い場合

```yaml
# k8s/04-collabora.yaml
resources:
  requests:
    memory: "2Gi"
    cpu: "1000m"
  limits:
    memory: "4Gi"
    cpu: "2000m"
```

### デバッグコマンド集

```bash
# すべてのリソースを確認
kubectl get all -n cloud-storage

# Pod内でシェルを実行
kubectl exec -it -n cloud-storage <pod-name> -- /bin/bash

# ポートフォワードでローカルテスト
kubectl port-forward -n cloud-storage svc/nextcloud 8080:80

# 設定の確認
kubectl get configmap -n cloud-storage
kubectl get secret -n cloud-storage

# リソース使用状況
kubectl top pods -n cloud-storage
kubectl top nodes

# ネットワーク診断
kubectl exec -n cloud-storage deployment/nextcloud -- ping minio
kubectl exec -n cloud-storage deployment/nextcloud -- nslookup minio
```

## 🗑️ アンインストール

### クリーンアップスクリプトの使用

簡単に全てを削除できます：

```bash
./cleanup.sh
```

このスクリプトは以下を実行します：
- cloud-storage namespaceの削除（全リソース含む）
- 永続ボリューム（PV）の削除
- 確認メッセージ表示

### 手動でのアンインストール

```bash
# 1. namespace削除（全リソースが削除される）
kubectl delete namespace cloud-storage

# 2. PVの確認
kubectl get pv

# 3. 必要に応じてPVを削除
kubectl delete pv <pv-name>

# 4. Cloudflare Tunnelの削除（Cloudflareダッシュボード）
# Zero Trust → Networks → Tunnels から該当トンネルを削除
```

### k3sの完全削除（オプション）

k3s自体も削除する場合：

```bash
# k3sをアンインストール
/usr/local/bin/k3s-uninstall.sh

# データディレクトリを削除
sudo rm -rf /var/lib/rancher/k3s
```

## 📈 セキュリティのベストプラクティス

### 本番環境での推奨設定

#### 0. 環境変数ファイルの管理（最重要）

**`.env`ファイルの保護:**
- `.env`ファイルは絶対にGitHubにプッシュしないこと（`.gitignore`で除外済み）
- サーバー上で適切な権限を設定：
  ```bash
  chmod 600 .env
  chown root:root .env
  ```
- `.env.example`をテンプレートとして使用し、実際の値は含めない
- 本番環境では環境変数管理ツール（Vault、Sealed Secretsなど）の使用を推奨

#### 1. デフォルトパスワードの変更（必須）

**MinIO:**
```yaml
# k8s/02-minio.yaml
stringData:
  rootUser: "your-secure-admin-username"
  rootPassword: "your-very-strong-password-123!"
```

**NextCloud:**
初回セットアップ時に強力な管理者パスワードを設定

**Collabora:**
```yaml
# k8s/04-collabora.yaml
data:
  username: "collabora-admin"
  password: "strong-collabora-password-456!"
```

#### 2. Cloudflare Zero Trustアクセスポリシー

**Email認証を追加:**
```
Zero Trust → Access → Applications → Add an application
- Application domain: nextcloud.yourdomain.com
- Policy: Allow emails ending in @yourcompany.com
```

**IP制限を追加:**
```
- Policy: Allow IP ranges
- IP ranges: 203.0.113.0/24 (オフィスのIP)
```

**国別制限:**
```
- Policy: Block countries
- Countries: 特定の国をブロック
```

#### 3. SSL/TLS設定

Cloudflareダッシュボード → `SSL/TLS`:
- SSL/TLSモード: **Full (strict)** を推奨
- Minimum TLS Version: **TLS 1.2** 以上
- Always Use HTTPS: 有効化
- Automatic HTTPS Rewrites: 有効化

#### 4. ファイアウォールルール

Cloudflareダッシュボード → `Security` → `WAF`:
- Managed Rulesを有効化
- Rate Limitingを設定（DDoS対策）
- Bot Fight Modeを有効化

#### 5. 定期的なバックアップ

```bash
# Cronで毎日バックアップ
0 2 * * * /path/to/backup-script.sh
```

#### 6. アップデートの適用

```bash
# 月1回のアップデート確認
kubectl set image deployment/nextcloud nextcloud=nextcloud:latest -n cloud-storage
kubectl set image deployment/collabora collabora=collabora/code:latest -n cloud-storage
```

#### 7. ログ監視

```bash
# 異常なアクセスログの確認
kubectl logs -n cloud-storage -l app=cloudflare-tunnel | grep -i "error\|fail"
```

## ⚙️ カスタマイズ

### ストレージ容量の変更

各サービスのストレージ容量を変更：

```yaml
# k8s/02-minio.yaml - MinIOストレージ
resources:
  requests:
    storage: 100Gi  # デフォルト: 50Gi

# k8s/03-nextcloud.yaml - NextCloudストレージ
resources:
  requests:
    storage: 50Gi   # デフォルト: 30Gi

# k8s/03-nextcloud.yaml - データベースストレージ
resources:
  requests:
    storage: 20Gi   # デフォルト: 10Gi
```

変更後、再デプロイ：
```bash
kubectl apply -f k8s/02-minio.yaml
kubectl apply -f k8s/03-nextcloud.yaml
```

### レプリカ数の変更（高可用性）

```bash
# NextCloudを3レプリカに
kubectl scale deployment/nextcloud --replicas=3 -n cloud-storage

# Collaboraを2レプリカに
kubectl scale deployment/collabora --replicas=2 -n cloud-storage

# cloudflaredを2レプリカに（冗長性）
kubectl scale deployment/cloudflare-tunnel --replicas=2 -n cloud-storage
```

**YAMLで永続的に設定:**
```yaml
# k8s/03-nextcloud.yaml
spec:
  replicas: 3  # 変更
```

### ネームスペースの変更

全ての`.yaml`ファイルの`cloud-storage`を変更：

```bash
# sedで一括置換
sed -i '' 's/cloud-storage/my-storage/g' k8s/*.yaml

# 適用
./deploy.sh
```

### カスタムドメインの設定

1. **Cloudflare Tunnelの設定を更新**
   - Cloudflareダッシュボードで Public Hostname を変更

2. **Collaboraの設定を更新**
   ```yaml
   # k8s/04-collabora.yaml
   data:
     domain: "nextcloud\\.newdomain\\.com"
   ```

3. **NextCloudの信頼されたドメインを更新**
   ```bash
   kubectl exec -it -n cloud-storage deployment/nextcloud -- bash
   vi /var/www/html/config/config.php
   ```

## 📚 参考リンク

### 公式ドキュメント

- [Cloudflare Tunnel Documentation](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/)
- [Cloudflare Zero Trust](https://developers.cloudflare.com/cloudflare-one/)
- [NextCloud Documentation](https://docs.nextcloud.com/)
- [Collabora Online Documentation](https://sdk.collaboraonline.com/)
- [MinIO Documentation](https://min.io/docs/minio/kubernetes/upstream/)
- [k3s Documentation](https://docs.k3s.io/)

### コミュニティ

- [NextCloud Community Forum](https://help.nextcloud.com/)
- [Collabora Online Forum](https://forum.collaboraoffice.com/)
- [MinIO Slack](https://slack.min.io/)
- [Cloudflare Community](https://community.cloudflare.com/)

### チュートリアル

- [Cloudflare Tunnel Quick Start](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/install-and-setup/)
- [NextCloud on Kubernetes](https://docs.nextcloud.com/server/latest/admin_manual/installation/kubernetes.html)
- [k3s Getting Started](https://rancher.com/docs/k3s/latest/en/quick-start/)

## 🤝 貢献

プロジェクトへの貢献を歓迎します！

### 貢献方法

1. このリポジトリをフォーク
2. 新しいブランチを作成 (`git checkout -b feature/amazing-feature`)
3. 変更をコミット (`git commit -m 'Add some amazing feature'`)
4. ブランチにプッシュ (`git push origin feature/amazing-feature`)
5. Pull Requestを作成

### 報告

バグや機能要望は [Issues](https://github.com/JarodBruce/MinIO_NextCloud_CollaboraOnline/issues) で報告してください。

## 📄 ライセンス

MIT License

## 🙏 謝辞

このプロジェクトは以下のオープンソースプロジェクトを使用しています：

- [k3s](https://k3s.io/) - Lightweight Kubernetes
- [MinIO](https://min.io/) - High Performance Object Storage
- [NextCloud](https://nextcloud.com/) - Self-hosted Cloud Platform
- [Collabora Online](https://www.collaboraoffice.com/) - Online Office Suite
- [Cloudflare](https://www.cloudflare.com/) - Global Network & Security
- [PostgreSQL](https://www.postgresql.org/) - Advanced Open Source Database

---

**リポジトリ**: [https://github.com/JarodBruce/MinIO_NextCloud_CollaboraOnline](https://github.com/JarodBruce/MinIO_NextCloud_CollaboraOnline)

**作成日**: 2025年11月5日  
**最終更新**: 2025年11月5日

**メンテナー**: [@JarodBruce](https://github.com/JarodBruce)

---

💡 **ヒント**: 質問や問題がある場合は、[Issues](https://github.com/JarodBruce/MinIO_NextCloud_CollaboraOnline/issues)で質問するか、[Discussions](https://github.com/JarodBruce/MinIO_NextCloud_CollaboraOnline/discussions)で議論してください。
