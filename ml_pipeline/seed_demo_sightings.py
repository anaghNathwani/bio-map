"""
Seed clearly-labelled SAMPLE sightings around California so the live map isn't empty.

These are NOT real observations. Every document is marked so it can never be mistaken for real data:
  - isDemo: true
  - username "sample_birder_N", userId "demo-seed"
  - notes starting "Sample data"
  - doc IDs "demo-0001" ... so re-running is idempotent and removal is exact

Species are drawn from habitat pools that genuinely occur at each hotspot, filtered by season
(e.g. no Western Tanager in January, no Snow Goose in July). Dates follow the last ~12 months.
No photos/audio are attached and no annotations exist (annotationCount 0), so nothing implies
community verification.

  python seed_demo_sightings.py                 # dry run: prints the plan, writes nothing
  python seed_demo_sightings.py --commit        # write to Firestore
  python seed_demo_sightings.py --remove        # delete every isDemo document

Uses the same credentials as the rest of the pipeline (see firestore_client.py). If this machine's clock is
off, Google rejects the signed token; this script corrects for it using Google's own Date header.
"""

import argparse
import collections
import datetime as dt
import email.utils
import random
from zoneinfo import ZoneInfo

PT = ZoneInfo("America/Los_Angeles")

# Season codes -> months the species is normally present (CA lowlands unless noted).
SEASON = {
    None: set(range(1, 13)),
    "S": set(range(4, 10)),  # Apr-Sep breeding/summer
    "W": {10, 11, 12, 1, 2, 3, 4},  # winter visitors
    "M": {3, 4, 5, 8, 9, 10},  # migrants
    "H": set(range(6, 13)),  # Heermann's Gull: Jun-Dec
    "G": {7, 8, 9, 10, 11, 12, 1, 2, 3, 4},  # California Gull on the coast: Jul-Apr
    "C": {3, 4, 5, 6, 7, 8},  # Costa's Hummingbird
    "P": {6, 7, 8, 9},  # Wilson's Phalarope
}

# habitat -> [(species, weight, season code)]
POOLS = {
    "urban_coast": [
        ("Anna's Hummingbird", 8, None), ("House Finch", 9, None), ("Western Scrub-Jay", 6, None),
        ("American Crow", 6, None), ("Mourning Dove", 6, None), ("Black Phoebe", 5, None),
        ("California Towhee", 5, None), ("Lesser Goldfinch", 4, None), ("Bushtit", 4, None),
        ("Northern Mockingbird", 5, None), ("Dark-eyed Junco", 3, "W"), ("White-crowned Sparrow", 4, None),
        ("Golden-crowned Sparrow", 3, "W"), ("American Robin", 4, "W"), ("Northern Flicker", 3, None),
        ("Cooper's Hawk", 2, None), ("Red-shouldered Hawk", 2, None), ("Eurasian Collared-Dove", 4, None),
        ("European Starling", 4, None), ("House Sparrow", 4, None), ("Rock Pigeon", 3, None),
        ("Nuttall's Woodpecker", 2, None), ("Allen's Hummingbird", 3, "S"), ("Cedar Waxwing", 2, "W"),
    ],
    "urban_inland": [
        ("House Finch", 9, None), ("Western Scrub-Jay", 6, None), ("American Crow", 6, None),
        ("Mourning Dove", 6, None), ("Black Phoebe", 5, None), ("California Towhee", 5, None),
        ("Lesser Goldfinch", 4, None), ("Bushtit", 4, None), ("Northern Mockingbird", 5, None),
        ("Anna's Hummingbird", 6, None), ("Yellow-billed Magpie", 3, None), ("Northern Flicker", 3, None),
        ("American Robin", 4, "W"), ("White-crowned Sparrow", 4, "W"), ("Golden-crowned Sparrow", 3, "W"),
        ("Dark-eyed Junco", 3, "W"), ("Cooper's Hawk", 2, None), ("Red-tailed Hawk", 2, None),
        ("Red-shouldered Hawk", 2, None), ("Eurasian Collared-Dove", 4, None), ("European Starling", 4, None),
        ("House Sparrow", 4, None), ("Nuttall's Woodpecker", 2, None), ("Oak Titmouse", 2, None),
        ("Acorn Woodpecker", 2, None), ("Turkey Vulture", 2, None), ("Cedar Waxwing", 2, "W"),
    ],
    "coast": [
        ("Western Gull", 9, None), ("California Gull", 5, "G"), ("Heermann's Gull", 4, "H"),
        ("Brown Pelican", 6, None), ("Brandt's Cormorant", 5, None), ("Double-crested Cormorant", 4, None),
        ("Pelagic Cormorant", 3, None), ("Black Oystercatcher", 3, None), ("Black Turnstone", 3, "W"),
        ("Surfbird", 2, "W"), ("Whimbrel", 2, "M"), ("Willet", 4, None), ("Marbled Godwit", 3, "G"),
        ("Sanderling", 4, "G"), ("Western Grebe", 3, "W"), ("Surf Scoter", 3, "W"), ("Caspian Tern", 2, "S"),
        ("Osprey", 2, None), ("Snowy Egret", 2, None), ("Great Blue Heron", 3, None), ("Belted Kingfisher", 1, None),
        ("Peregrine Falcon", 1, None), ("Common Raven", 3, None), ("Song Sparrow", 2, None),
    ],
    "wetland": [
        ("Great Egret", 7, None), ("Snowy Egret", 6, None), ("Great Blue Heron", 6, None),
        ("Black-crowned Night-Heron", 3, None), ("American Avocet", 5, None), ("Black-necked Stilt", 5, "S"),
        ("Long-billed Curlew", 3, "G"), ("Marbled Godwit", 3, "G"), ("Willet", 4, None), ("Dunlin", 3, "W"),
        ("Western Sandpiper", 3, "M"), ("Least Sandpiper", 3, "W"), ("Killdeer", 5, None), ("Mallard", 6, None),
        ("Northern Pintail", 4, "W"), ("American Wigeon", 3, "W"), ("Northern Shoveler", 4, "W"),
        ("Ruddy Duck", 3, "W"), ("Bufflehead", 3, "W"), ("Green-winged Teal", 3, "W"), ("Pied-billed Grebe", 3, None),
        ("American Coot", 5, None), ("Belted Kingfisher", 2, None), ("Red-winged Blackbird", 6, None),
        ("Marsh Wren", 3, None), ("Song Sparrow", 4, None), ("Forster's Tern", 3, None), ("Ring-billed Gull", 3, "W"),
        ("Osprey", 2, None), ("Northern Harrier", 2, None),
    ],
    "oak": [
        ("Acorn Woodpecker", 6, None), ("Oak Titmouse", 6, None), ("Western Scrub-Jay", 7, None),
        ("California Towhee", 5, None), ("Wrentit", 4, None), ("California Thrasher", 3, None), ("Bushtit", 5, None),
        ("Spotted Towhee", 5, None), ("Bewick's Wren", 4, None), ("Hutton's Vireo", 2, None), ("Lark Sparrow", 3, "S"),
        ("Western Bluebird", 4, None), ("California Quail", 5, None), ("Nuttall's Woodpecker", 3, None),
        ("Red-tailed Hawk", 3, None), ("Turkey Vulture", 3, None), ("Black-headed Grosbeak", 3, "S"),
        ("Lazuli Bunting", 2, "S"), ("Anna's Hummingbird", 5, None), ("Northern Flicker", 2, None),
        ("Common Raven", 3, None), ("Ash-throated Flycatcher", 2, "S"), ("Yellow-rumped Warbler", 3, "W"),
        ("Great Horned Owl", 1, None),
    ],
    "redwood": [
        ("Steller's Jay", 7, None), ("Pacific Wren", 5, None), ("Varied Thrush", 3, "W"), ("Brown Creeper", 3, None),
        ("Chestnut-backed Chickadee", 6, None), ("Hermit Thrush", 3, "W"), ("Pacific-slope Flycatcher", 3, "S"),
        ("Red-breasted Sapsucker", 2, None), ("Hutton's Vireo", 2, None), ("Wilson's Warbler", 3, "S"),
        ("Golden-crowned Kinglet", 3, None), ("Dark-eyed Junco", 4, None), ("Anna's Hummingbird", 3, None),
        ("Common Raven", 3, None), ("Swainson's Thrush", 3, "S"), ("Band-tailed Pigeon", 2, None),
        ("Townsend's Warbler", 2, "W"), ("American Robin", 2, None), ("Hairy Woodpecker", 2, None),
    ],
    "montane": [
        ("Steller's Jay", 7, None), ("Clark's Nutcracker", 4, None), ("Mountain Chickadee", 7, None),
        ("White-headed Woodpecker", 2, None), ("Red-breasted Nuthatch", 4, None), ("White-breasted Nuthatch", 3, None),
        ("Pygmy Nuthatch", 3, None), ("Dark-eyed Junco", 6, None), ("Western Tanager", 4, "S"),
        ("Cassin's Finch", 3, "S"), ("Pine Siskin", 3, None), ("Hairy Woodpecker", 2, None), ("Northern Flicker", 3, None),
        ("Common Raven", 4, None), ("Mountain Bluebird", 2, "S"), ("Townsend's Solitaire", 2, None),
        ("Golden-crowned Kinglet", 2, None), ("Yellow-rumped Warbler", 4, "S"), ("Hermit Thrush", 2, "S"),
        ("Mountain Quail", 1, "S"), ("Brown Creeper", 2, None), ("Western Wood-Pewee", 2, "S"),
        ("Green-tailed Towhee", 2, "S"), ("American Dipper", 2, None), ("Belted Kingfisher", 1, None),
        ("Turkey Vulture", 2, "S"), ("Red-tailed Hawk", 2, None),
    ],
    "gbasin": [
        ("California Gull", 5, "S"), ("Wilson's Phalarope", 3, "P"), ("Eared Grebe", 3, "M"), ("American Avocet", 3, "S"),
        ("Sage Thrasher", 3, "S"), ("Brewer's Sparrow", 3, "S"), ("Sage Sparrow", 2, None), ("Black-billed Magpie", 3, None),
        ("Common Raven", 5, None), ("Say's Phoebe", 3, "S"), ("Loggerhead Shrike", 2, None), ("Mountain Bluebird", 2, None),
        ("Horned Lark", 3, None), ("Western Meadowlark", 4, None), ("Red-winged Blackbird", 3, "S"),
        ("Yellow-headed Blackbird", 2, "S"), ("Killdeer", 3, None), ("Mallard", 2, None), ("Northern Harrier", 2, None),
        ("Red-tailed Hawk", 3, None), ("Swainson's Hawk", 2, "S"), ("Rock Wren", 3, None), ("Black-throated Sparrow", 2, "S"),
        ("House Finch", 3, None), ("Mourning Dove", 3, "S"), ("Turkey Vulture", 2, "S"), ("Green-tailed Towhee", 1, "S"),
    ],
    "desert": [
        ("Gambel's Quail", 6, None), ("Greater Roadrunner", 3, None), ("Verdin", 5, None), ("Cactus Wren", 5, None),
        ("Black-throated Sparrow", 4, None), ("Phainopepla", 3, None), ("Costa's Hummingbird", 3, "C"),
        ("Ladder-backed Woodpecker", 3, None), ("Black-tailed Gnatcatcher", 3, None), ("Rock Wren", 3, None),
        ("Common Raven", 5, None), ("Loggerhead Shrike", 2, None), ("Say's Phoebe", 3, None), ("Turkey Vulture", 3, None),
        ("Red-tailed Hawk", 3, None), ("Le Conte's Thrasher", 2, None), ("Northern Mockingbird", 4, None),
        ("House Finch", 5, None), ("Mourning Dove", 4, None), ("White-winged Dove", 2, "S"), ("Lesser Goldfinch", 2, None),
        ("Ash-throated Flycatcher", 2, "S"), ("Scott's Oriole", 2, "S"), ("Western Kingbird", 2, "S"),
        ("Lesser Nighthawk", 1, "S"), ("Cooper's Hawk", 1, None),
    ],
    "desert_wetland": [
        ("Great Egret", 5, None), ("Snowy Egret", 4, None), ("Great Blue Heron", 4, None), ("Black-necked Stilt", 5, None),
        ("American Avocet", 5, None), ("Killdeer", 4, None), ("Yellow-headed Blackbird", 3, None), ("Burrowing Owl", 3, None),
        ("Gambel's Quail", 2, None), ("Verdin", 2, None), ("Gull-billed Tern", 2, "S"), ("Black Skimmer", 2, "S"),
        ("American White Pelican", 4, "W"), ("Brown Pelican", 3, None), ("Eared Grebe", 4, "W"), ("White-faced Ibis", 3, "M"),
        ("Cattle Egret", 3, None), ("Great-tailed Grackle", 5, None), ("Red-winged Blackbird", 4, None),
        ("Ruddy Duck", 3, "W"), ("Northern Shoveler", 3, "W"), ("American Coot", 3, None), ("Common Raven", 2, None),
        ("Western Sandpiper", 2, "W"), ("Long-billed Curlew", 2, "W"),
    ],
    "cvalley": [
        ("Sandhill Crane", 3, "W"), ("Snow Goose", 5, "W"), ("Ross's Goose", 3, "W"), ("Greater White-fronted Goose", 4, "W"),
        ("Tundra Swan", 3, "W"), ("Northern Harrier", 3, None), ("White-tailed Kite", 3, None), ("Red-tailed Hawk", 5, None),
        ("Swainson's Hawk", 3, "S"), ("American Kestrel", 4, None), ("Western Meadowlark", 6, None),
        ("Yellow-billed Magpie", 4, None), ("Tricolored Blackbird", 3, "S"), ("Loggerhead Shrike", 2, None),
        ("White-faced Ibis", 2, "S"), ("Cattle Egret", 2, None), ("Black-necked Stilt", 3, "S"),
        ("American White Pelican", 3, "W"), ("Northern Pintail", 4, "W"), ("Mallard", 5, None), ("Killdeer", 4, None),
        ("Horned Lark", 3, None), ("Savannah Sparrow", 3, "W"), ("Great Egret", 4, None), ("Great Blue Heron", 3, None),
        ("Turkey Vulture", 3, None), ("Red-winged Blackbird", 6, None), ("Ring-necked Pheasant", 2, None),
        ("California Quail", 2, None), ("Mourning Dove", 3, None), ("American Crow", 3, None), ("Bald Eagle", 1, "W"),
    ],
}

# Species that plausibly get recorded by sound (audio sightings are only drawn from these).
VOCAL = {
    "House Finch", "Western Scrub-Jay", "California Towhee", "Oak Titmouse", "Bewick's Wren", "Wrentit",
    "California Thrasher", "Northern Mockingbird", "Song Sparrow", "Marsh Wren", "Red-winged Blackbird",
    "Western Meadowlark", "Steller's Jay", "Mountain Chickadee", "Chestnut-backed Chickadee", "Pacific Wren",
    "Cactus Wren", "Gambel's Quail", "California Quail", "Great Horned Owl", "Spotted Towhee", "Black Phoebe",
    "Killdeer", "American Crow", "Common Raven", "Acorn Woodpecker", "Northern Flicker", "Verdin",
    "Black-headed Grosbeak", "Western Tanager", "Lazuli Bunting", "Wilson's Warbler", "Hermit Thrush",
    "Varied Thrush", "Swainson's Thrush", "Anna's Hummingbird", "Mourning Dove", "Lesser Goldfinch", "Bushtit",
    "Sage Thrasher", "Brewer's Sparrow", "Yellow-headed Blackbird", "Great-tailed Grackle", "Hutton's Vireo",
    "Pacific-slope Flycatcher", "Ash-throated Flycatcher", "Western Wood-Pewee", "Green-tailed Towhee",
    "Clark's Nutcracker", "White-breasted Nuthatch", "Pygmy Nuthatch", "Red-breasted Nuthatch", "Le Conte's Thrasher",
    "Greater Roadrunner", "Sandhill Crane", "Burrowing Owl", "Hairy Woodpecker", "Cassin's Finch", "Pine Siskin",
}

# (name, lat, lon, {habitat: weight}, site weight, jitter sigma in degrees)
SITES = [
    ("Golden Gate Park, San Francisco", 37.7694, -122.4862, {"urban_coast": 1}, 14, 0.008),
    ("Crissy Field, San Francisco", 37.8060, -122.4650, {"coast": .6, "urban_coast": .4}, 6, 0.004),
    ("Point Reyes: Limantour", 38.0350, -122.8990, {"coast": .5, "wetland": .5}, 5, 0.01),
    ("Point Reyes Lighthouse", 38.0000, -123.0220, {"coast": 1}, 3, 0.006),
    ("Muir Woods", 37.8912, -122.5714, {"redwood": 1}, 4, 0.006),
    ("Palo Alto Baylands", 37.4590, -122.1020, {"wetland": 1}, 8, 0.008),
    ("Don Edwards NWR, Alviso", 37.4560, -121.9800, {"wetland": 1}, 6, 0.012),
    ("Lake Merritt, Oakland", 37.8080, -122.2590, {"urban_coast": .7, "wetland": .3}, 7, 0.006),
    ("Mount Diablo", 37.8816, -121.9142, {"oak": 1}, 6, 0.02),
    ("Elkhorn Slough", 36.8170, -121.7440, {"wetland": 1}, 9, 0.01),
    ("Point Lobos", 36.5160, -121.9390, {"coast": .6, "oak": .4}, 6, 0.004),
    ("Big Sur: Andrew Molera", 36.2830, -121.8420, {"oak": .5, "redwood": .3, "coast": .2}, 4, 0.02),
    ("Morro Bay", 35.3600, -120.8560, {"wetland": .6, "coast": .4}, 7, 0.008),
    ("Goleta Slough, Santa Barbara", 34.4130, -119.8470, {"wetland": .7, "urban_coast": .3}, 6, 0.008),
    ("Santa Barbara foothills", 34.4700, -119.7100, {"oak": 1}, 4, 0.02),
    ("Ballona Wetlands, Los Angeles", 33.9770, -118.4390, {"wetland": .7, "urban_coast": .3}, 8, 0.006),
    ("Griffith Park, Los Angeles", 34.1180, -118.3000, {"oak": .6, "urban_coast": .4}, 8, 0.01),
    ("Los Angeles (urban)", 34.0522, -118.2437, {"urban_coast": 1}, 12, 0.05),
    ("Bolsa Chica", 33.6930, -118.0480, {"wetland": .8, "coast": .2}, 7, 0.006),
    ("Upper Newport Bay", 33.6300, -117.8900, {"wetland": 1}, 6, 0.008),
    ("Laguna coast", 33.5400, -117.7900, {"coast": 1}, 3, 0.006),
    ("Torrey Pines, San Diego", 32.9210, -117.2570, {"oak": .5, "coast": .5}, 6, 0.006),
    ("La Jolla Cove", 32.8510, -117.2720, {"coast": 1}, 5, 0.003),
    ("Mission Bay, San Diego", 32.7800, -117.2300, {"wetland": .5, "coast": .3, "urban_coast": .2}, 5, 0.008),
    ("San Diego (urban)", 32.7157, -117.1611, {"urban_coast": 1}, 9, 0.04),
    ("Cuyamaca Rancho", 32.9900, -116.5900, {"oak": 1}, 3, 0.02),
    ("Anza-Borrego", 33.2560, -116.3750, {"desert": 1}, 4, 0.05),
    ("Salton Sea NWR", 33.1740, -115.6200, {"desert_wetland": 1}, 6, 0.03),
    ("Joshua Tree NP", 33.7420, -115.8210, {"desert": 1}, 6, 0.05),
    ("Palm Springs", 33.8300, -116.5400, {"desert": .7, "urban_inland": .3}, 4, 0.03),
    ("Death Valley: Furnace Creek", 36.4570, -116.8650, {"desert": 1}, 3, 0.03),
    ("Mojave National Preserve", 35.1400, -115.5100, {"desert": 1}, 2, 0.06),
    ("Kern NWR", 35.7560, -119.6000, {"cvalley": .6, "wetland": .4}, 3, 0.02),
    ("Merced NWR", 37.1700, -120.5500, {"cvalley": .6, "wetland": .4}, 4, 0.02),
    ("Grasslands, Los Banos", 37.1500, -120.8300, {"cvalley": .6, "wetland": .4}, 4, 0.03),
    ("Cosumnes River Preserve", 38.2700, -121.4200, {"cvalley": .6, "wetland": .4}, 4, 0.02),
    ("Sacramento NWR", 39.4200, -122.1000, {"cvalley": .6, "wetland": .4}, 3, 0.02),
    ("Sacramento (urban)", 38.5816, -121.4944, {"urban_inland": 1}, 7, 0.03),
    ("Yosemite Valley", 37.7450, -119.5930, {"montane": 1}, 8, 0.01),
    ("Tuolumne Meadows", 37.8730, -119.3580, {"montane": 1}, 3, 0.02),
    ("Sequoia NP", 36.5650, -118.7700, {"montane": 1}, 4, 0.02),
    ("Lake Tahoe: Fallen Leaf", 38.9300, -120.0700, {"montane": 1}, 4, 0.02),
    ("Lassen Volcanic NP", 40.4700, -121.5100, {"montane": 1}, 2, 0.02),
    ("Mount Shasta", 41.3500, -122.2500, {"montane": 1}, 2, 0.03),
    ("Mono Lake: South Tufa", 37.9400, -119.0300, {"gbasin": 1}, 4, 0.02),
    ("Owens Valley, Bishop", 37.3600, -118.4000, {"gbasin": 1}, 2, 0.03),
    ("Humboldt Bay NWR", 40.6700, -124.2200, {"wetland": .5, "coast": .5}, 3, 0.01),
    ("Arcata Marsh", 40.8690, -124.0890, {"wetland": 1}, 3, 0.006),
    ("Prairie Creek Redwoods", 41.3650, -124.0240, {"redwood": 1}, 3, 0.01),
    ("Klamath Basin NWR", 41.9600, -121.7300, {"cvalley": .5, "wetland": .5}, 2, 0.03),
    ("Point Arena", 38.9500, -123.7400, {"coast": 1}, 1, 0.005),
    ("MacKerricher, Fort Bragg", 39.4800, -123.8000, {"coast": 1}, 2, 0.005),
]


def google_time_skew():
    """Google's servers' idea of 'now' vs this machine (a wrong clock makes signed tokens invalid)."""
    import requests

    date = requests.head("https://www.google.com", timeout=10).headers["Date"]
    real = email.utils.parsedate_to_datetime(date).replace(tzinfo=None)
    return real, real - dt.datetime.utcnow()


def fix_clock():
    real, skew = google_time_skew()
    if abs(skew.total_seconds()) > 30:
        import google.auth._helpers as h

        original = h.utcnow
        h.utcnow = lambda: original() + skew
        print(f"Corrected clock skew of {skew} for Google auth.")
    return real.replace(tzinfo=dt.timezone.utc)


def make_sightings(count, now_utc, seed=20260925):
    rng = random.Random(seed)
    site_pick = rng.choices(SITES, weights=[s[4] for s in SITES], k=count)
    out = []
    for n, (name, lat0, lon0, habitats, _w, sigma) in enumerate(site_pick, 1):
        # date: 40% in the last 45 days, the rest spread over ~12 months; local morning-heavy time of day
        for _ in range(60):
            days = rng.uniform(0, 45) if rng.random() < 0.40 else rng.uniform(45, 360)
            hour = rng.choices([6, 7, 8, 9, 10, 11, 13, 15, 16, 17, 18], weights=[5, 9, 10, 8, 5, 2, 2, 3, 4, 4, 2], k=1)[0]
            local = (now_utc - dt.timedelta(days=days)).astimezone(PT).replace(hour=hour, minute=rng.randrange(60), second=rng.randrange(60), microsecond=0)
            if local.astimezone(dt.timezone.utc) > now_utc:
                continue
            month = local.month
            pool_name = rng.choices(list(habitats), weights=list(habitats.values()), k=1)[0]
            pool = [p for p in POOLS[pool_name] if month in SEASON[p[2]]]
            if pool:
                break
        else:
            raise RuntimeError("no valid species/date found for " + name)
        species, _, _ = rng.choices(pool, weights=[p[1] for p in pool], k=1)[0]
        audio = species in VOCAL and rng.random() < 0.22
        conf = round(rng.uniform(0.45, 0.95) if audio else min(0.98, max(0.55, rng.gauss(0.85, 0.09))), 2)
        suggestions = [{"species": species, "confidence": conf}]
        if audio and rng.random() < 0.25:
            others = [p for p in pool if p[0] in VOCAL and p[0] != species]
            if others:
                sp2 = rng.choice(others)[0]
                suggestions.append({"species": sp2, "confidence": round(rng.uniform(0.5, 0.8), 2)})
        created = local.astimezone(dt.timezone.utc)
        out.append({
            "_id": f"demo-{n:04d}",
            "isDemo": True,
            "userId": "demo-seed",
            "username": f"sample_birder_{rng.randint(1, 8)}",
            "mediaType": "audio" if audio else "photo",
            "latitude": round(min(41.98, max(32.56, lat0 + rng.gauss(0, sigma))), 5),  # stay inside California
            "longitude": round(lon0 + rng.gauss(0, sigma), 5),
            "annotationCount": 0,
            "notes": "Sample data (not a real observation)",
            "aiSpeciesSuggestion": species,
            "aiConfidence": conf,
            "aiSpeciesSuggestions": suggestions,
            "createdAt": created,
            "aiAnalyzedAt": created,
            "_site": name,
            "_habitat": pool_name,
        })
    return out


def summarize(docs):
    print(f"{len(docs)} sample sightings")
    print("media:", dict(collections.Counter(d["mediaType"] for d in docs)))
    print("species:", len({d['aiSpeciesSuggestion'] for d in docs}), "distinct; top 10:",
          collections.Counter(d["aiSpeciesSuggestion"] for d in docs).most_common(10))
    print("habitats:", dict(collections.Counter(d["_habitat"] for d in docs)))
    print("months:", dict(sorted(collections.Counter(d["createdAt"].astimezone(PT).month for d in docs).items())))
    print("sites:", len({d['_site'] for d in docs}))
    lats = [d["latitude"] for d in docs]; lons = [d["longitude"] for d in docs]
    print(f"lat {min(lats)}..{max(lats)}  lon {min(lons)}..{max(lons)}")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--count", type=int, default=500)
    ap.add_argument("--commit", action="store_true", help="write to Firestore")
    ap.add_argument("--remove", action="store_true", help="delete all isDemo sightings")
    ap.add_argument("--service-account")
    args = ap.parse_args()

    now_utc = fix_clock()

    if args.remove:
        from firestore_client import get_db

        db = get_db(args.service_account)
        refs = [d.reference for d in db.collection("sightings").where("isDemo", "==", True).stream()]
        for i in range(0, len(refs), 400):
            batch = db.batch()
            for r in refs[i:i + 400]:
                batch.delete(r)
            batch.commit()
        print(f"Removed {len(refs)} sample sightings.")
        return

    docs = make_sightings(args.count, now_utc)
    summarize(docs)
    if not args.commit:
        print("Dry run only. Re-run with --commit to write.")
        return

    from firestore_client import get_db

    db = get_db(args.service_account)
    for i in range(0, len(docs), 400):
        batch = db.batch()
        for d in docs[i:i + 400]:
            data = {k: v for k, v in d.items() if not k.startswith("_")}
            batch.set(db.collection("sightings").document(d["_id"]), data)
        batch.commit()
        print(f"wrote {min(i + 400, len(docs))}/{len(docs)}")
    print("Done. Remove them any time with: python seed_demo_sightings.py --remove")


if __name__ == "__main__":
    main()
