#!/bin/bash

# ポートフォワードを簡単に設定するためのヘルパースクリプト

NAMESPACE="cloud-storage"

show_menu() {
    echo "========================================="
    echo "ポートフォワード設定"
    echo "========================================="
    echo "1) MinIO Console (port 9001)"
    echo "2) NextCloud (port 8080)"
    echo "3) Collabora Online (port 9980)"
    echo "4) Nginx Proxy Manager (port 8081)"
    echo "5) 全て起動"
    echo "6) 終了"
    echo "========================================="
    echo -n "選択してください [1-6]: "
}

port_forward_minio() {
    echo "MinIO Consoleへのポートフォワードを開始します..."
    echo "アクセス: http://localhost:9001"
    kubectl port-forward -n $NAMESPACE svc/minio 9001:9001
}

port_forward_nextcloud() {
    echo "NextCloudへのポートフォワードを開始します..."
    echo "アクセス: http://localhost:8080"
    kubectl port-forward -n $NAMESPACE svc/nextcloud 8080:80
}

port_forward_collabora() {
    echo "Collabora Onlineへのポートフォワードを開始します..."
    echo "アクセス: http://localhost:9980"
    kubectl port-forward -n $NAMESPACE svc/collabora 9980:9980
}

port_forward_npm() {
    echo "Nginx Proxy Managerへのポートフォワードを開始します..."
    echo "アクセス: http://localhost:8081"
    kubectl port-forward -n $NAMESPACE svc/nginx-proxy-manager 8081:81
}

port_forward_all() {
    echo "全サービスへのポートフォワードをバックグラウンドで開始します..."
    
    kubectl port-forward -n $NAMESPACE svc/minio 9001:9001 &
    MINIO_PID=$!
    echo "MinIO Console: http://localhost:9001 (PID: $MINIO_PID)"
    
    kubectl port-forward -n $NAMESPACE svc/nextcloud 8080:80 &
    NC_PID=$!
    echo "NextCloud: http://localhost:8080 (PID: $NC_PID)"
    
    kubectl port-forward -n $NAMESPACE svc/collabora 9980:9980 &
    COLLAB_PID=$!
    echo "Collabora: http://localhost:9980 (PID: $COLLAB_PID)"
    
    kubectl port-forward -n $NAMESPACE svc/nginx-proxy-manager 8081:81 &
    NPM_PID=$!
    echo "Nginx Proxy Manager: http://localhost:8081 (PID: $NPM_PID)"
    
    echo ""
    echo "全てのポートフォワードが開始されました。"
    echo "停止するには: kill $MINIO_PID $NC_PID $COLLAB_PID $NPM_PID"
    echo "または: pkill -f 'kubectl port-forward'"
    echo ""
    echo "Ctrl+C で終了します..."
    
    # プロセスが終了するまで待機
    wait
}

# メインループ
while true; do
    show_menu
    read choice
    
    case $choice in
        1)
            port_forward_minio
            ;;
        2)
            port_forward_nextcloud
            ;;
        3)
            port_forward_collabora
            ;;
        4)
            port_forward_npm
            ;;
        5)
            port_forward_all
            ;;
        6)
            echo "終了します"
            exit 0
            ;;
        *)
            echo "無効な選択です"
            ;;
    esac
    
    echo ""
done
