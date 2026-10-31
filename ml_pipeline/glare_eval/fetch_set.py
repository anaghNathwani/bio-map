"""Downloads a small labelled bird-photo test set for glare experiments (evaluation only, nothing is committed).

For each species in SPECIES that the bundled classifier knows, pulls a few research-grade, openly licensed
(CC0 / CC-BY / CC-BY-SA) iNaturalist photos. The photos stay in --out (outside the repo) and are only used to
measure the classifier; they are never redistributed or used for training.

  python fetch_set.py --out /path/to/glare_set [--per-species 3]
"""
import argparse, json, pathlib, time, urllib.parse, urllib.request

LABELS = pathlib.Path(__file__).resolve().parents[2] / "ios/BioMap/BioMap/ML/Bundled/BundledBirdLabels.json"
SPECIES = """Northern Cardinal|Blue Jay|American Robin|House Finch|American Goldfinch|Black-capped Chickadee|Mourning Dove|
Northern Mockingbird|Red-winged Blackbird|Downy Woodpecker|Dark-eyed Junco|Song Sparrow|European Starling|Bald Eagle|
Red-tailed Hawk|Mallard|Canada Goose|Great Blue Heron|American Crow|Common Raven|Barn Swallow|Tree Swallow|Cedar Waxwing|
Eastern Bluebird|Western Bluebird|Anna's Hummingbird|Ruby-throated Hummingbird|Steller's Jay|Northern Flicker|Pileated Woodpecker|
White-breasted Nuthatch|Tufted Titmouse|Carolina Wren|House Wren|Brown Pelican|Great Egret|Snowy Egret|Belted Kingfisher|Osprey|
Turkey Vulture|American Kestrel|Peregrine Falcon|Sandhill Crane|Wild Turkey|Ring-billed Gull|Herring Gull|Killdeer|Black Phoebe|
Western Meadowlark|Baltimore Oriole|Scarlet Tanager|Indigo Bunting|Yellow Warbler|American Avocet|Vermilion Flycatcher|
Double-crested Cormorant|Common Loon|Mute Swan|Wood Duck|Black-necked Stilt|Acorn Woodpecker|California Scrub-Jay""".replace("\n", "").split("|")
API = "https://api.inaturalist.org/v1"


def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": "BioMap-glare-eval/1.0 (research; local use)"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.read()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--per-species", type=int, default=3)
    a = ap.parse_args()
    out = pathlib.Path(a.out); out.mkdir(parents=True, exist_ok=True)
    known = set(json.loads(LABELS.read_text()))
    manifest = []
    for name in [s.strip() for s in SPECIES]:
        if name not in known:
            print("skip (not a model label):", name); continue
        try:
            taxa = json.loads(get(f"{API}/taxa?q={urllib.parse.quote(name)}&rank=species&per_page=1"))["results"]
            if not taxa: print("no taxon:", name); continue
            q = (f"{API}/observations?taxon_id={taxa[0]['id']}&quality_grade=research&photos=true"
                 f"&photo_license=cc0,cc-by,cc-by-sa&order_by=votes&per_page={a.per_species * 2}")
            obs = json.loads(get(q))["results"]
            n = 0
            for o in obs:
                if n >= a.per_species: break
                ph = (o.get("photos") or [None])[0]
                if not ph: continue
                url = ph["url"].replace("square", "medium")
                fn = out / f"{name.replace(' ', '_').replace('/', '-')}_{n}.jpg"
                fn.write_bytes(get(url))
                manifest.append({"file": fn.name, "label": name, "source": f"https://www.inaturalist.org/observations/{o['id']}", "license": ph.get("license_code")})
                n += 1
            print(f"{name}: {n}")
            time.sleep(1.1)   # stay well under iNaturalist's rate limit
        except Exception as e:
            print("error", name, e)
    (out / "manifest.json").write_text(json.dumps(manifest, indent=1))
    print("total images:", len(manifest))


if __name__ == "__main__":
    main()
