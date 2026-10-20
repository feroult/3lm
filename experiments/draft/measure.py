import json, sys, time, urllib.request
BASE = sys.argv[1]; MODEL = sys.argv[2]
import os
CODE = """def is_valid_cpf(cpf):
    cpf = ''.join(c for c in cpf if c.isdigit())
    if len(cpf) != 11 or cpf == cpf[0] * 11:
        return False
    for i in (9, 10):
        total = sum(int(cpf[j]) * (i + 1 - j) for j in range(i))
        digit = (total * 10 % 11) % 10
        if digit != int(cpf[i]):
            return False
    return True


def is_valid_cnpj(cnpj):
    cnpj = ''.join(c for c in cnpj if c.isdigit())
    if len(cnpj) != 14 or cnpj == cnpj[0] * 14:
        return False
    weights = [6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2]
    for i in (12, 13):
        total = sum(int(cnpj[j]) * weights[j + 13 - i] for j in range(i))
        digit = 0 if total % 11 < 2 else 11 - total % 11
        if digit != int(cnpj[i]):
            return False
    return True
"""
EDIT = [("edit-typehints", 0.0, "Rewrite the whole code below, identical, only adding type hints and short docstrings. Reply with the code only.\n\n" + CODE),
        ("edit-rename", 0.0, "Rewrite the whole code below, renaming is_valid_cpf to check_cpf and is_valid_cnpj to check_cnpj, with no other change. Reply with the code only.\n\n" + CODE)]
PROMPTS = EDIT if os.environ.get("PROMPTSET") == "edit" else [
 ("cpf",   0.0, "Write a Python function that validates a Brazilian CPF, with tests."),
 ("sort",  0.0, "Write a Python function that sorts a list using quicksort, with tests."),
 ("btree", 0.0, "Explain in detail how a B-tree index works in databases, including insertion and node splitting."),
 ("cnpj-default-sampling", None, "Write a Python function that validates a Brazilian CNPJ, with tests."),
]
def req(prompt, temp, n, timeout=900):
    body = {"model": MODEL, "messages": [{"role": "user", "content": prompt}], "max_tokens": n}
    if temp is not None: body["temperature"] = temp
    r = urllib.request.Request(BASE + "/v1/chat/completions", json.dumps(body).encode(), {"Content-Type": "application/json"})
    return json.load(urllib.request.urlopen(r, timeout=timeout))
t0 = time.time(); req("hello", 0.0, 8); print(json.dumps({"load_plus_first_answer_s": round(time.time() - t0, 1)}))
req("Write a fibonacci function in Python.", 0.0, 64)  # warm-up
tot_n = tot_ms = dn = da = 0
for name, temp, p in PROMPTS:
    d = req(p, temp, 400 if os.environ.get("PROMPTSET") == "edit" else 256); t = d["timings"]
    n, ms = t["predicted_n"], t["predicted_ms"]; tot_n += n; tot_ms += ms
    x, y = t.get("draft_n", 0) or 0, t.get("draft_n_accepted", 0) or 0; dn += x; da += y
    print(json.dumps({"prompt": name, "gen_tps": round(t["predicted_per_second"], 1), "tokens": n, "draft_n": x, "draft_ok": y,
                      "acceptance": round(y / x, 3) if x else None, "prefill_tps": round(t["prompt_per_second"])}))
print(json.dumps({"SUMMARY_weighted_gen_tps": round(tot_n / (tot_ms / 1000), 1), "total_acceptance": round(da / dn, 3) if dn else None}))
