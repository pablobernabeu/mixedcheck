"""Is an unsalted SHA-256 of a person-level column safe to publish in a 'shareable' report or log?
(1) all-but-one attack: intruder knows every value except one child's; (2) full brute force of a
binary outcome column for a small class (n = 20). Serialisation assumed known (it is specified
in the public schema)."""
import hashlib, itertools, json, random, time
random.seed(7)
def col_hash(vals):  # canonical JSON array of 0/1, as a schema would fix it
    return hashlib.sha256(json.dumps(vals, separators=(",", ":")).encode()).hexdigest()
n = 20
y = [random.randint(0, 1) for _ in range(n)]
published = col_hash(y)
# (1) all-but-one
known = y.copy(); target = 13
t0 = time.time()
cands = [v for v in (0, 1) if col_hash(known[:target] + [v] + known[target + 1:]) == published]
print(f"all-but-one: recovered y[{target}]={cands} (true {y[target]}) in {time.time()-t0:.4f}s")
# (2) full brute force over 2^20 vectors
t0 = time.time(); hit = None
for bits in itertools.product((0, 1), repeat=n):
    if col_hash(list(bits)) == published:
        hit = list(bits); break
print(f"full brute force n={n}: recovered={hit == y} in {time.time()-t0:.1f}s")
# (3) keyed commitment (HMAC with a secret kept in the internal sidecar) defeats both
import hmac, secrets
key = secrets.token_bytes(32)
tag = hmac.new(key, json.dumps(y, separators=(",", ":")).encode(), hashlib.sha256).hexdigest()
ok = any(hmac.new(b"guess", json.dumps(known[:target] + [v] + known[target + 1:], separators=(",", ":")).encode(), hashlib.sha256).hexdigest() == tag for v in (0, 1))
print("all-but-one against HMAC without the key succeeds:", ok)
