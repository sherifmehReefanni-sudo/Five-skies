#!/usr/bin/env python3
"""Fetch the Quran text, metadata and font from their primary sources.

Run by the fetch-content workflow. Nothing here edits the Quran text: the
Tanzil file is saved exactly as downloaded, including its license notice.
The script only verifies that what was downloaded is complete.
"""
import hashlib
import io
import os
import sys
import urllib.request
import xml.etree.ElementTree as ET
import zipfile

OUT = os.path.join("FiveSkies", "Resources", "Quran")
TEXT_URLS = [
    "https://tanzil.net/pub/download/index.php?marks=true&sajdah=true&rub=true&tatweel=true&quranType=uthmani&outType=txt-2&agree=true",
    "https://tanzil.net/pub/download/v1.1/download.php?marks=true&sajdah=true&rub=true&tatweel=true&quranType=uthmani&outType=txt-2&agree=true",
]
META_URLS = [
    "https://tanzil.net/res/text/metadata/quran-data.xml",
    "http://tanzil.net/res/text/metadata/quran-data.xml",
]
FONT_ZIPS = [
    "https://github.com/aliftype/amiri/releases/download/1.003/Amiri-1.003.zip",
    "https://github.com/aliftype/amiri/releases/download/1.002/Amiri-1.002.zip",
    "https://github.com/aliftype/amiri/releases/download/1.001/Amiri-1.001.zip",
    "https://github.com/aliftype/amiri/releases/download/1.000/Amiri-1.000.zip",
]


def get(url):
    request = urllib.request.Request(url, headers={"User-Agent": "five-skies-content-fetch/1.0"})
    with urllib.request.urlopen(request, timeout=60) as response:
        return response.read()


def first(urls, label, check):
    for url in urls:
        try:
            data = get(url)
            check(data)
            print(f"{label}: fetched {len(data)} bytes from {url}")
            return data, url
        except Exception as error:  # noqa: BLE001
            print(f"{label}: {url} failed: {error}")
    sys.exit(f"{label}: no source worked")


def parse_text(data):
    verses = {}
    for line in data.decode("utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split("|", 2)
        if len(parts) != 3:
            raise ValueError(f"unexpected line: {line[:40]!r}")
        verses[(int(parts[0]), int(parts[1]))] = parts[2]
    return verses


def check_text(data):
    verses = parse_text(data)
    if len(verses) != 6236:
        raise ValueError(f"expected 6236 ayahs, found {len(verses)}")
    if "Tanzil" not in data.decode("utf-8"):
        raise ValueError("license notice missing")


def check_meta(data):
    root = ET.fromstring(data)
    suras = root.find("suras")
    if suras is None or len(suras.findall("sura")) != 114:
        raise ValueError("expected 114 suras in metadata")


def main():
    os.makedirs(OUT, exist_ok=True)
    text, text_url = first(TEXT_URLS, "text", check_text)
    meta, meta_url = first(META_URLS, "metadata", check_meta)

    verses = parse_text(text)
    root = ET.fromstring(meta)
    total = 0
    for sura in root.find("suras").findall("sura"):
        index = int(sura.get("index"))
        expected = int(sura.get("ayas"))
        found = sum(1 for (s, _a) in verses if s == index)
        if found != expected:
            sys.exit(f"sura {index}: metadata says {expected} ayahs, text has {found}")
        total += found
    if total != 6236:
        sys.exit(f"total ayahs {total}, expected 6236")
    print("verified: 114 suras, 6236 ayahs, every sura's ayah count matches the metadata")

    with open(os.path.join(OUT, "quran-uthmani.txt"), "wb") as handle:
        handle.write(text)
    with open(os.path.join(OUT, "quran-data.xml"), "wb") as handle:
        handle.write(meta)

    font_name = None
    font_url = None
    license_text = None
    for url in FONT_ZIPS:
        try:
            archive = zipfile.ZipFile(io.BytesIO(get(url)))
        except Exception as error:  # noqa: BLE001
            print(f"font: {url} failed: {error}")
            continue
        names = archive.namelist()
        fonts = [n for n in names if n.lower().endswith("amiriquran.ttf")]
        licenses = [n for n in names if os.path.basename(n).upper().startswith("OFL")]
        if fonts:
            with open(os.path.join(OUT, "AmiriQuran.ttf"), "wb") as handle:
                handle.write(archive.read(fonts[0]))
            if licenses:
                license_text = archive.read(licenses[0])
                with open(os.path.join(OUT, "AmiriQuran-OFL.txt"), "wb") as handle:
                    handle.write(license_text)
            font_name, font_url = fonts[0], url
            print(f"font: took {fonts[0]} from {url}")
            break
        print(f"font: {url} has no AmiriQuran.ttf; files: {names[:12]}")
    if font_name is None:
        sys.exit("font: no source worked")

    def digest(name):
        with open(os.path.join(OUT, name), "rb") as handle:
            return hashlib.sha256(handle.read()).hexdigest()

    with open(os.path.join(OUT, "SOURCES.md"), "w", encoding="utf-8") as handle:
        handle.write("# Quran content sources\n\n")
        handle.write("These files were downloaded by `tools/fetch_quran_content.py` and are stored exactly as received.\n")
        handle.write("Do not edit them by hand. To update, run the Fetch content workflow again.\n\n")
        handle.write(f"- `quran-uthmani.txt`: Tanzil Quran Text (Uthmani). Copyright Tanzil Project, Creative Commons Attribution 3.0, verbatim copies only. Source: {text_url}\n  sha256 `{digest('quran-uthmani.txt')}`\n")
        handle.write(f"- `quran-data.xml`: Tanzil Quran metadata. Source: {meta_url}\n  sha256 `{digest('quran-data.xml')}`\n")
        handle.write(f"- `AmiriQuran.ttf`: Amiri Quran typeface, SIL Open Font License. Source: {font_url}\n  sha256 `{digest('AmiriQuran.ttf')}`\n")
        handle.write("\nIntegrity check at download time: 114 suras, 6236 ayahs, and every sura's ayah count matches the metadata.\n")
    print("done")


if __name__ == "__main__":
    main()
