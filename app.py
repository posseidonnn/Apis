import os, glob, sqlite3, hmac
from flask import Flask, request, jsonify

app = Flask(__name__)

BASE = os.path.dirname(os.path.abspath(__file__))
KEYS = [k.strip() for k in os.environ.get("API_KEYS", "").split(",") if k.strip()]
LIMIT = 20
MIN_LEN = 3


def qi(name):
    return '"' + str(name).replace('"', '""') + '"'


def conn(path):
    c = sqlite3.connect(f"file:{path}?mode=ro&immutable=1", uri=True)
    c.row_factory = sqlite3.Row
    c.execute("PRAGMA query_only=ON")
    c.execute("PRAGMA mmap_size=1073741824")
    c.execute("PRAGMA cache_size=-65536")
    return c


def load_sources():
    sources = []
    for path in sorted(glob.glob(os.path.join(BASE, "*.db"))):
        try:
            with conn(path) as c:
                tables = [r[0] for r in c.execute(
                    "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'")]
                for t in tables:
                    cols = [r[1] for r in c.execute(f"PRAGMA table_info({qi(t)})")]
                    if cols:
                        sources.append((os.path.basename(path), path, t, cols))
        except sqlite3.Error as e:
            print(f"skip {path}: {e}")
    return sources


SOURCES = load_sources()


def authorized():
    given = request.headers.get("X-API-Key") or request.args.get("key", "")
    return any(hmac.compare_digest(given, k) for k in KEYS)


@app.route("/")
def home():
    return jsonify(status="ok",
                   sources=[{"db": s[0], "table": s[2], "columns": s[3]} for s in SOURCES])


@app.route("/reload")
def reload_sources():
    if not authorized():
        return jsonify(success=False, error="invalid or missing API key"), 401
    global SOURCES
    SOURCES = load_sources()
    return jsonify(success=True, dbs=len(SOURCES))


@app.route("/search")
def search():
    if not authorized():
        return jsonify(success=False, error="invalid or missing API key"), 401

    q = (request.args.get("q") or "").strip()
    if len(q) < MIN_LEN:
        return jsonify(credit="saikatFTW APi", success=True, found=False,
                       count=0, result=[], note=f"q minimum {MIN_LEN} akkhor")

    results = []
    for dbname, path, table, cols in SOURCES:
        if len(results) >= LIMIT:
            break
        remaining = LIMIT - len(results)
        where = " OR ".join(f"{qi(c)} LIKE ?" for c in cols)
        params = [f"%{q}%"] * len(cols)
        try:
            with conn(path) as c:
                for r in c.execute(
                    f"SELECT * FROM {qi(table)} WHERE {where} LIMIT {remaining}", params
                ):
                    row = dict(r)
                    row["_source"] = dbname
                    results.append(row)
        except sqlite3.Error as e:
            print(f"search error {path}: {e}")

    return jsonify(credit="saikatFTW APi", success=True,
                   found=bool(results), count=len(results), result=results)


if __name__ == "__main__":
    app.run(host="127.0.0.1", port=8000)
