#!/usr/bin/env python3
"""Fetch TestFlight screenshot feedback from App Store Connect, oldest first, one JSON object per line.

Usage: fetch_feedback.py [--download DIR] [--all]
  default  only reports not marked resolved in Xcode's local cache
  --all    include locally resolved ones too
  --download DIR  save each screenshot as DIR/b<build>-<id8>[-N].jpg (URLs expire)
Fields: id, date, build, comment, device, os, locale, screenshots (urls), resolved_local, tracked (GitHub issues citing the id).
Needs ASC_KEY_ID / ASC_ISSUER_ID in .env (same as scripts/xcb) and an authenticated `gh`.
"""
import argparse, json, os, subprocess, sys, urllib.request

ROOT = subprocess.check_output(["git", "rev-parse", "--show-toplevel"], text=True).strip()
sys.path.insert(0, f"{ROOT}/scripts")
import asc_api  # noqa: E402

BUNDLE = "rizzoG99.PersonalFinanceTraker"
USERDATA = os.path.expanduser(f"~/Library/Developer/Xcode/Products/{BUNDLE}/Feedback/UserData/UserData_a.json")

ap = argparse.ArgumentParser()
ap.add_argument("--download")
ap.add_argument("--all", action="store_true")
args = ap.parse_args()

# .env is gitignored, so a worktree has none: fall back to the main checkout's.
main = os.path.dirname(os.path.realpath(subprocess.check_output(
    ["git", "rev-parse", "--git-common-dir"], cwd=ROOT, text=True).strip()))
env = next((p for p in (f"{ROOT}/.env", f"{main}/.env") if os.path.exists(p)), None)
if env is None:
    sys.exit("No .env with ASC_KEY_ID / ASC_ISSUER_ID found (see .env.example)")
for line in open(env):
    k, _, v = line.strip().partition("=")
    if k in ("ASC_KEY_ID", "ASC_ISSUER_ID"):
        os.environ.setdefault(k, v.strip("\"'"))
token = asc_api.make_jwt(os.environ["ASC_KEY_ID"], os.environ["ASC_ISSUER_ID"])
app = asc_api.find_app_id(BUNDLE, token)

# Xcode keeps "resolved" locally only (the API has no such field): pairs of {feedbackIdentifier} / {isResolved}.
resolved = set()
if os.path.exists(USERDATA):
    flat = json.load(open(USERDATA))["identifierToUserData"]
    resolved = {a["feedbackIdentifier"] for a, b in zip(flat[::2], flat[1::2]) if b.get("isResolved")}

issues = json.loads(subprocess.check_output(
    ["gh", "issue", "list", "--state", "all", "--limit", "1000", "--json", "number,state,body"], cwd=ROOT))

rows, cursor = [], ""
while True:
    r = asc_api.call(f"/apps/{app}/betaFeedbackScreenshotSubmissions?limit=200&include=build{cursor}", token)
    builds = {i["id"]: i["attributes"]["version"] for i in r.get("included", []) if i["type"] == "builds"}
    for d in r["data"]:
        a, fid = d["attributes"], d["id"]
        build = builds.get((d["relationships"]["build"].get("data") or {}).get("id"), "?")
        rows.append({
            "id": fid, "date": a["createdDate"][:10], "build": build, "comment": a["comment"],
            "device": a["deviceModel"], "os": a["osVersion"], "locale": a["locale"],
            "screenshots": [s["url"] for s in a.get("screenshots", [])],
            "resolved_local": fid in resolved,
            "tracked": [f'#{i["number"]} {i["state"]}' for i in issues if fid in (i["body"] or "") or fid[:8] in (i["body"] or "")],
        })
    nxt = r.get("meta", {}).get("paging", {}).get("nextCursor")
    if not nxt:
        break
    cursor = f"&cursor={nxt}"

for row in sorted(rows, key=lambda x: x["date"]):
    if row["resolved_local"] and not args.all:
        continue
    if args.download:
        os.makedirs(args.download, exist_ok=True)
        for n, url in enumerate(row["screenshots"]):
            name = f'b{row["build"]}-{row["id"][:8]}' + (f"-{n}" if n else "") + ".jpg"
            urllib.request.urlretrieve(url, os.path.join(args.download, name))
    print(json.dumps(row, ensure_ascii=False))
