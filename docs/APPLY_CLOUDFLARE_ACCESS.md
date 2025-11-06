# Cloudflare Access統合の適用方法

このガイドでは、既存のデプロイメントにCloudflare Access設定を適用する手順を説明します。

## 🎯 概要

以下の設定が追加されました：

1. **Cloudflare AccessのConfigMap** - 認証設定
2. **NextCloudの信頼プロキシ設定** - CloudflareのIPレンジを信頼
3. **Immichのプロキシ設定** - トラステッドプロキシの追加
4. **Collaboraのプロキシ設定** - NextCloudとの連携強化

## 📋 前提条件

- Cloudflare Tunnelが設定済み
- 全サービスがデプロイ済み
- Cloudflare Accessアプリケーションが作成済み

## 🚀 適用手順

### ステップ1: Cloudflare Access ConfigMapの作成

まず、Cloudflare Accessの設定を適用します：

```bash
# ConfigMapを作成
kubectl apply -f k8s/07-cloudflare-access.yaml
```

**重要:** `k8s/07-cloudflare-access.yaml`を編集して、実際の値を設定してください：

```yaml
data:
  CLOUDFLARE_ACCESS_TEAM_DOMAIN: "your-team.cloudflareaccess.com"  # 実際のチーム名
  NEXTCLOUD_POLICY_AUD: "your-actual-nextcloud-aud-tag"            # NextCloudのAUD
  IMMICH_POLICY_AUD: "your-actual-immich-aud-tag"                  # ImmichのAUD
  COLLABORA_POLICY_AUD: "your-actual-collabora-aud-tag"            # CollaboraのAUD
```

**AUD Tagの取得方法:**
1. Cloudflare Dashboard → `Access` → `Applications`
2. 各アプリケーションをクリック
3. `Overview`タブの`Application Audience (AUD) Tag`をコピー

### ステップ2: 既存の設定が更新されていることを確認

以下のファイルは既に更新されています：

#### NextCloud (`k8s/03-nextcloud.yaml`)
- `TRUSTED_PROXIES`にCloudflareのIPレンジが追加済み
- プロキシ設定が最適化済み

#### Immich (`k8s/05-immich.yaml`)
- `IMMICH_TRUSTED_PROXIES`が設定済み

#### Collabora (`k8s/04-collabora.yaml`)
- `extra_params`にプロキシ設定が追加済み

変更を確認：
```bash
git diff k8s/03-nextcloud.yaml
git diff k8s/04-collabora.yaml
git diff k8s/05-immich.yaml
```

### ステップ3: 設定の再適用

変更された設定を適用：

```bash
# NextCloud設定を再適用
kubectl apply -f k8s/03-nextcloud.yaml

# Collabora設定を再適用
kubectl apply -f k8s/04-collabora.yaml

# Immich設定を再適用
kubectl apply -f k8s/05-immich.yaml
```

### ステップ4: Podの再起動

設定を反映させるため、各サービスを再起動：

```bash
# NextCloud
kubectl rollout restart deployment/nextcloud -n cloud-storage

# Collabora
kubectl rollout restart deployment/collabora -n cloud-storage

# Immich Server
kubectl rollout restart deployment/immich-server -n cloud-storage
```

再起動の進行状況を確認：
```bash
kubectl rollout status deployment/nextcloud -n cloud-storage
kubectl rollout status deployment/collabora -n cloud-storage
kubectl rollout status deployment/immich-server -n cloud-storage
```

### ステップ5: NextCloudの追加設定（手動）

NextCloudには、ConfigMapで設定できない項目があります。手動で追加：

```bash
# NextCloud Podに入る
NEXTCLOUD_POD=$(kubectl get pod -n cloud-storage -l app=nextcloud -o jsonpath='{.items[0].metadata.name}')
kubectl exec -it -n cloud-storage $NEXTCLOUD_POD -- bash
```

`config.php`を編集：
```bash
vi /var/www/html/config/config.php
```

以下を追加（既存の配列に追加）：

```php
<?php
$CONFIG = array (
  // ... 既存の設定 ...
  
  // Cloudflare Proxy設定
  'trusted_proxies' => array(
    '10.0.0.0/8',
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
  'forwarded_for_headers' => array('HTTP_X_FORWARDED_FOR'),
);
```

**注意:** `nextcloud.yourdomain.com` を実際のドメインに置き換えてください。

保存して終了（`:wq`）。

Podから抜ける：
```bash
exit
```

### ステップ6: Cloudflare Accessアプリケーションの作成

まだ作成していない場合、Cloudflareダッシュボードでアプリケーションを作成：

#### NextCloud

1. `Access` → `Applications` → `Add an application`
2. Application name: `NextCloud`
3. Application domain: `nextcloud.yourdomain.com`
4. Session duration: `24 hours`
5. Policy:
   - Name: `Allow users`
   - Action: `Allow`
   - Include: `Emails` → 許可するメールアドレス

#### Immich

1. Application name: `Immich`
2. Application domain: `immich.yourdomain.com`
3. 同様のポリシーを設定

#### Collabora

1. Application name: `Collabora Online`
2. Application domain: `collabora.yourdomain.com`
3. **重要:** 2つのポリシーが必要
   
   **ポリシー1:**
   - Name: `Allow users`
   - Action: `Allow`
   - Include: `Emails`
   
   **ポリシー2:**
   - Name: `Bypass from NextCloud`
   - Action: `Bypass`
   - Include: `IP ranges` → `10.42.0.0/16`（NextCloudのPod CIDR）

### ステップ7: 動作確認

各サービスにアクセスして、Cloudflare Access認証が機能しているか確認：

```bash
# ブラウザでアクセス（シークレットモード推奨）
# 1. NextCloud
https://nextcloud.yourdomain.com

# 2. Immich
https://immich.yourdomain.com

# 3. Collabora（NextCloudから文書を開く）
https://collabora.yourdomain.com

# 4. MinIO（オプション）
https://minio.yourdomain.com
```

**期待される動作:**
1. Cloudflare Accessの認証画面が表示される
2. メールアドレスを入力（Email OTPの場合）
3. PINコードがメールで送信される
4. PINコードを入力
5. 認証成功後、該当サービスにリダイレクト

### ステップ8: 問題のデバッグ

問題が発生した場合：

```bash
# 各サービスのログを確認
kubectl logs -n cloud-storage -l app=nextcloud --tail=50
kubectl logs -n cloud-storage -l app=immich-server --tail=50
kubectl logs -n cloud-storage -l app=collabora --tail=50

# Cloudflare Tunnelのログを確認
kubectl logs -n cloud-storage -l app=cloudflare-tunnel --tail=50

# Podの状態確認
kubectl get pods -n cloud-storage

# ConfigMapの確認
kubectl get configmap -n cloud-storage
kubectl describe configmap cloudflare-access-config -n cloud-storage
```

## 🔧 トラブルシューティング

### 認証ループが発生する

**症状:** 認証後、再びCloudflare Access画面に戻る。

**解決方法:**

NextCloudの`config.php`が正しく設定されているか確認：

```bash
kubectl exec -n cloud-storage deployment/nextcloud -- \
  cat /var/www/html/config/config.php | grep -A 20 trusted_proxies
```

### Collaboraにアクセスできない

**症状:** NextCloudから文書を開けない。

**解決方法:**

1. Collabora Applicationに`Bypass`ポリシーがあるか確認
2. NextCloudのPod IPを確認：
   ```bash
   kubectl get pods -n cloud-storage -o wide | grep nextcloud
   ```
3. そのIPレンジ（例: `10.42.0.0/16`）がBypassポリシーに含まれているか確認

### Immichのアップロードが遅い

**症状:** 写真のアップロードがタイムアウトする。

**解決方法:**

Cloudflare Dashboard → `Rules` → `Configuration Rules`:

```
If: Hostname equals immich.yourdomain.com
Then:
  - Browser Integrity Check: Off
  - Security Level: Essentially Off
  - Timeout: 300 seconds
```

### 「Access Denied」エラー

**症状:** 認証後、アクセス拒否される。

**解決方法:**

Cloudflare Accessのポリシーを確認：

1. Dashboard → `Access` → `Applications` → 該当アプリ
2. Policyで、ユーザーのメールアドレスが`Include`に含まれているか確認

## 📊 設定の検証

### NextCloud設定の検証

```bash
kubectl exec -n cloud-storage deployment/nextcloud -- \
  php /var/www/html/occ config:list system

# trusted_proxies が設定されているか確認
```

### Immich設定の検証

```bash
kubectl exec -n cloud-storage deployment/immich-server -- \
  printenv | grep TRUSTED_PROXIES
```

### Collabora設定の検証

```bash
kubectl logs -n cloud-storage -l app=collabora | grep -i "proxy\|wopi"
```

## 🎯 次のステップ

設定が完了したら：

1. **アクセスログの確認**
   - Cloudflare Dashboard → `Logs` → `Access`
   - 誰がいつアクセスしたか確認

2. **追加のセキュリティ設定**
   - 多要素認証(MFA)の有効化
   - デバイス認証の設定
   - 国別制限の追加

3. **パフォーマンス最適化**
   - セッションタイムアウトの調整
   - キャッシュ設定の最適化

詳細は [Cloudflare Access設定ガイド](./CLOUDFLARE_ACCESS_SETUP.md) を参照してください。

## 📚 参考リンク

- [Cloudflare Access公式ドキュメント](https://developers.cloudflare.com/cloudflare-one/policies/access/)
- [NextCloud Reverse Proxy設定](https://docs.nextcloud.com/server/latest/admin_manual/configuration_server/reverse_proxy_configuration.html)
- [Collabora Online Proxy設定](https://sdk.collaboraonline.com/docs/installation/Proxy_settings.html)

---

**質問やサポートが必要な場合:** [GitHub Issues](https://github.com/JarodBruce/MinIO_NextCloud_CollaboraOnline/issues)
