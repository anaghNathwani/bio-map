"""Builds a REAL low-sun test set: labelled bird photos actually taken near sunrise / sunset, plus same-species daylight photos.

iNaturalist observations carry a capture time and a location. From those we compute the sun's elevation at the moment of the
shot and keep research-grade, openly licensed (CC0 / CC-BY / CC-BY-SA) photos of the species the bundled classifier knows:

  LOW   sun elevation between -3 and +10 degrees (sunrise/sunset and golden hour)
  DAY   sun elevation above 35 degrees (a daylight control, to measure how big the real gap is)

Photos stay in --out (outside the repo) and are used only to evaluate the model, never to train it.

  python fetch_lowsun.py --out /path/to/real_lowsun [--per-bucket 6] [--pages 3]
"""
import argparse, json, pathlib, time, urllib.parse, urllib.request
from datetime import datetime

from solar import solar_elevation
from fetch_set import SPECIES, LABELS, API, get

LOW = (-3.0, 10.0)
DAY_MIN = 35.0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--per-bucket", type=int, default=6)
    ap.add_argument("--pages", type=int, default=3)
    ap.add_argument("--low-min", type=float, default=LOW[0], help="lowest sun elevation to keep as 'low'")
    ap.add_argument("--low-max", type=float, default=LOW[1], help="highest sun elevation to keep as 'low'")
    ap.add_argument("--no-day", action="store_true", help="skip the daylight control bucket")
    ap.add_argument("--exclude", help="a manifest.json whose observations should be skipped (to add NEW photos only)")
    a = ap.parse_args()
    out = pathlib.Path(a.out); out.mkdir(parents=True, exist_ok=True)
    known = set(json.loads(LABELS.read_text()))
    manifest, stats = [], {}
    seen = set()
    if a.exclude:
        seen = {m["source"] for m in json.loads(pathlib.Path(a.exclude).read_text())}
    for name in [s.strip() for s in SPECIES]:
        if name not in known:
            continue
        try:
            taxa = json.loads(get(f"{API}/taxa?q={urllib.parse.quote(name)}&rank=species&per_page=1"))["results"]
            if not taxa:
                continue
            tid = taxa[0]["id"]
            buckets = {"low": [], "day": []}
            for page in range(1, a.pages + 1):
                if len(buckets["low"]) >= a.per_bucket and (a.no_day or len(buckets["day"]) >= a.per_bucket):
                    break
                q = (f"{API}/observations?taxon_id={tid}&quality_grade=research&photos=true&geo=true"
                     f"&photo_license=cc0,cc-by,cc-by-sa&order_by=votes&per_page=200&page={page}")
                for o in json.loads(get(q))["results"]:
                    t, loc = o.get("time_observed_at"), o.get("location")
                    ph = (o.get("photos") or [None])[0]
                    if not (t and loc and ph):
                        continue
                    try:
                        dt = datetime.fromisoformat(t)
                        lat, lon = (float(v) for v in loc.split(","))
                    except ValueError:
                        continue
                    if dt.tzinfo is None:
                        continue
                    if f"https://www.inaturalist.org/observations/{o['id']}" in seen:
                        continue
                    el = solar_elevation(dt, lat, lon)
                    kind = "low" if a.low_min <= el <= a.low_max else (None if a.no_day else ("day" if el >= DAY_MIN else None))
                    if kind and len(buckets[kind]) < a.per_bucket:
                        buckets[kind].append((o, ph, el))
                time.sleep(1.1)
            n = {"low": 0, "day": 0}
            for kind, rows in buckets.items():
                for i, (o, ph, el) in enumerate(rows):
                    fn = out / f"{name.replace(' ', '_')}_{kind}_{i}.jpg"
                    fn.write_bytes(get(ph["url"].replace("square", "medium")))
                    manifest.append({"file": fn.name, "label": name, "kind": kind, "sun_elevation": round(el, 1),
                                     "time": o["time_observed_at"], "source": f"https://www.inaturalist.org/observations/{o['id']}",
                                     "license": ph.get("license_code")})
                    n[kind] += 1
            stats[name] = n
            print(f"{name}: low={n['low']} day={n['day']}", flush=True)
        except Exception as e:
            print("error", name, e, flush=True)
    (out / "manifest.json").write_text(json.dumps(manifest, indent=1))
    low = sum(1 for m in manifest if m["kind"] == "low"); day = len(manifest) - low
    print(f"total: {len(manifest)} photos ({low} low-sun, {day} daylight)")


if __name__ == "__main__":
    main()
