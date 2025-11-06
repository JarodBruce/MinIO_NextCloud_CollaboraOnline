# セキュリティ向上：環境変数ファイルへの移行

## 概要

このアップデートにより、機密情報（Cloudflare Tunnel Token）をGitHubリポジトリから分離し、`.env`ファイルで管理するようになりました。

## 変更内容

### 新規ファイル

1. **`.env.example`** - 環境変数のテンプレートファイル
   - GitHubにプッシュ可能
   - 実際の値は含まれていない
   - 新規セットアップ時にコピーして使用

2. **`.env`** - 実際の環境変数ファイル
   - `.gitignore`で除外済み
   - 機密情報を含む
   - GitHubにプッシュされない

3. **`.gitignore`** - Gitで無視するファイルのリスト
   - `.env`ファイルを除外
   - その他の機密ファイルも除外

### 変更されたファイル

1. **`k8s/06-cloudflare-tunnel.yaml`**
   - 変更前：トークンがYAMLファイルにハードコード
   - 変更後：Secretは`deploy.sh`スクリプトで動的に生成
   - コメントで手動適用方法も記載

2. **`deploy.sh`**
   - `.env`ファイルから環境変数を自動読み込み
   - `TUNNEL_TOKEN`を使用してKubernetes Secretを動的に生成
   - `.env`ファイルがない場合はエラーメッセージを表示

3. **`README.md`**
   - セットアップ手順を更新
   - `.env`ファイルの作成手順を追加
   - セキュリティのベストプラクティスセクションを追加

## 使用方法

### 新規セットアップ

```bash
# 1. リポジトリをクローン
git clone https://github.com/JarodBruce/MinIO_NextCloud_CollaboraOnline.git
cd MinIO_NextCloud_CollaboraOnline

# 2. .envファイルを作成
cp .env.example .env

# 3. .envファイルを編集してTUNNEL_TOKENを設定
nano .env
# TUNNEL_TOKEN=your_actual_token_here

# 4. デプロイ実行
./deploy.sh
```

### 既存環境からの移行

既にデプロイ済みの場合：

```bash
# 1. 現在のトークンをバックアップ
kubectl get secret cloudflare-tunnel-token -n cloud-storage -o jsonpath='{.data.TUNNEL_TOKEN}' | base64 -d

# 2. .envファイルを作成
cp .env.example .env

# 3. バックアップしたトークンを.envに設定
nano .env
# TUNNEL_TOKEN=your_backed_up_token

# 4. yamlファイルから機密情報を削除
git pull origin main  # 最新版を取得

# 5. 再デプロイ（必要に応じて）
./deploy.sh
```

## セキュリティの利点

### Before（変更前）
```yaml
# k8s/06-cloudflare-tunnel.yaml
stringData:
  TUNNEL_TOKEN: "eyJhIjoiODQ2ZWFmZDUzNDI1M2Q1M2Q2ZTZiNzRhOWU3MTdiN2EiLCJ0..."
```
❌ トークンがGitHubに公開される  
❌ トークンが履歴に残る  
❌ フォークしたユーザーも機密情報にアクセス可能

### After（変更後）
```bash
# .env (ローカルのみ、Gitで管理されない)
TUNNEL_TOKEN=eyJhIjoiODQ2ZWFmZDUzNDI1M2Q1M2Q2ZTZiNzRhOWU3MTdiN2EiLCJ0...
```
✅ トークンはローカル環境のみに存在  
✅ GitHubに機密情報が公開されない  
✅ `.gitignore`で自動的に除外される  
✅ 環境ごとに異なるトークンを使用可能

## ファイル構造

```
MinIO_NextCloud_CollaboraOnline/
├── .env                    # 機密情報（Git管理外）
├── .env.example            # テンプレート（Git管理対象）
├── .gitignore              # Gitで無視するファイル
├── deploy.sh               # 更新：.envを読み込み
├── k8s/
│   └── 06-cloudflare-tunnel.yaml  # 更新：機密情報削除
└── README.md               # 更新：手順を追加
```

## トラブルシューティング

### エラー: `.env`ファイルが見つかりません

```bash
[WARNING] .envファイルが見つかりません
[INFO] .env.exampleをコピーして.envを作成してください
[INFO] cp .env.example .env
```

**解決方法:**
```bash
cp .env.example .env
nano .env  # TUNNEL_TOKENを設定
```

### エラー: `TUNNEL_TOKEN`が設定されていません

```bash
[WARNING] Cloudflare Tunnel Tokenが設定されていません
```

**解決方法:**
1. `.env`ファイルを開く
2. `TUNNEL_TOKEN=your_cloudflare_tunnel_token_here`を実際のトークンに置き換え
3. 保存して再実行

### 手動でSecretを作成する場合

スクリプトを使わず手動で適用する場合：

```bash
# .envを読み込み
source .env

# Secretを作成
kubectl create secret generic cloudflare-tunnel-token \
  --from-literal=TUNNEL_TOKEN="$TUNNEL_TOKEN" \
  -n cloud-storage \
  --dry-run=client -o yaml | kubectl apply -f -
```

## ベストプラクティス

### 開発環境

```bash
# .env
TUNNEL_TOKEN=dev_token_here
```

### ステージング環境

```bash
# .env
TUNNEL_TOKEN=staging_token_here
```

### 本番環境

```bash
# .env（適切な権限で保護）
TUNNEL_TOKEN=production_token_here

# 権限設定
chmod 600 .env
chown root:root .env
```

さらに、本番環境では：
- HashiCorp Vault
- Kubernetes Sealed Secrets
- AWS Secrets Manager
- Azure Key Vault
などの専門的なシークレット管理ツールの使用を推奨

## Git操作のヒント

### .envファイルが誤ってコミットされた場合

```bash
# 1. 履歴から削除
git filter-branch --force --index-filter \
  "git rm --cached --ignore-unmatch .env" \
  --prune-empty --tag-name-filter cat -- --all

# 2. 強制プッシュ（注意：チームメンバーに通知）
git push origin --force --all

# 3. Cloudflare Tunnel Tokenを再生成
# Cloudflareダッシュボードで新しいトンネルを作成
```

### 確認方法

```bash
# .envがGit管理されていないことを確認
git status

# .gitignoreが正しく設定されているか確認
git check-ignore -v .env
# 出力例: .gitignore:2:.env	.env
```

## まとめ

この変更により：
- ✅ 機密情報がGitHubに公開されない
- ✅ セキュリティが大幅に向上
- ✅ 環境ごとに異なる設定を簡単に管理
- ✅ フォークしたユーザーも安全に使用可能
- ✅ ベストプラクティスに準拠

リポジトリを公開する準備が整いました！
