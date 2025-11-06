# Cloudflare Access 設定ガイド

このガイドでは、NextCloud、Immich、Collabora OnlineにCloudflare Accessを統合する方法を説明します。

## 📋 目次

- [概要](#概要)
- [前提条件](#前提条件)
- [Cloudflare Accessとは](#cloudflare-accessとは)
- [設定手順](#設定手順)
- [各サービスの設定](#各サービスの設定)
- [認証方式の選択](#認証方式の選択)
- [トラブルシューティング](#トラブルシューティング)

## 🎯 概要

Cloudflare Accessは、ゼロトラストセキュリティモデルに基づいた認証サービスです。VPNなしで、世界中どこからでも安全にアプリケーションにアクセスできます。

### 主な機能

- ✅ **統一された認証**: すべてのサービスで同じ認証フロー
- ✅ **多要素認証(MFA)**: TOTPやハードウェアキーのサポート
- ✅ **SSO統合**: Google、Microsoft、Oktaなどと連携
- ✅ **セッション管理**: タイムアウトとデバイス管理
- ✅ **詳細なログ**: すべてのアクセス試行を記録
- ✅ **地理的制限**: 国別のアクセス制御
- ✅ **デバイス認証**: 信頼できるデバイスのみ許可

## 📦 前提条件

- Cloudflare アカウント（無料プランでOK）
- ドメインがCloudflareで管理されている
- Cloudflare Tunnelが設定済み
- NextCloud、Immich、Collaboraがデプロイ済み

## 🔐 Cloudflare Accessとは

Cloudflare Accessは、アプリケーションの前に認証レイヤーを配置し、許可されたユーザーのみがアクセスできるようにします。

```
ユーザー
   ↓
Cloudflare Access（認証）
   ↓
Cloudflare Tunnel
   ↓
あなたのアプリケーション
```

### 無料プランの制限

- 最大50ユーザー
- 月間最大10,000リクエスト
- 基本的な認証プロバイダー（Email OTP、Google等）

個人利用や小規模チームには十分です。

## 🚀 設定手順

### ステップ1: Cloudflare Zero Trustダッシュボードにアクセス

1. [Cloudflare One Dashboard](https://one.dash.cloudflare.com/) にログイン
2. 初回の場合、チーム名を設定（例: `mycompany`）
   - これが認証URLになります: `mycompany.cloudflareaccess.com`

### ステップ2: 認証プロバイダーの設定

最初に、認証方法を設定します。

1. `Settings` → `Authentication` → `Login methods` に移動
2. `Add new` をクリック

#### オプション1: One-time PIN（最も簡単）

- Name: `Email OTP`
- 有効化
- これで、メールアドレスにPINコードが送信されます

#### オプション2: Google認証

- `Add new` → `Google`
- Client ID と Client Secret を入力（Google Cloud Consoleで取得）
- `Save` をクリック

#### オプション3: その他のプロバイダー

- Microsoft Azure AD
- GitHub
- Okta
- SAML

### ステップ3: NextCloud用のアプリケーション作成

1. `Access` → `Applications` → `Add an application` をクリック

2. **Application Configuration**
   - Application name: `NextCloud`
   - Session duration: `24 hours`（お好みで調整）
   - Application domain: `nextcloud.yourdomain.com`

3. **Identity providers**
   - 設定した認証プロバイダーを選択（例: Email OTP）

4. **Add a policy**
   - Policy name: `Allow authorized users`
   - Action: `Allow`
   
   **Include規則を追加:**
   
   **オプションA: 特定のメールアドレス**
   ```
   Selector: Emails
   Value: admin@example.com, user@example.com
   ```
   
   **オプションB: ドメイン全体**
   ```
   Selector: Email domains
   Value: @yourcompany.com
   ```
   
   **オプションC: 特定のIP範囲**
   ```
   Selector: IP ranges
   Value: 203.0.113.0/24
   ```
   
   複数の条件を組み合わせることもできます。

5. **Additional settings（オプション）**
   - Enable App in App Launcher: 有効化（推奨）
   - Accept all available identity providers: 有効化

6. `Save application` をクリック

7. **Application Audience (AUD) Tagをコピー**
   - アプリケーション作成後、`Overview`タブに表示されます
   - 例: `a1b2c3d4e5f6g7h8i9j0`
   - これを後で使用します

### ステップ4: Immich用のアプリケーション作成

NextCloudと同じ手順で、Immich用のアプリケーションを作成：

- Application name: `Immich`
- Application domain: `immich.yourdomain.com`
- 同じポリシーまたは別のポリシーを設定
- AUD Tagをコピー

### ステップ5: Collabora Online用のアプリケーション作成

Collaboraは特殊な設定が必要です：

1. **基本設定**
   - Application name: `Collabora Online`
   - Application domain: `collabora.yourdomain.com`

2. **ポリシー設定**
   
   2つのポリシーが必要です：
   
   **ポリシー1: 通常のユーザー**
   - Policy name: `Allow users`
   - Action: `Allow`
   - Include: Emails（NextCloudと同じユーザー）
   
   **ポリシー2: NextCloudからのアクセスをバイパス**
   - Policy name: `Bypass from NextCloud`
   - Action: `Bypass`
   - Include: `IP ranges`
     - NextCloudのPod CIDR（例: `10.42.0.0/16`）
     - これにより、NextCloudがCollaboraにアクセスできます

3. AUD Tagをコピー

### ステップ6: MinIO Console用のアプリケーション作成

管理者のみがアクセスできるように設定：

- Application name: `MinIO Console`
- Application domain: `minio.yourdomain.com`
- Policy: 管理者のメールアドレスのみ許可

### ステップ7: Kubernetes設定の更新

1. **ConfigMapを編集**

   `k8s/07-cloudflare-access.yaml` を編集：
   
   ```yaml
   data:
     CLOUDFLARE_ACCESS_TEAM_DOMAIN: "mycompany.cloudflareaccess.com"  # 実際のチーム名
     NEXTCLOUD_POLICY_AUD: "a1b2c3d4e5f6g7h8i9j0"  # NextCloudのAUD Tag
     IMMICH_POLICY_AUD: "k1l2m3n4o5p6q7r8s9t0"     # ImmichのAUD Tag
     COLLABORA_POLICY_AUD: "u1v2w3x4y5z6a7b8c9d0"  # CollaboraのAUD Tag
   ```

2. **Kubernetesに適用**
   
   ```bash
   kubectl apply -f k8s/07-cloudflare-access.yaml
   ```

3. **Pod再起動（オプション）**
   
   設定を反映させるため：
   ```bash
   kubectl rollout restart deployment/nextcloud -n cloud-storage
   kubectl rollout restart deployment/immich-server -n cloud-storage
   kubectl rollout restart deployment/collabora -n cloud-storage
   ```

### ステップ8: 動作確認

1. **ブラウザのシークレットモードで開く**
   
   ```
   https://nextcloud.yourdomain.com
   ```

2. **Cloudflare Access認証画面が表示される**
   - Email OTPの場合: メールアドレスを入力
   - PINコードがメールで送信される
   - PINコードを入力

3. **NextCloudにリダイレクトされる**
   - 認証成功後、通常通りNextCloudが表示されます

4. **他のサービスでも確認**
   - `https://immich.yourdomain.com`
   - `https://collabora.yourdomain.com`
   - `https://minio.yourdomain.com`

## ⚙️ 各サービスの設定

### NextCloudの追加設定

Cloudflare Accessと正しく動作させるため、NextCloudの設定を調整：

```bash
kubectl exec -it -n cloud-storage deployment/nextcloud -- bash
vi /var/www/html/config/config.php
```

以下を追加：

```php
<?php
$CONFIG = array (
  // 既存の設定...
  
  // Cloudflare Access用の設定
  'trusted_proxies' => array(
    '10.0.0.0/8',  // Kubernetes内部ネットワーク
    // Cloudflare IPレンジ（IPv4）
    '173.245.48.0/20',
    '103.21.244.0/22',
    '103.22.200.0/22',
    '103.31.4.0/22',
    '141.101.64.0/18',
    '108.162.192.0/18',
    '190.93.240.0/20',
    '188.114.96.0/20',
    '197.234.240.0/22',
    '198.41.128.0/17',
    '162.158.0.0/15',
    '104.16.0.0/13',
    '104.24.0.0/14',
    '172.64.0.0/13',
    '131.0.72.0/22',
  ),
  
  'overwriteprotocol' => 'https',
  'overwrite.cli.url' => 'https://nextcloud.yourdomain.com',
  'overwritehost' => 'nextcloud.yourdomain.com',
  
  // Cloudflare Accessヘッダーを信頼
  'forwarded_for_headers' => array('HTTP_X_FORWARDED_FOR'),
);
```

### Immichの追加設定

Immichは環境変数で設定済みのため、追加作業は不要です。

ただし、認証ヘッダーを活用したい場合：

```yaml
# k8s/05-immich.yaml
env:
- name: IMMICH_TRUSTED_PROXIES
  value: "10.42.0.0/16,10.43.0.0/16,173.245.48.0/20,..."
```

### Collaboraの特殊設定

Collaboraは、NextCloudから内部的にアクセスされるため、バイパスポリシーが必要です。

**確認ポイント:**

1. Cloudflare AccessのCollaboraアプリケーションで`Bypass`ポリシーが設定されているか
2. `IP ranges`にNextCloudのPod CIDRが含まれているか

**Pod CIDRの確認方法:**

```bash
# NextCloud PodのIPを確認
kubectl get pods -n cloud-storage -o wide | grep nextcloud

# 例: 10.42.1.5
# CIDR: 10.42.0.0/16（k3sのデフォルト）
```

## 🔑 認証方式の選択

### Email OTP（推奨: 個人利用）

**メリット:**
- ✅ 設定が最も簡単
- ✅ 追加のサービス不要
- ✅ MFAとして機能

**デメリット:**
- ❌ メール遅延がある場合あり
- ❌ メールサーバーが必要

**設定方法:**

Cloudflareが自動的にメールを送信します。追加設定は不要。

### Google認証（推奨: 小規模チーム）

**メリット:**
- ✅ シームレスなSSO体験
- ✅ Googleアカウントを持つユーザーに便利
- ✅ 高速な認証

**デメリット:**
- ❌ Google Cloud Consoleでの設定が必要
- ❌ Googleアカウントが必要

**設定手順:**

1. [Google Cloud Console](https://console.cloud.google.com/) にアクセス
2. プロジェクトを作成（または既存のものを選択）
3. `APIs & Services` → `Credentials` → `Create Credentials` → `OAuth 2.0 Client ID`
4. Application type: `Web application`
5. Authorized redirect URIs:
   ```
   https://mycompany.cloudflareaccess.com/cdn-cgi/access/callback
   ```
6. Client ID と Client Secret をコピー
7. Cloudflare Dashboard → `Settings` → `Authentication` → `Add new` → `Google`
8. Client ID と Client Secret を貼り付け

### Microsoft Azure AD（推奨: 企業利用）

**メリット:**
- ✅ Microsoft 365と統合
- ✅ Active Directoryのユーザー管理
- ✅ 高度なポリシー設定

**設定手順:**

[Cloudflare公式ドキュメント](https://developers.cloudflare.com/cloudflare-one/identity/idp-integration/azuread/) を参照

### GitHub（推奨: 開発者向け）

**メリット:**
- ✅ 開発チームに最適
- ✅ Organization単位でのアクセス制御
- ✅ 設定が簡単

**設定手順:**

1. [GitHub Developer Settings](https://github.com/settings/developers) にアクセス
2. `New OAuth App` をクリック
3. Authorization callback URL:
   ```
   https://mycompany.cloudflareaccess.com/cdn-cgi/access/callback
   ```
4. Client ID と Client Secret をコピー
5. Cloudflareに設定

## 🐛 トラブルシューティング

### 認証ループが発生する

**症状:** Cloudflare Access認証後、NextCloudにリダイレクトされるが、再びCloudflare Accessに戻される。

**原因:** NextCloudがリバースプロキシを正しく認識していない。

**解決方法:**

```bash
kubectl exec -it -n cloud-storage deployment/nextcloud -- bash
vi /var/www/html/config/config.php

# trusted_proxies を追加（上記のNextCloud設定を参照）
```

### Collaboraにアクセスできない

**症状:** NextCloudからCollabora Onlineで文書を開こうとすると失敗する。

**原因:** CollaboraのBypassポリシーが設定されていない。

**解決方法:**

1. Cloudflare Dashboard → `Access` → `Applications` → `Collabora Online`
2. Policyに`Bypass`を追加
3. `IP ranges`: NextCloudのPod CIDR（`10.42.0.0/16`）

### Immichのアップロードが失敗する

**症状:** 写真のアップロード時にタイムアウトエラーが発生。

**原因:** Cloudflare Accessのセッションタイムアウトが短い。

**解決方法:**

1. Immich Applicationの設定を開く
2. Session duration: `8 hours` 以上に設定
3. Cloudflare Dashboard → `Rules` → `Configuration Rules`
4. 新しいルールを作成:
   - If: `Hostname equals immich.yourdomain.com`
   - Then: `Timeout = 300 seconds`（5分）

### MinIO Consoleが動作しない

**症状:** MinIO Consoleにログインできない。

**原因:** WebSocketがブロックされている可能性。

**解決方法:**

1. Cloudflare Dashboard → `Network`
2. `WebSockets`: 有効化
3. MinIO Application設定:
   - CORS settings: `Allow all origins`（開発環境のみ）

### 「Access Denied」エラー

**症状:** 認証後、「Access Denied」と表示される。

**原因:** ポリシーに該当しないユーザー。

**解決方法:**

1. Cloudflare Dashboard → `Access` → `Applications`
2. 該当アプリケーションのポリシーを確認
3. Include規則にユーザーのメールアドレスまたはドメインが含まれているか確認

### セッションの有効期限が切れる

**症状:** 頻繁に再認証を求められる。

**解決方法:**

1. Application設定で`Session duration`を長くする（例: `24 hours`）
2. `Settings` → `Authentication` → `Refresh window`を設定

## 📊 アクセスログの確認

Cloudflare Accessは詳細なログを提供します。

1. `Logs` → `Access` に移動
2. フィルタリング:
   - Application
   - User
   - Action (Allow/Block)
   - Time range

**ログに含まれる情報:**
- ユーザーのメールアドレス
- アクセス時刻
- IPアドレス
- デバイス情報
- 認証結果（許可/拒否）

## 🎯 高度な設定

### デバイス認証

特定のデバイスからのみアクセスを許可：

1. `Settings` → `WARP Client` → `Device enrollment`
2. ポリシーに`Require WARP`を追加

### セッション管理

```
Settings → Authentication → Session timeout
- Idle timeout: 30 minutes
- Maximum session duration: 24 hours
```

### 国別制限

ポリシーに追加：
```
Include: Country → Japan
Exclude: Country → (ブロックしたい国)
```

## 📚 参考リンク

- [Cloudflare Access Documentation](https://developers.cloudflare.com/cloudflare-one/policies/access/)
- [Identity Provider Integration](https://developers.cloudflare.com/cloudflare-one/identity/idp-integration/)
- [Access Policy Configuration](https://developers.cloudflare.com/cloudflare-one/policies/access/policy-management/)

---

**次のステップ:** [運用とメンテナンス](../README.md#運用とメンテナンス)
