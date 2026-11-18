"""Builds a test set of multi-bird frames from single-species bird photos (real photos, composed side by side), to measure whether the
app finds every bird in a frame.

Only photos the species model already identifies on their own (correct, confidence >= 0.6) are used, so a miss means the
multi-bird step failed, not the classifier. Layouts:
  pair     two different species, equal size, side by side (landscape 8:5)
  triple   three different species across
  unequal  a large bird and a smaller one (about half size, vertically centred), different species
  same     two photos of the SAME species (control: nothing extra should be reported)
  single   one photo (control: nothing extra should be reported)

  python make_set.py --rows horizon_analysis.json --photos DIR --out OUT [--seed 0]
"""
import argparse, json, pathlib, random
from PIL import Image, ImageFilter

H = 500


def prep(path, w=400, h=H):
    im = Image.open(path).convert("RGB")
    iw, ih = im.size
    # centre-crop to w:h then resize
    target = w / h
    if iw / ih > target:
        nw = int(ih * target); im = im.crop(((iw - nw) // 2, 0, (iw - nw) // 2 + nw, ih))
    else:
        nh = int(iw / target); im = im.crop((0, (ih - nh) // 2, iw, (ih - nh) // 2 + nh))
    return im.resize((w, h), Image.LANCZOS)


def row(images):
    out = Image.new("RGB", (sum(i.width for i in images), H), (128, 128, 128))
    x = 0
    for i in images:
        out.paste(i, (x, 0)); x += i.width
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--rows", required=True)
    ap.add_argument("--photos", nargs="+", required=True, help="directories holding the photos named in --rows")
    ap.add_argument("--out", required=True)
    ap.add_argument("--seed", type=int, default=0)
    a = ap.parse_args()
    rng = random.Random(a.seed)
    out = pathlib.Path(a.out); out.mkdir(parents=True, exist_ok=True)
    rows = json.loads(pathlib.Path(a.rows).read_text())["rows"]
    elig = [r for r in rows if r["bucket"] == "day" and r["raw_top1"] and r["raw_conf"] >= 0.6]
    where = {}
    for d in a.photos:
        for f in pathlib.Path(d).glob("*.jpg"):
            where[f.name] = f
    elig = [r for r in elig if r["file"] in where]
    by_species = {}
    for r in elig:
        by_species.setdefault(r["label"], []).append(r)
    species = sorted(by_species)
    print("eligible photos:", len(elig), "species:", len(species))

    def pick(n, exclude=()):
        chosen = rng.sample([s for s in species if s not in exclude], n)
        return [rng.choice(by_species[s]) for s in chosen]

    manifest = []

    def add(name, img, truth, layout):
        img.save(out / name, quality=92)
        manifest.append({"file": name, "truth": sorted(set(truth)), "n_birds": len(truth), "layout": layout})

    for i in range(80):
        p = pick(2); add(f"pair_{i}.jpg", row([prep(where[x["file"]]) for x in p]), [x["label"] for x in p], "pair")
    for i in range(40):
        p = pick(3); add(f"triple_{i}.jpg", row([prep(where[x["file"]]) for x in p]), [x["label"] for x in p], "triple")
    for i in range(40):
        big, small = pick(2)
        small_im = prep(where[small["file"]], 220, 275)
        pad = Image.new("RGB", (220, H), tuple(int(v) for v in small_im.resize((1, 1)).getpixel((0, 0))))
        pad.paste(small_im, (0, (H - 275) // 2))
        add(f"unequal_{i}.jpg", row([prep(where[big["file"]]), pad]), [big["label"], small["label"]], "unequal")
    pool = [s for s in species if len(by_species[s]) >= 2]
    for i in range(60):
        s = rng.choice(pool); x, y = rng.sample(by_species[s], 2)
        add(f"same_{i}.jpg", row([prep(where[x["file"]]), prep(where[y["file"]])]), [s, s], "same")
    for i, r in enumerate(rng.sample(elig, min(100, len(elig)))):
        add(f"single_{i}.jpg", prep(where[r["file"]], 800, 500) if False else prep(where[r["file"]], 400, H), [r["label"]], "single")
    (out / "manifest.json").write_text(json.dumps(manifest, indent=1))
    print("wrote", len(manifest), "images to", out)


if __name__ == "__main__":
    main()
