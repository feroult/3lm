#!/usr/bin/env bash
# Validates the API. Usage: ./test.sh [BASE_URL] [MODEL]      (default: http://localhost:8080  coder)
#   or use the BASE_URL / MODEL variables.  API_KEY=...   EXEC_CONTAINER=coder-llm  (runs curl inside the container, internal port 8080)
#   Examples: ./test.sh http://localhost:8081            EXEC_CONTAINER=coder-llm-cpu ./test.sh
#   TIMEOUT=seconds per request (default 3600; answers are slow on CPU)
set -uo pipefail
BASE_URL="${1:-${BASE_URL:-http://localhost:8080}}"; MODEL="${2:-${MODEL:-coder}}"
MAXT="${MAX_TOKENS:-1500}"
fails=0
req() { # req METHOD PATH [json]
  local h=(-H "Content-Type: application/json"); [[ -n "${API_KEY:-}" ]] && h+=(-H "Authorization: Bearer $API_KEY")
  local d=(); [[ -n "${3:-}" ]] && d=(-d "$3")
  if [[ -n "${EXEC_CONTAINER:-}" ]]; then
    ${ENGINE:-podman} exec -i "$EXEC_CONTAINER" curl -sS --max-time "${TIMEOUT:-3600}" -X "$1" "${h[@]}" "${d[@]}" "http://127.0.0.1:${PORT:-8080}$2"
  else curl -sS --max-time "${TIMEOUT:-3600}" -X "$1" "${h[@]}" "${d[@]}" "$BASE_URL$2"; fi
}
ok()   { echo "  [OK]   $*"; }
fail() { echo "  [FAIL] $*"; fails=$((fails+1)); }
py()   { python3 -I -c "$1"; }

echo "== 1. /health"
out=$(req GET /health) && [[ "$out" == *OK* || "$out" == *ok* ]] && ok "health: $out" || fail "health: $out"

echo "== 2. /v1/models"
out=$(req GET /v1/models); echo "$out" | py 'import sys,json;d=json.load(sys.stdin);print("  models:",", ".join(m["id"] for m in d["data"]));assert d["data"]' && ok "model list" || fail "models: $out"

echo "== 3. chat completion (non-streaming) model=$MODEL"
body=$(MODEL=$MODEL MAXT=$MAXT py 'import json,os;print(json.dumps({"model":os.environ["MODEL"],"max_tokens":int(os.environ["MAXT"]),"messages":[{"role":"user","content":"Answer with just the word: pong"}]}))')
out=$(req POST /v1/chat/completions "$body")
echo "$out" | py 'import sys,json;d=json.load(sys.stdin);m=d["choices"][0]["message"];u=d["usage"];print("  answer:",repr(m.get("content"))[:120]);print("  usage:",u);t=d.get("timings",{});print("  timings: prompt %.1f t/s | gen %.1f t/s"%(t.get("prompt_per_second",0),t.get("predicted_per_second",0)));assert (m.get("content") or "").strip()' && ok "chat" || fail "chat: ${out:0:300}"

echo "== 4. chat streaming"
body=$(MODEL=$MODEL MAXT=$MAXT py 'import json,os;print(json.dumps({"model":os.environ["MODEL"],"stream":True,"max_tokens":int(os.environ["MAXT"]),"messages":[{"role":"user","content":"Count from 1 to 5."}]}))')
out=$(req POST /v1/chat/completions "$body")
n=$(echo "$out" | grep -c '^data: {'); if [[ $n -gt 3 && "$out" == *"data: [DONE]"* ]]; then ok "streaming: $n chunks + [DONE]"; else fail "streaming: n=$n ${out:0:200}"; fi

echo "== 5. tool calling"
body=$(MODEL=$MODEL MAXT=$MAXT py 'import json,os;print(json.dumps({"model":os.environ["MODEL"],"max_tokens":int(os.environ["MAXT"])*2,"tool_choice":"auto","messages":[{"role":"user","content":"What is the weather in Sao Paulo right now? Use the tool."}],"tools":[{"type":"function","function":{"name":"get_weather","description":"Gets the current weather for a city","parameters":{"type":"object","properties":{"city":{"type":"string"}},"required":["city"]}}}]}))')
out=$(req POST /v1/chat/completions "$body")
echo "$out" | py 'import sys,json;d=json.load(sys.stdin);c=d["choices"][0];tc=c["message"]["tool_calls"][0]["function"];a=json.loads(tc["arguments"]);print("  tool_call:",tc["name"],a);assert tc["name"]=="get_weather" and "city" in a' && ok "valid tool call" || fail "tool call: ${out:0:300}"

echo "== 6. code generation"
body=$(MODEL=$MODEL py 'import json,os;print(json.dumps({"model":os.environ["MODEL"],"max_tokens":16000,"messages":[{"role":"user","content":"Write an efficient Python function is_prime(n). Reply with a single python code block only."}]}))')
out=$(req POST /v1/chat/completions "$body")
echo "$out" | py '
import sys,json,re
d=json.load(sys.stdin);m=d["choices"][0]["message"]["content"] or ""
code=re.search(r"```(?:python)?\n(.*?)```",m,re.S);assert code,"no code block: "+m[:200]
ns={};exec(code.group(1),ns);f=ns["is_prime"]
assert [n for n in range(30) if f(n)]==[2,3,5,7,11,13,17,19,23,29] and f(7919) and not f(7917)
t=d.get("timings",{});print("  code executed and correct; gen %.1f t/s, %d tokens"%(t.get("predicted_per_second",0),d["usage"]["completion_tokens"]))' && ok "generated code passed the test" || fail "codegen: ${out:0:300}"

echo; [[ $fails -eq 0 ]] && echo "ALL TESTS PASSED" || echo "$fails TEST(S) FAILED"
exit $((fails>0))
