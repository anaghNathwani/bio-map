"""Writes input photos (224x224 float32 RGB) and glare_lib.adaptive()'s expected output + flags, for the Swift parity check.

  python dump_parity_cases.py --set /path/to/glare_set --out /path/to/cases [--n 30]
"""
import argparse, json, pathlib, zlib
import numpy as np
import glare_lib as G


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--set", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--n", type=int, default=30)
    a = ap.parse_args()
    root, out = pathlib.Path(a.set), pathlib.Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    items = json.loads((root / "manifest.json").read_text())[:: max(1, 177 // a.n)][: a.n]
    meta, k = [], 0
    for it in items:
        x = G.load224(root / it["file"])
        for cond in G.CONDITIONS:
            y = G.simulate(x, cond, zlib.crc32(f"{it['file']}|{cond}".encode())).astype(np.float32)
            fixed, flags = G.adaptive(y, return_flags=True)
            y.tofile(out / f"{k}.in.f32")
            np.asarray(fixed, np.float32).tofile(out / f"{k}.out.f32")
            meta.append({"id": k, "cond": cond, "flags": sorted(flags)})
            k += 1
    (out / "cases.json").write_text(json.dumps(meta))
    print("cases:", k, "| corrected:", sum(1 for m in meta if m["flags"]))


if __name__ == "__main__":
    main()
