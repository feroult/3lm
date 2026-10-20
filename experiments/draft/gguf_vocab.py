# Reads only the header of a GGUF (local file or HTTP URL with Range) and prints the architecture + a vocabulary fingerprint.
import sys, struct, hashlib, io, json, urllib.request
src = sys.argv[1]
LIM = 40 * 1024 * 1024
if src.startswith("http"):
    req = urllib.request.Request(src, headers={"Range": "bytes=0-%d" % (LIM - 1)})
    data = urllib.request.urlopen(req, timeout=120).read()
else:
    with open(src, "rb") as fh: data = fh.read(LIM)
f = io.BytesIO(data)
assert f.read(4) == b"GGUF", "not a GGUF file"
ver, = struct.unpack("<I", f.read(4)); nt, = struct.unpack("<Q", f.read(8)); nkv, = struct.unpack("<Q", f.read(8))
def rs():
    n, = struct.unpack("<Q", f.read(8)); return f.read(n).decode("utf8", "replace")
fm = {0:"<B",1:"<b",2:"<H",3:"<h",4:"<I",5:"<i",6:"<f",7:"<?",10:"<Q",11:"<q",12:"<d"}
sz = {0:1,1:1,2:2,3:2,4:4,5:4,6:4,7:1,10:8,11:8,12:8}
def rv(t):
    if t in fm: return struct.unpack(fm[t], f.read(sz[t]))[0]
    if t == 8: return rs()
    if t == 9:
        et, = struct.unpack("<I", f.read(4)); n, = struct.unpack("<Q", f.read(8))
        return [rv(et) for _ in range(n)]
out = {}
try:
    for _ in range(nkv):
        k = rs(); t, = struct.unpack("<I", f.read(4)); v = rv(t)
        if k == "tokenizer.ggml.tokens":
            out["n_tokens"] = len(v); out["tokens_sha"] = hashlib.sha256("\x00".join(v).encode()).hexdigest()[:16]
        elif k == "tokenizer.ggml.merges":
            out["n_merges"] = len(v); out["merges_sha"] = hashlib.sha256("\x00".join(v).encode()).hexdigest()[:16]
        elif k == "tokenizer.ggml.token_type":
            out["token_type_sha"] = hashlib.sha256(bytes(v)).hexdigest()[:16]
        elif isinstance(v, list): pass
        elif k.startswith("tokenizer.") or k in ("general.architecture","general.name") or k.endswith(".block_count") or k.endswith(".embedding_length") or k.endswith(".vocab_size") or k.endswith("full_attention_interval"):
            out[k] = v if not isinstance(v, str) or len(v) < 80 else v[:80]
except Exception as e:
    out["_read_error"] = repr(e) + " (header larger than %dMB?)" % (LIM // 2**20)
print(json.dumps(out, ensure_ascii=False, sort_keys=True))
