"""Sun elevation from a UTC time and a place (NOAA's low-precision algorithm, no refraction, no dependencies).
Used to pick photos taken at low sun (sunrise / sunset / golden hour) out of iNaturalist's timestamped observations."""
import math
from datetime import datetime, timezone


def solar_elevation(dt_utc: datetime, lat: float, lon: float) -> float:
    """Degrees above the horizon (negative = below). lon is east-positive."""
    jd = dt_utc.timestamp() / 86400 + 2440587.5
    jc = (jd - 2451545) / 36525
    rad, deg = math.radians, math.degrees
    L = (280.46646 + jc * (36000.76983 + jc * 0.0003032)) % 360
    M = 357.52911 + jc * (35999.05029 - 0.0001537 * jc)
    e = 0.016708634 - jc * (0.000042037 + 0.0000001267 * jc)
    c = (math.sin(rad(M)) * (1.914602 - jc * (0.004817 + 0.000014 * jc))
         + math.sin(rad(2 * M)) * (0.019993 - 0.000101 * jc) + math.sin(rad(3 * M)) * 0.000289)
    app = L + c - 0.00569 - 0.00478 * math.sin(rad(125.04 - 1934.136 * jc))
    obl = 23 + (26 + (21.448 - jc * (46.815 + jc * (0.00059 - jc * 0.001813))) / 60) / 60
    obl += 0.00256 * math.cos(rad(125.04 - 1934.136 * jc))
    decl = deg(math.asin(math.sin(rad(obl)) * math.sin(rad(app))))
    y = math.tan(rad(obl / 2)) ** 2
    eq = 4 * deg(y * math.sin(2 * rad(L)) - 2 * e * math.sin(rad(M)) + 4 * e * y * math.sin(rad(M)) * math.cos(2 * rad(L))
                 - 0.5 * y * y * math.sin(4 * rad(L)) - 1.25 * e * e * math.sin(2 * rad(M)))
    t = dt_utc.astimezone(timezone.utc)
    minutes = t.hour * 60 + t.minute + t.second / 60
    tst = (minutes + eq + 4 * lon) % 1440
    ha = tst / 4 - 180
    if ha < -180:
        ha += 360
    cosz = math.sin(rad(lat)) * math.sin(rad(decl)) + math.cos(rad(lat)) * math.cos(rad(decl)) * math.cos(rad(ha))
    return 90 - deg(math.acos(max(-1, min(1, cosz))))


if __name__ == "__main__":     # sanity checks against well-known cases
    # Summer solstice, solar noon at Greenwich (lat 51.48): about 61.9 degrees
    print(round(solar_elevation(datetime(2026, 6, 21, 12, 1, tzinfo=timezone.utc), 51.48, 0.0), 1))
    # Equinox, solar noon at the equator: about 90
    print(round(solar_elevation(datetime(2026, 3, 20, 12, 0, tzinfo=timezone.utc), 0.0, 0.0), 1))
    # Midnight at Greenwich in June: about -15
    print(round(solar_elevation(datetime(2026, 6, 21, 0, 0, tzinfo=timezone.utc), 51.48, 0.0), 1))
