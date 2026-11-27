#!/usr/bin/env python3
"""Fetch the GeoNames cities15000 list and keep only what the day view needs.

Run by the fetch-cities workflow. Writes FiveSkies/Resources/Cities/cities15000.tsv with four
tab-separated columns: name, country code, latitude, longitude (4 decimals), sorted by latitude.
Names are Latin script only: when the GeoNames `name` has any other letter, `asciiname` is used.
The alternatenames column is never read.

For a local test without the network: python3 tools/fetch_cities.py --from-zip path/to/cities15000.zip
"""
import datetime
import io
import os
import sys
import unicodedata
import urllib.request
import zipfile

SOURCE_URL = "https://download.geonames.org/export/dump/cities15000.zip"
MEMBER = "cities15000.txt"
OUT = os.path.join("FiveSkies", "Resources", "Cities")
OUT_NAME = "cities15000.tsv"
MIN_ROWS = 20000
LICENSE_LINE = "City names: GeoNames (geonames.org), CC BY 4.0"
LICENSE_URL = "https://creativecommons.org/licenses/by/4.0/"

# GeoNames "geoname" table columns used here (0-based).
COL_NAME, COL_ASCII, COL_LAT, COL_LON, COL_COUNTRY = 1, 2, 4, 5, 8
COLUMNS = 19

PUNCTUATION = set(" -'.,()/&’‘`")


def is_latin_text(text):
    """True when every character is a Latin letter, an ASCII digit, a space or common punctuation."""
    if not text:
        return False
    for char in text:
        if char in PUNCTUATION:
            continue
        if "0" <= char <= "9":
            continue
        if char.isalpha() and "LATIN" in unicodedata.name(char, ""):
            continue
        return False
    return True


def display_name(name, asciiname):
    """The GeoNames name when it is Latin script, else the ASCII name, else None (row skipped)."""
    name = unicodedata.normalize("NFC", name.strip())
    if is_latin_text(name):
        return name
    asciiname = asciiname.strip()
    if is_latin_text(asciiname):
        return asciiname
    return None


def coordinate(text):
    value = round(float(text), 4)
    if value == 0:
        value = 0.0  # no "-0.0000"
    return value


def parse_line(line):
    """One GeoNames row to (name, country, latitude, longitude), or None if it cannot be used."""
    fields = line.rstrip("\r\n").split("\t")
    if len(fields) != COLUMNS:
        return None
    name = display_name(fields[COL_NAME], fields[COL_ASCII])
    if name is None:
        return None
    country = fields[COL_COUNTRY].strip().upper()
    if country and not (len(country) == 2 and country.isascii() and country.isalpha()):
        return None
    try:
        latitude = coordinate(fields[COL_LAT])
        longitude = coordinate(fields[COL_LON])
    except ValueError:
        return None
    if not (-90 <= latitude <= 90 and -180 <= longitude <= 180):
        return None
    return name, country, latitude, longitude


def build_rows(lines):
    rows = []
    skipped = 0
    for line in lines:
        if not line.strip():
            continue
        row = parse_line(line)
        if row is None:
            skipped += 1
            continue
        rows.append(row)
    rows.sort(key=lambda row: (row[2], row[3], row[0]))
    return rows, skipped


def render(rows):
    out = io.StringIO()
    for name, country, latitude, longitude in rows:
        out.write(f"{name}\t{country}\t{latitude:.4f}\t{longitude:.4f}\n")
    return out.getvalue()


def verify(text):
    """Checks the written text itself: row count, four columns, Latin script only, sorted."""
    lines = text.splitlines()
    if len(lines) < MIN_ROWS:
        sys.exit(f"only {len(lines)} rows, expected at least {MIN_ROWS}")
    previous = -91.0
    for number, line in enumerate(lines, 1):
        fields = line.split("\t")
        if len(fields) != 4:
            sys.exit(f"row {number}: expected 4 columns, found {len(fields)}")
        if not is_latin_text(fields[0]):
            sys.exit(f"row {number}: name is not Latin script")
        latitude = float(fields[2])
        if latitude < previous:
            sys.exit(f"row {number}: not sorted by latitude")
        previous = latitude
    print(f"verified: {len(lines)} rows, 4 columns, Latin script names, sorted by latitude")


def download():
    last_error = None
    for attempt in range(1, 4):
        try:
            request = urllib.request.Request(SOURCE_URL, headers={"User-Agent": "five-skies-content-fetch/1.0"})
            with urllib.request.urlopen(request, timeout=120) as response:
                data = response.read()
            print(f"fetched {len(data)} bytes from {SOURCE_URL}")
            return data
        except Exception as error:  # noqa: BLE001
            last_error = error
            print(f"attempt {attempt} failed: {error}")
    sys.exit(f"download failed: {last_error}")


def read_member(archive_bytes):
    archive = zipfile.ZipFile(io.BytesIO(archive_bytes))
    names = [n for n in archive.namelist() if os.path.basename(n) == MEMBER]
    if not names:
        sys.exit(f"{MEMBER} not found in the archive: {archive.namelist()[:10]}")
    return archive.read(names[0]).decode("utf-8")


def main(argv):
    if len(argv) == 3 and argv[1] == "--from-zip":
        with open(argv[2], "rb") as handle:
            archive_bytes = handle.read()
        out_dir = os.environ.get("FS_CITIES_OUT", OUT)
    else:
        archive_bytes = download()
        out_dir = OUT

    rows, skipped = build_rows(read_member(archive_bytes).splitlines())
    print(f"kept {len(rows)} rows, skipped {skipped}")
    text = render(rows)
    verify(text)

    os.makedirs(out_dir, exist_ok=True)
    with open(os.path.join(out_dir, OUT_NAME), "w", encoding="utf-8", newline="\n") as handle:
        handle.write(text)
    today = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d")
    with open(os.path.join(out_dir, "SOURCE.txt"), "w", encoding="utf-8", newline="\n") as handle:
        handle.write(f"{LICENSE_LINE}\n")
        handle.write(f"License: Creative Commons Attribution 4.0 International, {LICENSE_URL}\n")
        handle.write(f"Source: {SOURCE_URL}\n")
        handle.write(f"Downloaded: {today} (UTC) by tools/fetch_cities.py\n")
        handle.write("Changes: kept only name, country code, latitude and longitude; coordinates rounded to 4 decimals;\n")
        handle.write("names in a non-Latin script replaced by the GeoNames ASCII name; sorted by latitude.\n")
        handle.write(f"Rows: {len(rows)}\n")
    print("done")


if __name__ == "__main__":
    main(sys.argv)
