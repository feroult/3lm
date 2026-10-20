set -e
cd /models
get() { f=$2; [ -f "$f" ] && { echo "already present: $f"; return; }; curl -fL --retry 3 -o "$f.part" "https://huggingface.co/$1/resolve/main/$f" && mv "$f.part" "$f" && ls -la "$f"; }
get unsloth/Qwen3.5-0.8B-GGUF Qwen3.5-0.8B-Q8_0.gguf
get unsloth/Qwen3.5-2B-GGUF Qwen3.5-2B-Q4_K_M.gguf
get empero-ai/Qwen3.8-2B-Distill-GGUF Qwen3.8-2B-Q4_K_M.gguf
