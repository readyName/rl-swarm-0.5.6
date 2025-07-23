#!/bin/bash

# 定义两个可能的 QuickQ 路径
APP_PATH1="/Applications/QuickQ For Mac.app"
APP_PATH2="/Applications/QuickQ.app"

# 动态检测可用路径
if [ -d "$APP_PATH1" ]; then
    APP_PATH="$APP_PATH1"
    APP_NAME="QuickQ For Mac"
    echo "[$(date +"%T")] 检测到应用：$APP_PATH1"
elif [ -d "$APP_PATH2" ]; then
    APP_PATH="$APP_PATH2"
    APP_NAME="QuickQ"
    echo "[$(date +"%T")] 检测到应用：$APP_PATH2"
else
    echo "[$(date +"%T")] 错误：未找到 QuickQ 应用（检查路径 $APP_PATH1 和 $APP_PATH2）"
    exit 1
fi

# 坐标参数
LEFT_X=1520
DROP_DOWN_BUTTON_X=200
DROP_DOWN_BUTTON_Y=430
CONNECT_BUTTON_X=200
CONNECT_BUTTON_Y=260
SETTINGS_BUTTON_X=349
SETTINGS_BUTTON_Y=165

# ALCHEMY_URL 和主机名
ALCHEMY_HOST="gensyn-testnet.g.alchemy.com"
ALCHEMY_URL="https://gensyn-testnet.g.alchemy.com/public"

# 检查 Homebrew 是否安装
if ! command -v brew &> /dev/null; then
    echo "[$(date +"%T")] 错误：未找到 Homebrew，请先安装 Homebrew (https://brew.sh)"
    exit 1
fi

# 检查 cliclick 依赖
if ! command -v cliclick &> /dev/null; then
    echo "[$(date +"%T")] 正在通过 Homebrew 安装 cliclick..."
    brew install cliclick
    if [ $? -ne 0 ]; then
        echo "[$(date +"%T")] 错误：cliclick 安装失败"
        exit 1
    fi
    echo "[$(date +"%T")] cliclick 安装完成"
fi

# 检查 nc（netcat）依赖
if ! command -v nc &> /dev/null; then
    echo "[$(date +"%T")] 正在通过 Homebrew 安装 netcat..."
    brew install netcat
    if [ $? -ne 0 ]; then
        echo "[$(date +"%T")] 错误：netcat 安装失败"
        exit 1
    fi
    echo "[$(date +"%T")] netcat 安装完成"
else
    echo "[$(date +"%T")] 检测到 netcat 已安装，跳过安装"
fi

# 一次性权限触发操作
if [ ! -f "/tmp/quickq_permissions_triggered" ]; then
    echo "[$(date +"%T")] 正在执行一次性权限触发操作..."
    open "$APP_PATH"
    sleep 5
    osascript -e "tell application \"$APP_NAME\" to activate"
    sleep 1
    adjust_window
    cliclick c:${SETTINGS_BUTTON_X},${SETTINGS_BUTTON_Y}
    echo "[$(date +"%T")] 已触发点击事件，请检查系统权限请求"
    echo "[$(date +"%T")] 等待10秒以便您处理权限对话框..."
    sleep 10
    pkill -9 -f "$APP_NAME"
    touch "/tmp/quickq_permissions_triggered"
    echo "[$(date +"%T")] 权限触发完成，标记已设置"
fi

# 网络连通性检测函数
check_network_connectivity() {
    local PING_TIMEOUT=6
    local CURL_TIMEOUT=8
    local NC_TIMEOUT=5
    local success=false

    # 1. DNS 解析检查
    if host "$ALCHEMY_HOST" &> /dev/null; then
        echo "[$(date +"%T")] 网络检测：DNS 解析 $ALCHEMY_HOST 成功"
    else
        echo "[$(date +"%T")] 网络检测：DNS 解析 $ALCHEMY_HOST 失败"
        return 1
    fi

    # 2. HTTP/HTTPS 请求检查
    local http_code
    http_code=$(curl --silent --head --fail --max-time $CURL_TIMEOUT -w "%{http_code}" -o /dev/null "$ALCHEMY_URL")
    if [ "$http_code" -eq 200 ] || [ "$http_code" -eq 204 ]; then
        echo "[$(date +"%T")] 网络检测：HTTP 请求 $ALCHEMY_URL 成功 (HTTP $http_code)"
        success=true
    else
        echo "[$(date +"%T")] 网络检测：HTTP 请求 $ALCHEMY_URL 失败 (HTTP $http_code)"
    fi

    # 3. TCP 连接检查（443 端口）
    if nc -w $NC_TIMEOUT -z $ALCHEMY_HOST 443 &> /dev/null; then
        echo "[$(date +"%T")] 网络检测：TCP 连接 $ALCHEMY_HOST:443 成功"
        success=true
    else
        echo "[$(date +"%T")] 网络检测：TCP 连接 $ALCHEMY_HOST:443 失败"
    fi

    # 4. Ping 检查（作为辅助，ICMP 可能被禁用）
    if ping -c 1 -W $PING_TIMEOUT $ALCHEMY_HOST &> /dev/null; then
        echo "[$(date +"%T")] 网络检测：Ping $ALCHEMY_HOST 成功"
        success=true
    else
        echo "[$(date +"%T")] 网络检测：Ping $ALCHEMY_HOST 失败"
    fi

    # 只要任一检查成功，就认为网络连通
    if $success; then
        return 0
    else
        echo "[$(date +"%T")] 网络检测：所有检查均失败"
        return 1
    fi
}

# QuickQ VPN 状态检测函数
check_quickq_status() {
    local QUICKQ_LOG="${APP_PATH}/Contents/Resources/logs/connection.log"
    if [ -f "$QUICKQ_LOG" ]; then
        if grep -i "Connected" "$QUICKQ_LOG" &> /dev/null; then
            echo "[$(date +"%T")] QuickQ检测：VPN已连接"
            last_vpn_status="connected"
            return 0
        else
            echo "[$(date +"%T")] QuickQ检测：VPN未连接"
            last_vpn_status="disconnected"
            return 1
        fi
    else
        return 1
    fi
}

# VPN 状态检测函数
check_vpn_connection() {
    local TEST_URLS=(
        "https://www.google.com/generate_204"
        "https://www.youtube.com/generate_204"
    )
    local PING_TEST="8.8.8.8"
    local PING_TIMEOUT=6
    local CURL_TIMEOUT=8
    local MAX_RETRIES=3
    local retry_count=0

    # 检查网络连通性
    if ! check_network_connectivity; then
        echo "[$(date +"%T")] 网络连通性测试失败"
        return 1
    fi

    # 检查 QuickQ VPN 状态
    if check_quickq_status; then
        echo "[$(date +"%T")] VPN检测：QuickQ VPN 已连接"
        last_vpn_status="connected"
        return 0
    fi

    # 基础网络连通性测试（ping 8.8.8.8）
    if ! ping -c 1 -W $PING_TIMEOUT $PING_TEST &> /dev/null; then
        echo "[$(date +"%T")] 基础网络连通性测试失败（ping $PING_TEST）"
        last_vpn_status="disconnected"
        return 1
    fi

    # 轻量级 HTTP 204 测试
    while [ $retry_count -lt $MAX_RETRIES ]; do
        for url in "${TEST_URLS[@]}"; do
            local http_code
            http_code=$(curl --silent --head --fail --max-time $CURL_TIMEOUT -w "%{http_code}" -o /dev/null "$url")
            if [ "$http_code" -eq 204 ]; then
                echo "[$(date +"%T")] VPN检测：通过 $url (HTTP 204)"
                last_vpn_status="connected"
                return 0
            fi
        done
        ((retry_count++))
        echo "[$(date +"%T")] VPN检测失败（尝试 $retry_count/$MAX_RETRIES）"
        sleep 2
    done

    echo "[$(date +"%T")] VPN检测：所有轻量级端点均不可达"
    last_vpn_status="disconnected"
    return 1
}

# 窗口位置校准函数
adjust_window() {
    osascript <<EOF
    tell application "System Events"
        tell process "$APP_NAME"
            repeat 3 times
                if exists window 1 then
                    set position of window 1 to {0, 0}
                    set size of window 1 to {400, 300}
                    exit repeat
                else
                    delay 0.5
                end if
            end repeat
        end tell
    end tell
EOF
    echo "[$(date +"%T")] 窗口位置已校准"
    sleep 1
}

# 执行标准连接流程
connect_procedure() {
    osascript -e "tell application \"$APP_NAME\" to activate"
    sleep 0.5
    adjust_window
    cliclick c:${DROP_DOWN_BUTTON_X},${DROP_DOWN_BUTTON_Y}
    echo "[$(date +"%T")] 已点击下拉菜单"
    sleep 1
    cliclick c:${CONNECT_BUTTON_X},${CONNECT_BUTTON_Y}
    echo "[$(date +"%T")] 已发起连接请求"
    sleep 60
}

# 应用重启初始化流程
initialize_app() {
    echo "[$(date +"%T")] 执行初始化操作..."
    osascript -e "tell application \"$APP_NAME\" to activate"
    adjust_window
    cliclick c:${SETTINGS_BUTTON_X},${SETTINGS_BUTTON_Y}
    echo "[$(date +"%T")] 已点击设置按钮"
    sleep 2
    connect_procedure
}

# 安全终止应用
terminate_app() {
    echo "[$(date +"%T")] 正在停止应用..."
    pkill -9 -f "$APP_NAME" && echo "[$(date +"%T")] 已终止残留进程"
}

# 主循环
reconnect_count=0
last_vpn_status="disconnected"

while :; do
    if pgrep -f "$APP_NAME" &> /dev/null; then
        if check_vpn_connection; then
            if [ "$last_vpn_status" == "disconnected" ]; then
                echo "[$(date +"%T")] 状态变化：已建立VPN连接"
            fi
            reconnect_count=0
            total_wait=600
            while [ $total_wait -gt 0 ]; do
                remaining_min=$((total_wait / 60))
                echo "[$(date +"%T")] 下次检测将在 ${remaining_min} 分钟后进行..."
                sleep 60
                total_wait=$((total_wait - 60))
            done
            continue
        else
            echo "[$(date +"%T")] 检测到VPN未连接"
            if [ $reconnect_count -lt 3 ]; then
                connect_procedure
                ((reconnect_count++))
                echo "[$(date +"%T")] 重试次数：$reconnect_count/3"
                sleep 60
            else
                echo "[$(date +"%T")] 达到重试上限，执行应用重置"
                terminate_app
                open "$APP_PATH"
                echo "[$(date +"%T")] 应用启动中..."
                sleep 10
                initialize_app
                reconnect_count=0
                sleep 10
            fi
        fi
    else
        echo "[$(date +"%T")] 应用未运行，正在启动..."
        open "$APP_PATH"
        sleep 10
        initialize_app
    fi
    sleep 5
done