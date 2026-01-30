#!/bin/bash

# --- 配置區 ---
PS_IP="192.168.236.80"
PS_USER="admin"
PS_PASS="Password123!"
VMID=$2
PHASE=$1
TARGET_VG="PSG-VG"

if [ "$PHASE" == "post-snapshot" ]; then
    echo "--- [PowerStore Linkage] Starting for VM $VMID ---"

    # 1. 取得 PSG-VG 所在的實體設備名稱 (例如 /dev/sdi)
    REAL_PV=$(pvs --noheadings -o pv_name,vg_name | grep "$TARGET_VG" | awk '{print $1}' | head -n 1 | tr -d '[:space:]')
    
    if [ -z "$REAL_PV" ]; then
        echo "Error: Could not find Physical Volume for $TARGET_VG"
        exit 1
    fi

    # 2. 取得該設備的 WWN 並進行字串清洗
    REAL_DM=$(readlink -f "$REAL_PV")
    WWN_NAME=$(ls -l /dev/disk/by-id/ | grep "wwn-0x" | grep "$(basename $REAL_DM)$" | awk '{print $9}' | head -n 1 | tr -d '[:space:]')
    
    if [ -z "$WWN_NAME" ]; then
        echo "Error: Could not find WWN in /dev/disk/by-id for $REAL_DM"
        exit 1
    fi

    # 去掉 wwn-0x，強制小寫，並移除所有換行或空白
    CLEAN_WWN=$(echo "$WWN_NAME" | sed 's/wwn-0x//' | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')
    PS_WWN="naa.${CLEAN_WWN}"
    
    echo "Target PowerStore WWN: [$PS_WWN]" # 使用中括號檢查有無隱藏空白

    # 3. 透過 API 取得 PowerStore Volume ID
    # 這裡加入 -s (silent) 並確保變數被正確引用
    API_URL="https://$PS_IP/api/rest/volume?select=id&wwn=eq.$PS_WWN"
    PS_VOLUME_ID=$(curl -k -s -u "$PS_USER:$PS_PASS" "$API_URL" | jq -r '.[0].id' | tr -d '[:space:]')

    if [ "$PS_VOLUME_ID" != "null" ] && [ -n "$PS_VOLUME_ID" ]; then
        # 4. 執行 PowerStore 硬體快照
        SNAP_NAME="PVE_VG_SNAP_${VMID}_$(date +%Y%m%d_%H%M)"
        EXPIRY=$(date -u -d "+24 hours" +"%Y-%m-%dT%H:%M:%SZ")

        echo "Creating Snapshot: $SNAP_NAME (Expires: $EXPIRY)"

        RESULT=$(curl -k -s -u "$PS_USER:$PS_PASS" \
             -X POST "https://$PS_IP/api/rest/volume/$PS_VOLUME_ID/snapshot" \
             -H "Content-Type: application/json" \
             -d "{\"name\": \"$SNAP_NAME\", \"description\": \"PVE VM $VMID Snapshot Linkage\", \"expiration_timestamp\": \"$EXPIRY\"}")
        
        # 簡單檢查回傳結果是否包含 id
        if echo "$RESULT" | grep -q "id"; then
            echo "SUCCESS: PowerStore Hardware Snapshot created."
        else
            echo "FAILED: API response: $RESULT"
        fi
    else
        echo "ERROR: PowerStore API could not find Volume ID for WWN $PS_WWN"
        echo "Debug: API URL was $API_URL"
    fi
fi
