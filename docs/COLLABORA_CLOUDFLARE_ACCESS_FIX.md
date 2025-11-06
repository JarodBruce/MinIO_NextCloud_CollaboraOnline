# Collabora + Cloudflare Access 統合の修正ガイド

## 🐛 問題の説明

Collabora OnlineがNextCloudのWOPIエンドポイントにアクセスしようとすると、Cloudflare Accessの認証画面にリダイレクトされ、404エラーが発生します。

**エラーログ:**
```
ERR  #32: WOPI::CheckFileInfo returned 404 (Not Found) 
for URI [https://jarodbruce.cloudflareaccess.com/cdn-cgi/access/login/...]
ERR  #32: Access denied to CheckFileInfo
```

## 🔍 原因

Collabora（サーバー側）からNextCloudのWOPIエンドポイント（`/index.php/apps/richdocuments/wopi/files/*`）へのアクセスが、Cloudflare Accessによってブロックされています。

**問題の流れ:**
1. ユーザーがNextCloudでドキュメントを開く
2. NextCloudがCollaboraにWOPI URLを渡す（`access_token`付き）
3. CollaboraがそのURLにアクセスしようとする
4. Cloudflare AccessがCollaboraを認証していないため、ログイン画面にリダイレクト
5. Collaboraは404エラーを受け取る

## 💡 解決策

以下の3つの解決策を提供します：

### 解決策1: Cloudflare AccessでWOPIパスをバイパス（最も推奨）

NextCloudアプリケーションのポリシーで、WOPIエンドポイントのみバイパスします。

#### Cloudflareダッシュボードでの設定

1. **Cloudflare Zero Trust Dashboard**にアクセス
   ```
   https://one.dash.cloudflare.com/
   ```

2. **NextCloudアプリケーションを編集**
   - `Access` → `Applications` → `NextCloud` をクリック
   - `Edit` をクリック

3. **WOPIエンドポイント専用の新しいApplicationを作成（推奨方法）**
   
   メインのNextCloudアプリケーションとは別に、WOPI専用のApplicationを作成します：
   
   **ステップ1: 新しいApplicationを作成**
   - `Access` → `Applications` → `Add an application`
   - Select type: `Self-hosted`
   
   **ステップ2: Application Configurationを設定**
   - Application name: `NextCloud WOPI (No Auth)`
   - Session Duration: `24 hours`
   - Application domain: `nextcloud.jarodbruce.f5.si`
   - Path (重要): `/index.php/apps/richdocuments/wopi`
   - ✓ `Include all subpaths` にチェック
   
   **ステップ3: Identity Providersを選択**
   - 任意のプロバイダーを選択（実際には使用されない）
   
   **ステップ4: Policyを設定**
   - Policy name: `Bypass everyone`
   - Action: `Bypass`
   - Configure rules:
     - **Include:** `Everyone`
   
   この設定により、`/index.php/apps/richdocuments/wopi/*` へのアクセスは
   すべて認証なしでバイパスされます。#### 動作確認

```bash
# Collabora Podのログを確認
kubectl logs -n cloud-storage -l app=collabora -f --tail=50

# NextCloudで文書を開いてみる
# エラーがなくなっているはず
```

---

### 解決策2: CollaboraにService Tokenを使用

Cloudflare AccessのService Tokenを使用して、CollaboraをCloudflare Accessで認証します。

#### ステップ1: Service Tokenの作成

1. **Cloudflare Zero Trust Dashboard**
   ```
   https://one.dash.cloudflare.com/
   ```

2. **Service Tokenを作成**
   - `Access` → `Service Auth` → `Service Tokens` に移動
   - `Create Service Token` をクリック
   - Name: `Collabora WOPI Access`
   - Duration: `Non-expiring`（または適切な期間）
   - `Generate token` をクリック

3. **Client IDとClient Secretをコピー**
   ```
   Client ID: xxxxxxxxxxxxxxxxxxxxxxxxxxxx
   Client Secret: yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy
   ```
   
   **重要:** このSecretは一度しか表示されません！

#### ステップ2: KubernetesにSecretを作成

```bash
kubectl create secret generic collabora-cf-token \
  --from-literal=CF_CLIENT_ID="xxxxxxxxxxxxxxxxxxxxxxxxxxxx" \
  --from-literal=CF_CLIENT_SECRET="yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy" \
  -n cloud-storage
```

#### ステップ3: Collabora設定を更新

`k8s/04-collabora.yaml`を編集：

```yaml
# Collabora用のConfigMap更新
apiVersion: v1
kind: ConfigMap
metadata:
  name: collabora-config
  namespace: cloud-storage
data:
  domain: "nextcloud\\.jarodbruce\\.f5\\.si|nextcloud\\.cloud-storage\\.svc\\.cluster\\.local"
  username: "admin"
  password: "admin123"
  extra_params: "--o:ssl.enable=false --o:ssl.termination=true --o:storage.wopi.host[0]=nextcloud.cloud-storage.svc.cluster.local --o:storage.wopi.host[1]=nextcloud.jarodbruce.f5.si --o:net.proxy_prefix=true --o:net.frame_ancestors=nextcloud.jarodbruce.f5.si --o:net.service_root=/browser/dist"
  # Cloudflare Access Service Token用のヘッダー設定
  cf_access_enabled: "true"
```

Collabora Deploymentにenv追加：

```yaml
containers:
- name: collabora
  image: collabora/code:latest
  env:
  # ... 既存のenv ...
  - name: CF_ACCESS_CLIENT_ID
    valueFrom:
      secretKeyRef:
        name: collabora-cf-token
        key: CF_CLIENT_ID
  - name: CF_ACCESS_CLIENT_SECRET
    valueFrom:
      secretKeyRef:
        name: collabora-cf-token
        key: CF_CLIENT_SECRET
```

しかし、Collabora自体はService Tokenヘッダーを自動的に送信しないため、**カスタムプロキシが必要**です。

#### ステップ4: Nginx Sidecarプロキシを追加（推奨しない：複雑）

この方法は複雑なため、**解決策1**を推奨します。

---

### 解決策3: 内部通信用に別のURLを使用（最もクリーン）

NextCloudがCollaboraに渡すWOPI URLを、Cloudflare Accessを経由しない内部URLに変更します。

#### ステップ1: NextCloudの内部通信用Ingressを作成

現在、NextCloudはCollaboraに`https://nextcloud.jarodbruce.f5.si/...`（Cloudflare Access経由）のURLを渡しています。代わりに、内部URL `http://nextcloud.cloud-storage.svc.cluster.local/...`を使用します。

#### ステップ2: NextCloud設定を更新

NextCloudの環境変数を追加：

```yaml
# k8s/03-nextcloud.yaml - ConfigMap更新
data:
  # ... 既存の設定 ...
  
  # Collabora内部通信用
  COLLABORA_WOPI_CALLBACK_URL: "http://nextcloud.cloud-storage.svc.cluster.local"
```

これは既に設定されていますが、NextCloudの`richdocuments`アプリの設定も更新する必要があります。

#### ステップ3: NextCloud内でWOPI URLを内部URLに変更

NextCloudにログインして、Collabora Online設定を確認：

```bash
# NextCloud Podに入る
kubectl exec -it -n cloud-storage deployment/nextcloud -- bash

# Collabora設定を確認
php occ config:app:get richdocuments wopi_url

# 内部URLに変更（もし外部URLになっている場合）
php occ config:app:set richdocuments wopi_url --value="http://nextcloud.cloud-storage.svc.cluster.local"

# 確認
php occ config:app:get richdocuments wopi_url
```

しかし、これでもブラウザからのアクセスは外部URL経由のため、混在して複雑になります。

---

## 🎯 推奨される解決策

**WOPIエンドポイント専用のApplicationを作成する方法**が最もシンプルで安全です。

### 完全な実装手順

#### ステップ1: 新しいApplicationを作成

1. `Access` → `Applications` → `Add an application`
2. Type: `Self-hosted` を選択

#### ステップ2: Application Configuration

| 項目 | 設定値 |
|------|--------|
| Application name | `NextCloud WOPI (No Auth)` |
| Session Duration | `24 hours` |
| Application domain | `nextcloud.jarodbruce.f5.si` |
| Path | `/index.php/apps/richdocuments/wopi` |
| Include all subpaths | ✓ **必ずチェック** |

#### ステップ3: Identity Providers選択

任意のプロバイダーを選択（実際には使用されない）

#### ステップ4: Policy設定

| 項目 | 設定値 |
|------|--------|
| Policy name | `Bypass everyone` |
| Action | `Bypass` |
| Include | `Everyone` |

#### ステップ5: 保存して確認

`Add application` をクリックして完了。数分待って反映を確認

### セキュリティ考慮事項

**Q: WOPIエンドポイントをバイパスしても安全？**

A: はい。WOPIプロトコル自体に認証機構（`access_token`）があります。

- NextCloudは一時的な`access_token`を生成
- CollaboraはこのトークンでWOPIエンドポイントにアクセス
- トークンは短時間で期限切れ
- トークンなしではファイルにアクセスできない

したがって、WOPIエンドポイントをCloudflare Accessからバイパスしても、WOPI自体の認証で保護されています。

---

## 🔧 トラブルシューティング

### ポリシーを追加してもエラーが続く

1. **キャッシュをクリア**
   ```bash
   # ブラウザのキャッシュをクリア
   # Cloudflareのキャッシュをパージ
   ```

2. **ポリシーの順序を再確認**
   ```
   Bypassポリシーが最初に評価されているか？
   ```

3. **Pathの正規表現を確認**
   ```
   ^/index\.php/apps/richdocuments/wopi/.*
   ```
   
   または
   ```
   /index.php/apps/richdocuments/wopi/*
   ```

4. **Collaboraのログで実際のURLを確認**
   ```bash
   kubectl logs -n cloud-storage -l app=collabora | grep WOPI
   ```

### それでも解決しない場合

Cloudflare Accessアプリケーション全体を一時的に無効化して、Collaboraが動作するか確認：

1. NextCloudアプリケーションを`Disabled`にする
2. ドキュメントを開く
3. 動作したら、ポリシー設定の問題
4. 動作しない場合、別の問題

---

## 📊 動作確認

正しく設定されていれば、以下のログが表示されるはずです：

**成功時のCollaboraログ:**
```
INF  WOPI::CheckFileInfo success for URI [https://nextcloud.jarodbruce.f5.si/index.php/apps/richdocuments/wopi/files/...]
```

**失敗時（修正前）:**
```
ERR  WOPI::CheckFileInfo returned 404 (Not Found)
ERR  Access denied to CheckFileInfo
```

---

## 📚 参考リンク

- [WOPI Protocol Documentation](https://learn.microsoft.com/en-us/microsoft-365/cloud-storage-partner-program/rest/)
- [Cloudflare Access Bypass Rules](https://developers.cloudflare.com/cloudflare-one/policies/access/policy-management/#bypass)
- [NextCloud Collabora Integration](https://docs.nextcloud.com/server/latest/admin_manual/office/example-ubuntu.html)

---

**次のステップ:** 設定が完了したら、[運用とメンテナンス](../README.md#運用とメンテナンス)に進んでください。
