#!/bin/bash

# 1. 获取当前终端的窗口ID并关闭其他终端窗口（排除当前终端）
current_window_id=$(osascript -e 'tell app "Terminal" to id of front window')
echo "当前终端窗口ID: $current_window_id，正在保护此终端不被关闭..."

osascript <<EOF
tell application "Terminal"
    activate
    set windowList to every window
    repeat with theWindow in windowList
        if id of theWindow is not ${current_window_id} then
            try
                close theWindow saving no
            end try
        end if
    end repeat
end tell
EOF
sleep 2

# 2. 启动VPN（新终端窗口，放在最左下角使底部与nexus对齐，长度1/2，宽度2/3）
osascript -e 'tell app "Terminal" to do script "~/shell/quickq_auto.sh"'
echo "✅ VPN已启动，等待2秒后启动Docker..."
sleep 2

# 获取屏幕尺寸
screen_size=$(osascript -e 'tell application "Finder" to get bounds of window of desktop')
read -r x1 y1 x2 y2 <<< $(echo $screen_size | tr ',' ' ')
width=$((x2-x1))
height=$((y2-y1))

# 窗口排列函数
function arrange_window {
    local title=$1
    local x=$2
    local y=$3
    local w=$4
    local h=$5
    
    osascript <<EOF
tell application "Terminal"
    set targetWindow to first window whose name contains "${title}"
    set bounds of targetWindow to {${x}, ${y}, ${x}+${w}, ${y}+${h}}
end tell
EOF
}

# 布局参数
spacing=20  # 间距20px
upper_height=$((height/2-2*spacing))  # 上层高度总共减少40px
lower_height=$((height/2-2*spacing))  # 下层高度总共减少40px
lower_y=$((y1+upper_height+2*spacing))  # 下层基准位置下移40px

# 上层布局（gensyn和wai）
upper_item_width=$(( (width-spacing)/2 ))  # 上层两个窗口的参考宽度，中间留20px间距

# 下层布局（quickq、nexus、Ritual）
# quickq宽度为item_width的2/3，高度为lower_height的1/2，剩余空间由nexus和Ritual平分
item_width=$(( (width-2*spacing)/3 ))  # 参考宽度（按3等分计算）
quickq_width=$((item_width*2/3))  # quickq宽度为参考宽度的2/3
quickq_height=$((lower_height/2))  # quickq高度为下层高度的1/2
lower_remaining_width=$((width-quickq_width-2*spacing))  # 下层剩余宽度
lower_item_width=$((lower_remaining_width/2))  # nexus和Ritual平分剩余宽度

# quickq底部与nexus对齐
nexus_ritual_height=$((lower_height-30))  # nexus和Ritual高度减小30px
nexus_ritual_y=$((lower_y+5))  # nexus和Ritual向下移动5px
quickq_y=$((nexus_ritual_y+nexus_ritual_height-quickq_height))  # quickq底部与nexus对齐

# wai宽度缩小1/2，高度保持不变（1倍）
wai_width=$((upper_item_width/2))  # wai宽度缩小为原来1/2
wai_height=$upper_height  # wai高度保持不变

# 3. 启动Docker（不新建终端窗口）
echo "✅ 正在后台启动Docker..."
open -a Docker --background

# 等待Docker完全启动
echo "⏳ 等待Docker服务就绪..."
until docker info >/dev/null 2>&1; do sleep 1; done
sleep 30  # 额外等待确保完全启动

# 4. 启动gensyn（上层左侧，向右偏移半个身位）
osascript -e 'tell app "Terminal" to do script "until docker info >/dev/null 2>&1; do sleep 1; done && ~/shell/gensyn.sh"'
sleep 1
arrange_window "gensyn" $((x1+upper_item_width/2)) $y1 $upper_item_width $upper_height

# 5. 启动wai（上层右侧，向右偏移半个身位，宽度缩小1/2，高度不变）
osascript -e 'tell app "Terminal" to do script "~/shell/wai.sh"'
sleep 1
arrange_window "wai" $((x1+upper_item_width+spacing+upper_item_width/2)) $y1 $wai_width $wai_height

# 6. 启动nexus（下层中间，高度减小30px，向下移动5px）
osascript -e 'tell app "Terminal" to do script "~/shell/nexus.sh"'
sleep 1
arrange_window "nexus" $((x1+quickq_width+spacing)) $nexus_ritual_y $lower_item_width $nexus_ritual_height

# 7. 启动Ritual（下层右侧，高度减小30px，向下移动5px）
osascript -e 'tell app "Terminal" to do script "~/shell/Ritual.sh"'
sleep 1
arrange_window "Ritual" $((x1+quickq_width+lower_item_width+2*spacing)) $nexus_ritual_y $lower_item_width $nexus_ritual_height

# 8. 排列VPN窗口（最左下角，底部与nexus对齐，长度1/2，宽度2/3）
arrange_window "quickq" $x1 $quickq_y $quickq_width $quickq_height

echo "✅ 所有项目已启动完成！"
echo "   - Docker已在后台运行"
echo "   - quickq窗口位于最左下角（底部与nexus对齐）"
echo "   - gensyn窗口向右偏移半个身位"
echo "   - wai窗口向右偏移半个身位，宽度缩小1/2，高度不变"
echo "   - nexus和Ritual高度减小30px，向下移动5px"
echo "   - 其他应用窗口已按布局打开（包含Ritual）"
echo "   - 当前终端已保护，未被关闭"
