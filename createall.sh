#!/bin/bash

PROJECT_DIR="$HOME/rl-swarm-0.5.3"
DESKTOP_DIR="$HOME/Desktop"

for script in gensyn_cli.sh nexus.sh ritual.sh wai.sh startAll.sh; do
  cmd_name="${script%.sh}.command"
  cat > "$DESKTOP_DIR/$cmd_name" <<EOF
#!/bin/bash
cd "$PROJECT_DIR"
./$script
EOF
  chmod +x "$DESKTOP_DIR/$cmd_name"
done

echo "✅ 已在桌面生成可双击运行的 .command 文件。"
