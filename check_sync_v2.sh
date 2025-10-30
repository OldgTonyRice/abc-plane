#!/usr/bin/env bash
set -euo pipefail

# === CẤU HÌNH ===
SERVER="debian@148.113.10.170"
REMOTE_ROOT="/home/debian/plane-selfhost"
LOCAL_ROOT="/Users/macbookpro/server-backups/plane-selfhost_2025-10-25"

# Exclude
read -r -d '' EXCLUDES << 'EOF' || true
.git/
**/node_modules/
**/.pnpm-store/
**/.turbo/
**/.next/
**/dist/
**/build/
**/.cache/
**/.gradle/
**/.idea/
**/.DS_Store
**/*.log
**/tmp/
**/.pytest_cache/
**/__pycache__/
**/*.pyc
**/coverage/
uploads/tmp/
EOF

EXC_FILE="$(mktemp)"; trap 'rm -f "$EXC_FILE"' EXIT
echo "$EXCLUDES" > "$EXC_FILE"

say(){ printf "\033[1;36m[INFO]\033[0m %s\n" "$*"; }
warn(){ printf "\033[1;33m[WARN]\033[0m %s\n" "$*"; }
err(){ printf "\033[1;31m[ERR ]\033[0m %s\n" "$*"; }

[[ -d "$LOCAL_ROOT" ]] || { err "LOCAL_ROOT không tồn tại: $LOCAL_ROOT"; exit 2; }

say "Local  : $LOCAL_ROOT"
say "Remote : $SERVER:$REMOTE_ROOT"
say "Exclude patterns:\n$(cat "$EXC_FILE")"

# Flags: -n (dry-run), --checksum (so sánh nội dung), --delete (so scope giống nhau)
# BỎ set time/perms để tránh permission error: --no-times --omit-dir-times --no-perms
RSYNC_FLAGS="-avzni --checksum --delete --no-times --omit-dir-times --no-perms \
  -e \"ssh -o Compression=yes -o StrictHostKeyChecking=no\" --exclude-from=\"$EXC_FILE\""

# 1) Remote -> Local
say "rsync DRY-RUN (remote ➜ local)…"
CMD1="rsync $RSYNC_FLAGS \"$SERVER:$REMOTE_ROOT/\" \"$LOCAL_ROOT/\""
DIFF_R2L="$(eval "$CMD1" || true)"

# 2) Local -> Remote
say "rsync DRY-RUN (local ➜ remote)…"
CMD2="rsync $RSYNC_FLAGS \"$LOCAL_ROOT/\" \"$SERVER:$REMOTE_ROOT/\""
DIFF_L2R="$(eval "$CMD2" || true)"

NEED_FIX=0

if [[ -n "$DIFF_R2L" ]]; then
  warn "Khác biệt (remote ➜ local):"
  echo "$DIFF_R2L" | sed -n '1,120p'
  NEED_FIX=1
fi

if [[ -n "$DIFF_L2R" ]]; then
  warn "Khác biệt (local ➜ remote):"
  echo "$DIFF_L2R" | sed -n '1,120p'
  NEED_FIX=1
fi

# Thống kê nhanh (không bắt buộc)
say "Thống kê nhanh:"
ssh -o StrictHostKeyChecking=no "$SERVER" "du -sb \"$REMOTE_ROOT\" 2>/dev/null || du -sk \"$REMOTE_ROOT\"" | awk '{print "Remote size :", $1}'
du -sb "$LOCAL_ROOT" 2>/dev/null || du -sk "$LOCAL_ROOT" | awk '{print "Local  size :", $1}'

if [[ $NEED_FIX -eq 0 ]]; then
  say "KẾT LUẬN: Hai bên ĐỒNG BỘ 100% ✅"
  exit 0
else
  err "KẾT LUẬN: CÒN KHÁC BIỆT ❌ — xem diff ở trên."
  echo
  echo "GỢI Ý SỬA NHANH:"
  echo "1) Kéo về (remote ➜ local) đúng theo exclude:"
  echo "   rsync -avz --checksum --delete --no-times --omit-dir-times --no-perms \\"
  echo "     -e \"ssh\" --exclude-from=\"$EXC_FILE\" \\"
  echo "     \"$SERVER:$REMOTE_ROOT/\" \"$LOCAL_ROOT/\""
  echo "2) Đẩy lên (local ➜ remote):"
  echo "   rsync -avz --checksum --delete --no-times --omit-dir-times --no-perms \\"
  echo "     -e \"ssh\" --exclude-from=\"$EXC_FILE\" \\"
  echo "     \"$LOCAL_ROOT/\" \"$SERVER:$REMOTE_ROOT/\""
  exit 3
fi

