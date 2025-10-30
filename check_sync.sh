#!/usr/bin/env bash
set -euo pipefail

# ====== CẤU HÌNH (sửa nếu cần) ======
SERVER="debian@148.113.10.170"
REMOTE_ROOT="/home/debian/plane-selfhost"

# ĐẶT ĐÚNG THƯ MỤC LOCAL MÀ MÀY ĐÃ ĐỒNG BỘ CODE VỀ:
LOCAL_ROOT="/Users/macbookpro/server-backups/plane-selfhost_2025-10-25"

# Exclude mặc định (bên build/cache/log, node_modules, .git, artifacts…)
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

# Tệp exclude tạm
EXC_FILE="$(mktemp)"
echo "$EXCLUDES" > "$EXC_FILE"

# Thư mục tạm
WORKDIR="$(mktemp -d)"
REMOTE_MANIFEST="$WORKDIR/remote.sha256"
LOCAL_MANIFEST="$WORKDIR/local.sha256"

say() { printf "\033[1;36m[INFO]\033[0m %s\n" "$*"; }
warn(){ printf "\033[1;33m[WARN]\033[0m %s\n" "$*"; }
err() { printf "\033[1;31m[ERR ]\033[0m %s\n" "$*"; }

# ====== Kiểm tra tồn tại thư mục ======
if [[ ! -d "$LOCAL_ROOT" ]]; then
  err "LOCAL_ROOT không tồn tại: $LOCAL_ROOT"
  exit 2
fi

say "Local  : $LOCAL_ROOT"
say "Remote : $SERVER:$REMOTE_ROOT"
say "Exclude patterns:\n$(cat "$EXC_FILE")"

# ====== 1) So sánh nhanh bằng rsync dry-run hướng remote -> local ======
say "rsync --dry-run --checksum (remote ➜ local)…"
RSYNC_OUT_1="$WORKDIR/rsync_r2l.txt"
set +e
rsync -avzi --checksum --delete \
  -e "ssh -o Compression=yes -o StrictHostKeyChecking=no" \
  --exclude-from="$EXC_FILE" \
  "$SERVER:$REMOTE_ROOT/" "$LOCAL_ROOT/" > "$RSYNC_OUT_1"
RC1=$?
set -e

# ====== 2) So sánh nhanh bằng rsync dry-run hướng local -> remote ======
say "rsync --dry-run --checksum (local ➜ remote)…"
RSYNC_OUT_2="$WORKDIR/rsync_l2r.txt"
set +e
rsync -avzi --checksum --delete \
  -e "ssh -o Compression=yes -o StrictHostKeyChecking=no" \
  --exclude-from="$EXC_FILE" \
  "$LOCAL_ROOT/" "$SERVER:$REMOTE_ROOT/" > "$RSYNC_OUT_2"
RC2=$?
set -e

# In tóm tắt thay đổi (chỉ in nếu có)
if [[ -s "$RSYNC_OUT_1" ]]; then
  warn "Khác biệt (remote ➜ local):"
  sed -n '1,120p' "$RSYNC_OUT_1"
fi
if [[ -s "$RSYNC_OUT_2" ]]; then
  warn "Khác biệt (local ➜ remote):"
  sed -n '1,120p' "$RSYNC_OUT_2"
fi

# ====== 3) Manifest SHA256: Remote ======
say "Tạo manifest SHA256 (remote)… chờ chút (lọc theo exclude)…"
ssh -o Compression=yes -o StrictHostKeyChecking=no "$SERVER" bash << 'EOSSH' > "$WORKDIR/_remote_list.txt"
set -euo pipefail
cd "'"$REMOTE_ROOT"'"
# Xuất danh sách file, loại bỏ theo các pattern thủ công (đơn giản, an toàn)
# Lưu ý: find không hiểu glob ** nên loại ở bước grep -v
find . -type f -print0
EOSSH

# Lọc exclude cho remote list
python3 - "$EXC_FILE" "$WORKDIR/_remote_list.txt" "$WORKDIR/_remote_list_f.txt" << 'PY'
import sys, fnmatch
exc = [l.strip() for l in open(sys.argv[1]) if l.strip() and not l.startswith('#')]
keep = []
with open(sys.argv[2], 'rb') as f:
    for path in f.read().split(b'\0'):
        if not path: continue
        p = path.decode('utf-8', 'ignore')
        norm = p.lstrip('./')
        skip = False
        for pat in exc:
            pat = pat.rstrip('/')
            if fnmatch.fnmatch(norm, pat) or norm.startswith(pat.rstrip('/') + '/'):
                skip = True; break
        if not skip:
            keep.append(p)
open(sys.argv[3],'wb').write(b'\0'.join(x.encode() for x in keep))
PY

# Tính sha256 remote theo danh sách đã lọc
ssh -o Compression=yes -o StrictHostKeyChecking=no "$SERVER" bash << EOSSH > "$REMOTE_MANIFEST"
set -euo pipefail
cd "$REMOTE_ROOT"
python3 - << 'PY2'
import sys, hashlib, os
import sys
def sha256_file(fp):
    h=hashlib.sha256()
    with open(fp,'rb') as f:
        for ch in iter(lambda: f.read(1024*1024), b''):
            h.update(ch)
    return h.hexdigest()
# đọc danh sách file qua stdin? ta sẽ cat từ local
PY2
EOSSH

# Do không truyền được null-list dễ trực tiếp, ta đẩy nội dung file danh sách tạm rồi tính trên remote
scp -q "$WORKDIR/_remote_list_f.txt" "$SERVER:/tmp/_list_remote_$$.nul"
ssh -o StrictHostKeyChecking=no "$SERVER" bash -s >> "$REMOTE_MANIFEST" << 'EOSSH'
set -euo pipefail
cd "'"$REMOTE_ROOT"'"
python3 - << 'PY'
import hashlib, sys, os
lst_file = "/tmp/_list_remote_$$.nul".replace('$$', str(os.getpid()))
# tìm file vừa scp: không biết pid phía local => dò theo glob
import glob
cands = glob.glob("/tmp/_list_remote_*\.nul")
if not cands:
    sys.exit(1)
lst_file = sorted(cands, key=os.path.getmtime)[-1]
with open(lst_file, 'rb') as f:
    items = [p for p in f.read().split(b'\0') if p]
items = [i.decode('utf-8','ignore').lstrip('./') for i in items]
def sha256(fp):
    h=hashlib.sha256()
    with open(fp,'rb') as f:
        for ch in iter(lambda: f.read(1024*1024), b''):
            h.update(ch)
    return h.hexdigest()
pairs = []
for rel in items:
    if not os.path.isfile(rel): 
        continue
    pairs.append((rel, sha256(rel)))
pairs.sort()
for rel, digest in pairs:
    print(f"{digest}  {rel}")
PY
EOSSH

# ====== 4) Manifest SHA256: Local ======
say "Tạo manifest SHA256 (local)…"
python3 - "$EXC_FILE" "$LOCAL_ROOT" "$LOCAL_MANIFEST" << 'PY'
import sys, os, fnmatch, hashlib
exc = [l.strip() for l in open(sys.argv[1]) if l.strip() and not l.startswith('#')]
root = sys.argv[2]
pairs = []
for base, dirs, files in os.walk(root):
    # bỏ nhanh các thư mục exclude ở cấp walk
    drop = []
    for d in list(dirs):
        p = os.path.relpath(os.path.join(base,d), root)
        norm = p.replace('\\','/')
        skip=False
        for pat in exc:
            pat = pat.rstrip('/')
            if fnmatch.fnmatch(norm, pat) or norm.startswith(pat + '/'):
                skip=True; break
        if skip:
            drop.append(d)
    for d in drop:
        dirs.remove(d)
    for f in files:
        rel = os.path.relpath(os.path.join(base,f), root).replace('\\','/')
        # lọc file theo pattern
        skip=False
        for pat in exc:
            if fnmatch.fnmatch(rel, pat):
                skip=True; break
        if skip: 
            continue
        # sha256
        h=hashlib.sha256()
        with open(os.path.join(root, rel), 'rb') as fp:
            for ch in iter(lambda: fp.read(1024*1024), b''):
                h.update(ch)
        pairs.append((rel, h.hexdigest()))
pairs.sort()
with open(sys.argv[3],'w') as out:
    for rel,dig in pairs:
        out.write(f"{dig}  {rel}\n")
PY

# ====== 5) Thống kê tổng quan ======
say "Thống kê tổng quan:"
ssh -o StrictHostKeyChecking=no "$SERVER" "du -sb \"$REMOTE_ROOT\" 2>/dev/null || du -sk \"$REMOTE_ROOT\"" | awk '{print "Remote size :", $1}'
du -sb "$LOCAL_ROOT" 2>/dev/null || du -sk "$LOCAL_ROOT" | awk '{print "Local  size :", $1}'
ssh -o StrictHostKeyChecking=no "$SERVER" "find \"$REMOTE_ROOT\" -type f | wc -l" | awk '{print "Remote files:", $1}'
find "$LOCAL_ROOT" -type f | wc -l | awk '{print "Local  files:", $1}'
ssh -o StrictHostKeyChecking=no "$SERVER" "find \"$REMOTE_ROOT\" -type d | wc -l" | awk '{print "Remote dirs :", $1}'
find "$LOCAL_ROOT" -type d | wc -l | awk '{print "Local  dirs :", $1}'

# ====== 6) So khớp manifest ======
say "So sánh manifest SHA256…"
DIFF_OUT="$WORKDIR/manifest.diff"
set +e
diff -u "$REMOTE_MANIFEST" "$LOCAL_MANIFEST" > "$DIFF_OUT"
RC_DIFF=$?
set -e

if [[ $RC_DIFF -ne 0 ]]; then
  warn "Manifest khác nhau! (in 120 dòng đầu)"
  sed -n '1,120p' "$DIFF_OUT"
else
  say "Manifest KHỚP HOÀN TOÀN ✅"
fi

# ====== 7) Kết luận dựa trên cả rsync và manifest ======
NEED_FIX=0
if [[ -s "$RSYNC_OUT_1" || -s "$RSYNC_OUT_2" ]]; then
  NEED_FIX=1
fi
if [[ $RC_DIFF -ne 0 ]]; then
  NEED_FIX=1
fi

if [[ $NEED_FIX -eq 0 ]]; then
  say "KẾT LUẬN: Hai bên ĐỒNG BỘ 100% ✅"
  exit 0
else
  err "KẾT LUẬN: CÒN KHÁC BIỆT ❌ — xem phần rsync và diff ở trên để xử lý."
  echo
  echo "GỢI Ý SỬA NHANH:"
  echo "1) Đồng bộ remote ➜ local (chỉ những file khác):"
  echo "   rsync -avz --delete -e \"ssh\" --exclude-from=\"$EXC_FILE\" \"$SERVER:$REMOTE_ROOT/\" \"$LOCAL_ROOT/\""
  echo "2) Hoặc local ➜ remote:"
  echo "   rsync -avz --delete -e \"ssh\" --exclude-from=\"$EXC_FILE\" \"$LOCAL_ROOT/\" \"$SERVER:$REMOTE_ROOT/\""
  exit 3
fi

