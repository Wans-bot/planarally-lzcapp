#!/bin/sh
# PlanarAlly 首装初始化（幂等）：建管理员账号 + 写基础 config.toml。
# 只发 HTTP 请求，不直接改数据库；重复执行结果相同，不会覆盖用户后来改过的配置。
# 镜像就是应用自己的镜像（自带 curl），脚本跑完常驻 sleep，容器保持 (healthy)。
set -u

BASE="${PA_BASE:-http://planarally:8000}"
USER_NAME="${LZC_ADMIN_USER:-admin}"
PASSWORD="${LZC_ADMIN_PASSWORD:-}"
CLIENT_URL="${LZC_CLIENT_URL:-}"
CONFIG_PATH="${PA_CONFIG_PATH:-/planarally/data/config.toml}"

ready=0
i=0
while [ "$i" -lt 120 ]; do
  if curl -fsS -o /dev/null "$BASE/api/version"; then
    ready=1
    echo "[init] 主服务已就绪（第 ${i} 次探测）"
    break
  fi
  i=$((i + 1))
  sleep 5
done

if [ "$ready" -ne 1 ]; then
  echo "[init] 主服务 600 秒内未就绪，跳过账号与配置初始化" >&2
else
  code=$(curl -s -o /tmp/pa-login.json -w '%{http_code}' -X POST "$BASE/api/login" \
    -H 'content-type: application/json' \
    -d "{\"username\":\"$USER_NAME\",\"password\":\"$PASSWORD\"}")
  if [ "$code" = "200" ]; then
    echo "[init] 管理员账号 $USER_NAME 已存在，跳过创建"
  else
    rcode=$(curl -s -o /tmp/pa-register.json -w '%{http_code}' -X POST "$BASE/api/register" \
      -H 'content-type: application/json' \
      -d "{\"username\":\"$USER_NAME\",\"password\":\"$PASSWORD\"}")
    echo "[init] 注册管理员账号 $USER_NAME -> HTTP $rcode"
    lcode=$(curl -s -o /tmp/pa-login.json -w '%{http_code}' -X POST "$BASE/api/login" \
      -H 'content-type: application/json' \
      -d "{\"username\":\"$USER_NAME\",\"password\":\"$PASSWORD\"}")
    echo "[init] 校验登录 -> HTTP $lcode"
  fi
fi

# config.toml：只在不存在时写，避免覆盖用户在界面里改过的设置。
# 字段名必须与上游 config/types.py 的 ServerConfig 一致，写错会让应用启动即退出。
if [ -f "$CONFIG_PATH" ]; then
  echo "[init] 已存在 $CONFIG_PATH，保留不覆盖"
else
  mkdir -p "$(dirname "$CONFIG_PATH")"
  cat > "$CONFIG_PATH" <<EOF
# 由懒猫 LPK 的 planarally-init 首次写入；应用界面里的改动会覆盖本文件。
[general]
save_file = "data/planar.sqlite"
client_url = "$CLIENT_URL"
allow_signups = true
enable_export = true
admin_user = "$USER_NAME"

[stats]
enabled = false
enable_export = false
EOF
  echo "[init] 已写入 $CONFIG_PATH（client_url=$CLIENT_URL）"
fi

# 常驻，避免容器反复退出；healthcheck 恒为 true。
while true; do
  sleep 3600
done
