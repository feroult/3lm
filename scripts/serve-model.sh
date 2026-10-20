#!/usr/bin/env bash
# usage: serve-model.sh --repo ORG/REPO --file PATH[=LOCAL_NAME] [--file ...] -- <llama-server args>
#   PATH=LOCAL_NAME saves the file under another name in $MODELS_DIR (avoids collisions between repos that use the same file name).
# Downloads (resumable, with a lock) the files missing from $MODELS_DIR and then execs llama-server.
set -euo pipefail
MODELS_DIR="${MODELS_DIR:-/models}"
repo=""; files=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) repo="$2"; shift 2;;
    --file) files+=("$2"); shift 2;;
    --) shift; break;;
    *) echo "serve-model: invalid argument $1" >&2; exit 2;;
  esac
done
auth=(); [[ -n "${HF_TOKEN:-}" ]] && auth=(-H "Authorization: Bearer ${HF_TOKEN}")
base="${HF_ENDPOINT:-https://huggingface.co}"
mkdir -p "$MODELS_DIR"
exec 9>"$MODELS_DIR/.download.lock"
flock 9
for spec in "${files[@]}"; do
  f="${spec%%=*}"; local_name="$(basename "$f")"; [[ "$spec" == *=* ]] && local_name="${spec#*=}"
  dest="$MODELS_DIR/$local_name"
  if [[ -s "$dest" ]]; then echo "[serve-model] already present: $dest"; continue; fi
  echo "[serve-model] downloading $repo/$f -> $dest"
  until curl -fL --retry 5 --retry-delay 5 --retry-all-errors -C - "${auth[@]}" \
        -o "$dest.part" "$base/$repo/resolve/main/$f" -# 2>&1 | tr '\r' '\n' | awk 'NR%200==1{print "[serve-model] " $0; fflush()}'; do :; done
  [[ -s "$dest.part" ]] || { echo "[serve-model] download of $f failed" >&2; exit 1; }
  mv "$dest.part" "$dest"
done
flock -u 9; exec 9>&-
exec /app/llama-server "$@"
