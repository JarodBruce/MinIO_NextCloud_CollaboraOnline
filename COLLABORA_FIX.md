# Collabora + Cloudflare Access エラー修正

## 🐛 問題

CollaboraでNextCloudのドキュメントを開こうとすると、以下のエラーが発生します：

```
ERR  WOPI::CheckFileInfo returned 404 (Not Found)
ERR  Access denied to CheckFileInfo
```

## 🚀 クイックフィックス

自動スクリプトを実行：

```bash
./fix-collabora-access.sh
```

このスクリプトは以下を実行します：
1. Collaboraの設定を更新
2. Collabora Podを再起動
3. Cloudflare Access設定の手順を表示

## 📝 手動設定（Cloudflare Dashboard）

スクリプト実行後、以下を手動で設定してください：

### 1. Cloudflare Zero Trust Dashboardにアクセス

```
https://one.dash.cloudflare.com/
```

### 2. NextCloudアプリケーションを編集

`Access` → `Applications` → `NextCloud` → `Edit`

### 3. 新しいBypassポリシーを追加

**重要:** 既存のポリシーの**前に**追加してください（順序が重要）

| 項目 | 設定値 |
|------|--------|
| **ポリシー名** | `Bypass WOPI endpoints` |
| **Action** | `Bypass` |
| **Include** | Selector: `Everyone` |
| **Require** | Selector: `Path`<br>Value: `/index.php/apps/richdocuments/wopi/*`<br>Operator: `matches regex` |

正規表現:
```
^/index\.php/apps/richdocuments/wopi/.*
```

### 4. 確認

Applications一覧に2つのアプリケーションが表示されます：

```
1. NextCloud (既存)
   - Domain: nextcloud.jarodbruce.f5.si
   - Path: / (すべてのパス)
   - Policy: 認証あり

2. NextCloud WOPI (No Auth) (新規)
   - Domain: nextcloud.jarodbruce.f5.si
   - Path: /index.php/apps/richdocuments/wopi
   - Policy: Bypass（認証なし）
```

これで、WOPIパスのみが認証をバイパスし、他のエンドポイントは保護されます。

### 5. 保存

`Save application` をクリックして、数分待ちます。

## ✅ 動作確認

### 1. NextCloudでドキュメントを開く

```
https://nextcloud.jarodbruce.f5.si
```

新しいドキュメントを作成、または既存のドキュメントを開きます。

### 2. Collaboraログを確認

```bash
kubectl logs -n cloud-storage -l app=collabora -f --tail=50
```

**成功時:**
```
✅ INF  WOPI::CheckFileInfo success for URI [https://nextcloud.jarodbruce.f5.si/...]
```

**失敗時（まだエラーの場合）:**
```
❌ ERR  WOPI::CheckFileInfo returned 404 (Not Found)
❌ ERR  Access denied to CheckFileInfo
```

## 🔧 トラブルシューティング

### エラーが続く場合

1. **ポリシーの順序を再確認**
   - Bypassポリシーが最初に評価されているか？

2. **キャッシュをクリア**
   ```bash
   # ブラウザのキャッシュをクリア（Ctrl+Shift+Delete）
   ```
   
   Cloudflare Dashboard:
   - `Caching` → `Configuration` → `Purge Everything`

3. **正規表現をテスト**
   
   実際のWOPI URL例:
   ```
   /index.php/apps/richdocuments/wopi/files/7_oc0dihrf5f45
   ```
   
   正規表現:
   ```
   ^/index\.php/apps/richdocuments/wopi/.*
   ```
   
   [Regex101](https://regex101.com/)でテストできます。

4. **Collaboraが使用している実際のURLを確認**
   ```bash
   kubectl logs -n cloud-storage -l app=collabora | grep "WOPI::CheckFileInfo"
   ```

5. **一時的にCloudflare Accessを無効化してテスト**
   - NextCloudアプリケーションを`Disabled`にする
   - ドキュメントを開く
   - 動作すれば、ポリシー設定の問題

### それでも解決しない場合

詳細なガイドを参照：

```bash
cat docs/COLLABORA_CLOUDFLARE_ACCESS_FIX.md
```

または、[オンラインドキュメント](./docs/COLLABORA_CLOUDFLARE_ACCESS_FIX.md)を参照してください。

## 🔒 セキュリティについて

**Q: WOPIエンドポイントをバイパスしても安全ですか？**

**A: はい、安全です。**

WOPIプロトコル自体に認証機構があります：
- NextCloudが一時的な`access_token`を生成
- Collaboraはこのトークンでアクセス
- トークンは短時間で期限切れ
- トークンなしではファイルにアクセス不可

つまり、Cloudflare Accessをバイパスしても、WOPI自体の認証で保護されています。

## 📚 関連ドキュメント

- [詳細な修正ガイド](./docs/COLLABORA_CLOUDFLARE_ACCESS_FIX.md)
- [Cloudflare Access設定](./docs/CLOUDFLARE_ACCESS_SETUP.md)
- [WOPI Protocol](https://learn.microsoft.com/en-us/microsoft-365/cloud-storage-partner-program/rest/)

---

**問題が解決しない場合:** [GitHub Issues](https://github.com/JarodBruce/MinIO_NextCloud_CollaboraOnline/issues) で質問してください。
