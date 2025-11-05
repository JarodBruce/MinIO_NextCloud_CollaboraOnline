# Nginx Proxy Manager設定ガイド

## 概要

このガイドでは、Nginx Proxy Manager (NPM) を使用してMinIO、NextCloud、Collabora OnlineへのリバースプロキシとSSL終端の設定方法を説明します。

## 初期セットアップ

### 1. 管理画面へのアクセス

```bash
# ポートフォワードで管理画面にアクセス
kubectl port-forward -n cloud-storage svc/nginx-proxy-manager 8081:81
```

ブラウザで `http://localhost:8081` を開く

### 2. 初回ログイン

**デフォルト認証情報:**
- Email: `admin@example.com`
- Password: `changeme`

**重要**: 初回ログイン後、必ずパスワードを変更してください！

## プロキシホストの設定

### NextCloudのプロキシ設定

#### 基本設定

1. **Proxy Hosts** タブをクリック
2. **Add Proxy Host** をクリック
3. **Details** タブで以下を入力:
   - **Domain Names**: `nextcloud.yourdomain.com` または `nextcloud.local`
   - **Scheme**: `http`
   - **Forward Hostname / IP**: `nextcloud.cloud-storage.svc.cluster.local`
   - **Forward Port**: `80`
   - **Cache Assets**: ✓ ON
   - **Block Common Exploits**: ✓ ON
   - **Websockets Support**: ✓ ON

#### カスタムロケーション設定

4. **Custom Locations** タブで以下を追加:

**Location 1: WebDAV (CardDAV)**
```nginx
location = /.well-known/carddav {
    return 301 $scheme://$host/remote.php/dav;
}
```

**Location 2: WebDAV (CalDAV)**
```nginx
location = /.well-known/caldav {
    return 301 $scheme://$host/remote.php/dav;
}
```

**Location 3: WebFinger**
```nginx
location = /.well-known/webfinger {
    return 301 $scheme://$host/index.php/.well-known/webfinger;
}

location = /.well-known/nodeinfo {
    return 301 $scheme://$host/index.php/.well-known/nodeinfo;
}
```

#### 高度な設定

5. **Advanced** タブで以下を追加:

```nginx
# NextCloud推奨設定
client_max_body_size 10G;
client_body_timeout 3600s;
proxy_read_timeout 3600s;
proxy_connect_timeout 3600s;
proxy_send_timeout 3600s;

# HSTSヘッダー
add_header Strict-Transport-Security "max-age=15552000; includeSubDomains" always;

# セキュリティヘッダー
add_header X-Content-Type-Options "nosniff" always;
add_header X-XSS-Protection "1; mode=block" always;
add_header X-Robots-Tag "none" always;
add_header X-Download-Options "noopen" always;
add_header X-Permitted-Cross-Domain-Policies "none" always;
add_header Referrer-Policy "no-referrer" always;

# プロキシヘッダー
proxy_set_header X-Forwarded-Proto $scheme;
proxy_set_header X-Forwarded-Host $host;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
```

#### SSL証明書設定

6. **SSL** タブで:
   - **SSL Certificate**: Let's Encryptで新規証明書を作成
   - **Force SSL**: ✓ ON
   - **HTTP/2 Support**: ✓ ON
   - **HSTS Enabled**: ✓ ON
   - **HSTS Subdomains**: ✓ ON

7. **Save** をクリック

### Collabora Onlineのプロキシ設定

#### 基本設定

1. **Add Proxy Host** をクリック
2. **Details** タブ:
   - **Domain Names**: `collabora.yourdomain.com`
   - **Scheme**: `http`
   - **Forward Hostname / IP**: `collabora.cloud-storage.svc.cluster.local`
   - **Forward Port**: `9980`
   - **Cache Assets**: ✗ OFF
   - **Block Common Exploits**: ✓ ON
   - **Websockets Support**: ✓ ON（重要！）

#### 高度な設定

3. **Advanced** タブ:

```nginx
# Collabora Online推奨設定
client_max_body_size 0;

# WebSocket設定
proxy_http_version 1.1;
proxy_set_header Upgrade $http_upgrade;
proxy_set_header Connection "Upgrade";

# タイムアウト設定
proxy_read_timeout 36000s;
proxy_connect_timeout 36000s;
proxy_send_timeout 36000s;

# プロキシヘッダー
proxy_set_header Host $http_host;
proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto $scheme;
```

#### SSL設定

4. **SSL** タブ:
   - Let's Encrypt証明書を設定
   - Force SSL: ✓ ON
   - HTTP/2 Support: ✓ ON

### MinIOのプロキシ設定

#### MinIO API (S3)

1. **Add Proxy Host**
2. **Details** タブ:
   - **Domain Names**: `minio-api.yourdomain.com`
   - **Scheme**: `http`
   - **Forward Hostname / IP**: `minio.cloud-storage.svc.cluster.local`
   - **Forward Port**: `9000`
   - **Cache Assets**: ✗ OFF
   - **Block Common Exploits**: ✓ ON
   - **Websockets Support**: ✓ ON

3. **Advanced** タブ:

```nginx
# MinIO S3 API設定
client_max_body_size 0;

# プロキシヘッダー
proxy_set_header Host $http_host;
proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto $scheme;

# タイムアウト
proxy_connect_timeout 300;
proxy_http_version 1.1;
proxy_set_header Connection "";
chunked_transfer_encoding off;
```

#### MinIO Console (Web UI)

1. **Add Proxy Host**
2. **Details** タブ:
   - **Domain Names**: `minio-console.yourdomain.com`
   - **Scheme**: `http`
   - **Forward Hostname / IP**: `minio.cloud-storage.svc.cluster.local`
   - **Forward Port**: `9001`
   - **Cache Assets**: ✗ OFF
   - **Block Common Exploits**: ✓ ON
   - **Websockets Support**: ✓ ON（重要！）

3. **Advanced** タブ:

```nginx
# MinIO Console設定
client_max_body_size 0;

# WebSocket設定（Console用）
proxy_http_version 1.1;
proxy_set_header Upgrade $http_upgrade;
proxy_set_header Connection "upgrade";

# プロキシヘッダー
proxy_set_header Host $http_host;
proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto $scheme;
proxy_set_header X-NginX-Proxy true;

# タイムアウト
proxy_read_timeout 86400;
```

## SSL証明書の管理

### Let's Encrypt証明書の取得

#### 前提条件

- ドメインが正しくDNS設定されている
- ポート80と443が外部からアクセス可能

#### 手順

1. **SSL Certificates** タブをクリック
2. **Add SSL Certificate** をクリック
3. **Let's Encrypt** を選択
4. 入力:
   - **Domain Names**: 
     ```
     nextcloud.yourdomain.com
     collabora.yourdomain.com
     minio-api.yourdomain.com
     minio-console.yourdomain.com
     ```
   - **Email Address**: あなたのメールアドレス
   - **Use a DNS Challenge**: プライベートネットワークの場合はON
   - **Agree to the Let's Encrypt Terms of Service**: ✓ ON
5. **Save** をクリック

### 自己署名証明書の作成

開発環境用：

1. **SSL Certificates** タブ
2. **Add SSL Certificate**
3. **Custom** を選択
4. 証明書と秘密鍵を貼り付け

#### 自己署名証明書の生成

```bash
# OpenSSLで証明書生成
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /tmp/npm-selfsigned.key \
  -out /tmp/npm-selfsigned.crt \
  -subj "/C=JP/ST=Tokyo/L=Tokyo/O=YourOrg/CN=*.yourdomain.com"

# 証明書の内容を表示
cat /tmp/npm-selfsigned.crt
cat /tmp/npm-selfsigned.key
```

### ワイルドカード証明書

```bash
# ワイルドカード証明書の取得（DNS Challenge必須）
# Domain Names: *.yourdomain.com, yourdomain.com
```

## アクセスリスト（Access Lists）

特定のIPアドレスからのみアクセスを許可：

### 1. アクセスリストの作成

1. **Access Lists** タブをクリック
2. **Add Access List** をクリック
3. 入力:
   - **Name**: `Tailscale Only`
   - **Satisfy Any**: OFF
   
4. **Authorization** タブ:
   - ユーザー名/パスワード認証（オプション）

5. **Access** タブ:
   ```
   Allow: 100.64.0.0/10  # Tailscale CGNAT range
   Deny: all
   ```

### 2. プロキシホストに適用

1. プロキシホストを編集
2. **Details** タブで **Access List** を選択
3. 作成したアクセスリストを選択

## カスタム設定例

### レート制限

```nginx
# 1秒間に10リクエストまで
limit_req_zone $binary_remote_addr zone=nextcloud_limit:10m rate=10r/s;
limit_req zone=nextcloud_limit burst=20 nodelay;
```

### 特定のパスのブロック

```nginx
# xmlrpc.phpへのアクセスをブロック
location ~ /xmlrpc.php {
    deny all;
    return 403;
}
```

### カスタムエラーページ

```nginx
error_page 502 503 504 /custom_502.html;
location = /custom_502.html {
    root /data/nginx/error_pages;
    internal;
}
```

### ログ設定

```nginx
# 詳細なログ
access_log /data/logs/nextcloud_access.log;
error_log /data/logs/nextcloud_error.log debug;
```

## トラブルシューティング

### 502 Bad Gateway

**原因:**
- バックエンドサービスが起動していない
- ホスト名/IPが間違っている
- ポート番号が間違っている

**確認:**
```bash
# サービスの状態確認
kubectl get svc -n cloud-storage

# Podの状態確認
kubectl get pods -n cloud-storage

# NPM Podからの接続テスト
kubectl exec -n cloud-storage <npm-pod> -- curl http://nextcloud.cloud-storage.svc.cluster.local
```

### 504 Gateway Timeout

**原因:**
- バックエンドのレスポンスが遅い
- タイムアウト設定が短すぎる

**解決:**
```nginx
# Advanced設定でタイムアウトを増やす
proxy_connect_timeout 600s;
proxy_send_timeout 600s;
proxy_read_timeout 600s;
```

### WebSocketが動作しない

**原因:**
- WebSockets Supportが無効
- Upgradeヘッダーが正しく設定されていない

**解決:**
```nginx
# Advanced設定で追加
proxy_http_version 1.1;
proxy_set_header Upgrade $http_upgrade;
proxy_set_header Connection "upgrade";
```

### SSL証明書エラー

**Let's Encrypt証明書が取得できない:**
```bash
# NPMのログ確認
kubectl logs -n cloud-storage -l app=nginx-proxy-manager -f

# よくある原因:
# - ドメインがNPMにルーティングされていない
# - ポート80/443が閉じている
# - レート制限に達した
```

### NextCloudが「信頼されたドメインではない」エラー

**解決:**
```bash
# NextCloud Podに入る
kubectl exec -it -n cloud-storage <nextcloud-pod> -- bash

# config.phpを編集
vi /var/www/html/config/config.php

# trusted_domainsに追加
'trusted_domains' => 
  array (
    0 => 'localhost',
    1 => 'nextcloud.yourdomain.com',
    2 => 'nextcloud.local',
  ),
```

## パフォーマンスチューニング

### キャッシュ設定

```nginx
# 静的ファイルのキャッシュ
location ~* \.(jpg|jpeg|png|gif|ico|css|js)$ {
    expires 1y;
    add_header Cache-Control "public, immutable";
}
```

### Gzip圧縮

```nginx
gzip on;
gzip_vary on;
gzip_min_length 1024;
gzip_types text/plain text/css text/xml text/javascript 
           application/x-javascript application/xml+rss 
           application/json application/javascript;
```

### HTTP/2の有効化

1. SSL証明書が設定されている必要がある
2. SSL タブで **HTTP/2 Support** を有効化

### 接続プール

```nginx
# バックエンドへの接続をプール
upstream nextcloud_backend {
    server nextcloud.cloud-storage.svc.cluster.local:80;
    keepalive 32;
}

location / {
    proxy_pass http://nextcloud_backend;
    proxy_http_version 1.1;
    proxy_set_header Connection "";
}
```

## セキュリティ強化

### セキュリティヘッダーの追加

```nginx
# XSS保護
add_header X-XSS-Protection "1; mode=block" always;

# コンテンツタイプスニッフィング防止
add_header X-Content-Type-Options "nosniff" always;

# クリックジャッキング防止
add_header X-Frame-Options "SAMEORIGIN" always;

# CSP（Content Security Policy）
add_header Content-Security-Policy "default-src 'self' https: data: 'unsafe-inline' 'unsafe-eval';" always;

# HSTS
add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;
```

### 基本認証の追加

1. プロキシホストの **Advanced** タブ:

```nginx
auth_basic "Restricted Access";
auth_basic_user_file /data/nginx/htpasswd;
```

2. htpasswdファイルの作成:

```bash
# NPM Podに入る
kubectl exec -it -n cloud-storage <npm-pod> -- sh

# htpasswdファイル作成
apk add apache2-utils
htpasswd -c /data/nginx/htpasswd username
```

### IP制限

```nginx
# 特定のIPのみ許可
allow 192.168.1.0/24;
allow 100.64.0.0/10;  # Tailscale
deny all;
```

## バックアップとリストア

### 設定のバックアップ

```bash
# NPMのデータをバックアップ
kubectl exec -n cloud-storage <npm-pod> -- tar czf /tmp/npm-backup.tar.gz /data

# ローカルにコピー
kubectl cp cloud-storage/<npm-pod>:/tmp/npm-backup.tar.gz ./npm-backup.tar.gz
```

### リストア

```bash
# バックアップをPodにコピー
kubectl cp ./npm-backup.tar.gz cloud-storage/<npm-pod>:/tmp/npm-backup.tar.gz

# リストア
kubectl exec -n cloud-storage <npm-pod> -- tar xzf /tmp/npm-backup.tar.gz -C /
```

## 監視とログ

### ログの確認

```bash
# NPMのログ
kubectl logs -n cloud-storage -l app=nginx-proxy-manager -f

# 特定のプロキシホストのログ
kubectl exec -n cloud-storage <npm-pod> -- tail -f /data/logs/proxy-host-*.log
```

### メトリクス

NPMはPrometheusメトリクスをデフォルトで提供していません。Nginx Exporterを追加することで監視可能：

```yaml
# nginx-exporter.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-exporter
  namespace: cloud-storage
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx-exporter
  template:
    metadata:
      labels:
        app: nginx-exporter
    spec:
      containers:
      - name: nginx-exporter
        image: nginx/nginx-prometheus-exporter:latest
        args:
        - -nginx.scrape-uri=http://nginx-proxy-manager/stub_status
        ports:
        - containerPort: 9113
```

## 参考リンク

- [Nginx Proxy Manager公式ドキュメント](https://nginxproxymanager.com/)
- [Nginx公式ドキュメント](https://nginx.org/en/docs/)
- [NextCloud Nginx設定](https://docs.nextcloud.com/server/latest/admin_manual/installation/nginx.html)
- [Let's Encrypt](https://letsencrypt.org/)

---

**最終更新**: 2025年11月5日
