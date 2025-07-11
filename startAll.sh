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

# 坐标参数说明：
# 连接操作坐标
LEFT_X=1520
DROP_DOWN_BUTTON_X=200  # 下拉按钮X  1720在右边 200在左边
DROP_DOWN_BUTTON_Y=430   # 下拉按钮Y
CONNECT_BUTTON_X=200    # 连接按钮X。1720在右边 200在左边
CONNECT_BUTTON_Y=260     # 连接按钮Y

# 初始化操作坐标
SETTINGS_BUTTON_X=349   # 设置按钮X   1869在右边。349在左边
SETTINGS_BUTTON_Y=165    # 设置按钮Y

# 检查 cliclick 依赖
if ! command -v cliclick &> /dev/null; then
    echo "正在通过Homebrew安装cliclick..."
    if ! command -v brew &> /dev/null; then
        echo "错误：请先安装Homebrew (https://brew.sh)"
        exit 1
    fi
    brew install cliclick
    
    echo "[$(date +"%T")] 依赖安装完成，正在执行一次性权限触发操作..."
    
    # 启动应用
    open "$APP_PATH"
    sleep 5  # 等待应用启动
    
    # 执行窗口调整和点击
    osascript -e "tell application \"$APP_NAME\" to activate"
    sleep 1
    
    # 窗口校准函数调用
    adjust_window
    
    # 点击设置按钮（触发权限请求）
    cliclick c:${SETTINGS_BUTTON_X},${SETTINGS_BUTTON_Y}
    echo "[$(date +"%T")] 已触发点击事件，请检查系统权限请求"
    echo "[$(date +"%T")] 等待10秒以便您处理权限对话框..."
    sleep 10
    
    # 安全终止应用（因为主循环会重新启动它）
    pkill -9 -f "$APP_NAME"
fi

# 以下是原有脚本内容，部分优化 ▼▼▼
reconnect_count=0
last_vpn_status="disconnected"

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

# VPN状态检测函数
check_vpn_connection() {
    local TEST_URLS=(
        "https://www.google.com"
        "https://x.com"
        "https://www.youtube.com"
    )
    local PING_TEST="8.8.8.8"
    local PING_TIMEOUT=6
    local CURL_TIMEOUT=8
    local MAX_RETRIES=3
    local retry_count=0

    if check_quickq_status; then
        return 0
    fi

    if ! ping -c 2 -W $PING_TIMEOUT $PING_TEST &> /dev/null; then
        echo "[$(date +"%T")] 基础网络连通性测试失败（ping $PING_TEST）"
        last_vpn_status="disconnected"
        return 1
    fi

    while [ $retry_count -lt $MAX_RETRIES ]; do
        for url in "${TEST_URLS[@]}"; do
            if curl --silent --head --fail --max-time $CURL_TIMEOUT "$url" &> /dev/null; then
                echo "[$(date +"%T")] VPN检测：可通过 $url"
                last_vpn_status="connected"
                return 0
            fi
        done
        ((retry_count++))
        echo "[$(date +"%T")] VPN检测失败，重试 $retry_count/$MAX_RETRIES"
        sleep 2
    done

    echo "[$(date +"%T")] VPN检测：所有测试站点均不可达"
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

while :; do
    if pgrep -f "$APP_NAME" &> /dev/null; then
        if check_vpn_connection; then
            if [ "$last_vpn_status" == "disconnected" ]; then
                echo "[$(date +"%T")] 状态变化：已建立VPN连接"
            fi
            reconnect_count=0
            total_wait=900
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
