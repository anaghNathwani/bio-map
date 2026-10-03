"""
Builds ios/BioMap/BioMap/ML/Bundled/BundledBirdNETLabels.json from the label
file that ships with birdnetlib: one entry per BirdNET output class, in class
order, with a *blank* string for everything that isn't a bird.

BirdNET V2.4's 6,522 classes aren't all birds. Left in, they'd be reported as
"sightings" by the on-device identifier and counted as valid bird names by the
annotation moderator (a gray squirrel is not a bird). Excluded:
  - sound classes, which repeat the same text either side of the underscore
    ("Human vocal_Human vocal", "Dog_Dog", "Engine_Engine", "Noise_Noise"...);
  - frogs/toads, insects and mammals, identified by genus. The list was built by
    scanning the label file (83 classes) and cross-checking common names; note
    "Frogmouth", "Squirrel Cuckoo", "Bat Falcon" etc. are birds, which is why
    this goes by genus rather than by matching words in the common name.

Usage (in the ml_pipeline venv):
    python build_birdnet_labels.py
"""

import json
import os
from pathlib import Path

import birdnetlib

NON_BIRD_GENERA = {
    # frogs & toads
    "Acris", "Anaxyrus", "Dryophytes", "Eleutherodactylus", "Gastrophryne", "Hyliola",
    "Incilius", "Lithobates", "Pseudacris",
    # insects
    "Allonemobius", "Amblycorypha", "Apis", "Conocephalus", "Eunemobius", "Gryllus", "Miogryllus",
    "Neoconocephalus", "Neonemobius", "Oecanthus", "Orchelimum", "Orocharis", "Pterophylla", "Scudderia",
    # mammals
    "Alouatta", "Canis", "Odocoileus", "Sciurus", "Tamias", "Tamiasciurus",
}

OUTPUT = Path(__file__).parent.parent / "ios/BioMap/BioMap/ML/Bundled/BundledBirdNETLabels.json"


def main() -> None:
    labels_path = Path(os.path.dirname(birdnetlib.__file__)) / "models/analyzer/BirdNET_GLOBAL_6K_V2.4_Labels.txt"
    names, blanked = [], []
    for line in labels_path.read_text(encoding="utf-8").splitlines():
        scientific, _, common = line.strip().partition("_")
        is_species = " " in scientific and common and scientific.lower() != common.lower()
        if is_species and scientific.split(" ")[0] not in NON_BIRD_GENERA:
            names.append(common)
        else:
            names.append("")
            blanked.append(line.strip())
    OUTPUT.write_text(json.dumps(names, ensure_ascii=False))
    print(f"{len(names)} classes, {len(names) - len(blanked)} birds, {len(blanked)} blanked -> {OUTPUT}")


if __name__ == "__main__":
    main()
