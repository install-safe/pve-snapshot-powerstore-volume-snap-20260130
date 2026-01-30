#!/bin/bash

# 定義連動腳本位置
HOOK_SCRIPT="/usr/local/bin/powerstore-hook.sh"

echo "Starting PVE Snapshot Monitor (Exact Log Match) for PowerStore..."

# 監控 journal 輸出
journalctl -u pvedaemon -f -n 0 | while read line; do
    # 匹配結尾包含 qmsnapshot 且狀態為 OK 的行
    if echo "$line" | grep -q "end task" && echo "$line" | grep -q "qmsnapshot" && echo "$line" | grep -q "OK"; then
        
        # 根據您的日誌格式: <UPID>:<TASK>:<VMID>:<USER>: OK
        # 我們用冒號切分，VMID 通常在倒數第三個欄位
        VMID=$(echo "$line" | awk -F: '{print $(NF-2)}')

        # 安全檢查：確保 VMID 是純數字
        if [[ "$VMID" =~ ^[0-9]+$ ]]; then
            echo "[$(date)] Match Found! VMID: $VMID. Triggering PowerStore Linkage..."
            # 異步執行 Hook，避免阻塞監控迴圈
            $HOOK_SCRIPT post-snapshot "$VMID" >> /var/log/pve-powerstore-linkage.log 2>&1 &
        else
            echo "[$(date)] Warning: Could not parse VMID from line: $line"
        fi
    fi
done
