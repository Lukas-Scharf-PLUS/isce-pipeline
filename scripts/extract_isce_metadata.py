#!/usr/bin/env python3

"""
Extract metadata from an ISCE topsStack processing directory.

Example
-------
python extract_isce_metadata.py \
    --workdir /data/ISCE_output/stack_xxx
"""

from pathlib import Path
import argparse
import yaml
from typing import List, Iterable
import xml.etree.ElementTree as ET
from datetime import datetime


def parse_args():
    parser = argparse.ArgumentParser(
        description="Extract metadata from an ISCE stack."
    )

    parser.add_argument(
    "--workdir",
    type=Path,
    required=True,
    help="Path to the ISCE stack directory."
    )

    parser.add_argument(
        "--output",
        type=Path,
        default=None,
        help="Output YAML file (default: <workdir>/isce_metadata.yaml)"
    )


    parser.add_argument(
    "--orbit-state",
    type=str,
    required=True,
    help="Orbit direction (ASC/DES)"
)

    parser.add_argument(
        "--relative-orbit",
        type=int,
        required=True,
        help="Sentinel-1 relative orbit number"
    )

    parser.add_argument(
        "--range-looks",
        type=int,
        required=True,
        help="Number of range looks"
    )

    parser.add_argument(
        "--azimuth-looks",
        type=int,
        required=True,
        help="Number of azimuth looks"
    )

    parser.add_argument(
        "--connections",
        type=int,
        required=True,
        help="Number of interferometric connections"
    )

    parser.add_argument(
        "--filter-strength",
        type=float,
        required=True,
        help="Goldstein filter strength"
    )

    parser.add_argument(
        "--bbox",
        type=str,
        required=True,
        help="Bounding box (south north west east)"
    )


    return parser.parse_args()
  


def require_dir(path: Path):
    """Raise an exception if a required directory does not exist."""
    if not path.is_dir():
        raise FileNotFoundError(f"Missing directory: {path}")
    

def first_file(files: Iterable[Path]) -> Path:
    """
    Return the first file from an iterable of Path objects.

    Raises
    ------
    RuntimeError
        If no matching files are found.
    """
    files = sorted(files)

    if not files:
        raise RuntimeError("No matching files found.")

    return files[0]

def detect_acquisitions(workdir: Path) -> List[str]:

    """
    Return the acquisition dates contained in the merged SLC stack.
    """

    slc_dir = workdir / "merged" / "SLC"

    require_dir(slc_dir)

    acquisitions = sorted(
        d.name
        for d in slc_dir.iterdir()
        if d.is_dir()
    )

    if not acquisitions:
        raise RuntimeError(f"No acquisitions found in {slc_dir}")

    return acquisitions


def detect_reference_date(workdir: Path) -> str:
    """
    Detect the ISCE reference date from the baselines directory.

    Example:
        baselines/
            20200616_20200604/
            20200616_20200610/
            20200616_20200622/

    -> returns "20200616"
    """

    baseline_dir = workdir / "baselines"

    require_dir(baseline_dir)

    references = set()

    for d in baseline_dir.iterdir():

        if not d.is_dir():
            continue

        parts = d.name.split("_")

        if len(parts) != 2:
            continue

        references.add(parts[0])

    if len(references) == 0:
        raise RuntimeError(
            "No baseline directories found."
        )

    if len(references) > 1:
        raise RuntimeError(
            f"Multiple reference dates detected: {sorted(references)}"
        )

    return references.pop()


def detect_isce_version(workdir: Path) -> str:
    """
    Detect the ISCE version from the merged SLC XML metadata.
    """

    slc_dir = workdir / "merged" / "SLC"

    require_dir(slc_dir)

    xml_file = first_file(slc_dir.glob("*/*.xml"))

    tree = ET.parse(xml_file)
    root = tree.getroot()

    for prop in root.findall(".//property"):

        if prop.attrib.get("name") != "ISCE_VERSION":
            continue

        value = prop.find("value")

        if value is None:
            break

        return value.text.strip()

    raise RuntimeError("Could not determine ISCE version.")


def parse_bbox(bbox: str) -> List[float]:
    """
    Convert a bounding box from

        south north west east

    to STAC/GeoJSON order

        west south east north

    Example
    -------
    Input:
        "48.12 48.33 16.18 16.58"

    Output:
        [16.18, 48.12, 16.58, 48.33]
    """

    if bbox is None or bbox.strip() == "":
        return []

    values = [float(v) for v in bbox.split()]

    if len(values) != 4:
        raise ValueError(
            "Bounding box must contain four values: "
            "south north west east"
        )

    south, north, west, east = values

    return [west, south, east, north]


def detect_safe_products(workdir: Path) -> List[str]:
    """
    Return the list of Sentinel-1 SAFE products used to build the stack.
    """

    input_file = workdir / "input_scenes.txt"

    if not input_file.is_file():
        raise FileNotFoundError(f"Missing file: {input_file}")

    safe_products = []

    with open(input_file) as f:
        for line in f:

            line = line.strip()

            if not line:
                continue

            safe_products.append(Path(line).name)

    if not safe_products:
        raise RuntimeError("No SAFE products found in input_scenes.txt")

    return safe_products


def detect_slc_suffix(workdir: Path) -> str:
    """
    Detect the merged SLC filename suffix.

    Example
    -------
    20200604.slc.full.xml
        -> .slc.full
    """

    slc_dir = workdir / "merged" / "SLC"

    require_dir(slc_dir)

    xml_file = first_file(slc_dir.glob("*/*.xml"))

    stem = xml_file.stem

    acquisition = xml_file.parent.name

    prefix = acquisition

    if not stem.startswith(prefix):
        raise RuntimeError(
            f"Unexpected merged SLC filename: {xml_file.name}"
        )

    return stem[len(prefix):]


def detect_geometry_suffix(workdir: Path) -> str:
    """
    Detect the merged geometry filename suffix.

    Example
    -------
    lat.rdr.full.xml
        -> .rdr.full
    """

    geom_dir = workdir / "merged" / "geom_reference"

    require_dir(geom_dir)

    xml_file = first_file(geom_dir.glob("lat*.xml"))

    stem = xml_file.stem

    if not stem.startswith("lat"):
        raise RuntimeError(
            f"Unexpected merged geom_reference filename: {xml_file.name}"
        )

    return stem[len("lat"):]


def detect_satellites(safe_products: List[str]) -> List[str]:
    return sorted({p[:3] for p in safe_products})

def detect_polarization(safe_products: List[str]) -> str:
    product = safe_products[0]

    return product.split("_")[4][-2:]

def detect_beam_mode(safe_products: List[str]) -> str:
    product = safe_products[0]

    return product.split("_")[1]

def detect_wavelength(workdir: Path) -> float:
    """
    Detect the radar wavelength from the ISCE reference XML.

    Example
    -------
    reference/IW*.xml

    <property name="radarwavelength">
        <value>0.05546576</value>
    </property>
    """

    reference_dir = workdir / "reference"

    require_dir(reference_dir)

    xml_file = first_file(reference_dir.glob("IW*.xml"))

    tree = ET.parse(xml_file)
    root = tree.getroot()

    for prop in root.findall(".//property"):

        if prop.attrib.get("name") != "radarwavelength":
            continue

        value = prop.find("value")

        if value is None:
            break

        return float(value.text.strip())

    raise RuntimeError(
        f"Could not determine radar wavelength from {xml_file.name}"
    )


def find_stackdir(workdir: Path) -> Path:
    """
    Return the ISCE stack directory.

    If workdir already points to a stack directory, return it.
    Otherwise search for a single stack_* directory.
    """

    # Already a stack directory
    if (workdir / "merged").is_dir():
        return workdir

    stackdirs = sorted(
        d for d in workdir.iterdir()
        if d.is_dir() and d.name.startswith("stack_")
    )

    if len(stackdirs) == 0:
        raise RuntimeError(f"No stack_* directory found in {workdir}")

    if len(stackdirs) > 1:
        raise RuntimeError(
            f"Multiple stack directories found: {[d.name for d in stackdirs]}"
        )

    return stackdirs[0]


def main():

    args = parse_args()

    workdir = args.workdir.resolve()

    if not workdir.exists():
        raise FileNotFoundError(workdir)

    workdir = find_stackdir(workdir)

    acquisitions = detect_acquisitions(workdir)
    safe_products = detect_safe_products(workdir)

    output = args.output

    if output is None:
        output = workdir / "isce_metadata.yaml"

    metadata = {

        "metadata": {
            "generated": datetime.utcnow().isoformat() + "Z"
        },

        "isce": {
            "version": detect_isce_version(workdir),
        },

        "acquisition": {  
            "orbit_state": args.orbit_state,
            "relative_orbit": args.relative_orbit,
        },
        
        
        "input": {
            "satellites": detect_satellites(safe_products),
            "safe_products": safe_products,
        },

        "stack": {
            "start_date": acquisitions[0],
            "end_date": acquisitions[-1],
            "reference_date": detect_reference_date(workdir),
            "acquisitions": acquisitions,
        },

        "processing": {
            "range_looks": args.range_looks,
            "azimuth_looks": args.azimuth_looks,
            "connections": args.connections,
            "filter_strength": args.filter_strength,
            "bbox": parse_bbox(args.bbox)
        },

        "radar": {
            "wavelength": detect_wavelength(workdir),
            "polarization": detect_polarization(safe_products),
            "beam_mode": detect_beam_mode(safe_products),
        },

        "paths": {
            "merged_slc": "merged/SLC",
            "merged_geometry": "merged/geom_reference",
            "baselines": "baselines",
            "reference": "reference",
            "coreg_secondarys": "coreg_secondarys"
        },

        "suffixes": {
            "slc": detect_slc_suffix(workdir),
            "geometry": detect_geometry_suffix(workdir),
},

    }

    with open(output, "w") as f:
        yaml.safe_dump(metadata, f, sort_keys=False)

    print(f"Wrote {output}")


if __name__ == "__main__":
    main()