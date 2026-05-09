"""Export a shortest route between two coordinates (lat,lon) for Santa Cruz.

Usage:
  python tools/export_route.py --origin LAT,LON --dest LAT,LON --out data/route.json

This script:
 - loads the driving graph for Santa Cruz (OSMnx)
 - finds nearest nodes to the provided origin/destination coordinates
 - computes the shortest path by length
 - projects coordinates to EPSG:3857 and normalizes to the bbox saved in data/santacruz_bbox.json
 - writes a JSON file with normalized points suitable for Godot
"""
import argparse
import json
from pathlib import Path

def parse_latlon(s: str):
    try:
        parts = s.split(",")
        if len(parts) != 2:
            raise ValueError
        lat = float(parts[0].strip())
        lon = float(parts[1].strip())
        return lat, lon
    except Exception:
        raise argparse.ArgumentTypeError("Coordinates must be 'LAT,LON'")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--origin", required=True, type=parse_latlon, help="Origin as LAT,LON")
    parser.add_argument("--dest", required=True, type=parse_latlon, help="Destination as LAT,LON")
    parser.add_argument("--place", default="Santa Cruz, Laguna, Philippines")
    parser.add_argument("--out", default="data/santacruz_route.json")
    args = parser.parse_args()

    try:
        import osmnx as ox
        import networkx as nx
        from pyproj import Transformer
    except Exception as e:
        print("Missing dependencies: pip install osmnx networkx pyproj")
        raise

    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)

    print("Loading graph for:", args.place)
    G = ox.graph_from_place(args.place, network_type="drive")

    orig_lat, orig_lon = args.origin
    dest_lat, dest_lon = args.dest

    # Project the graph to EPSG:3857 so nearest-node lookups use projected coords
    # (this avoids requiring scikit-learn for KD-tree lookups on unprojected graphs)
    try:
        G_proj = ox.project_graph(G, to_crs="EPSG:3857")
    except TypeError:
        # older osmnx versions may not accept the `to_crs` kwarg
        G_proj = ox.project_graph(G)

    # transformer to convert input lon/lat -> EPSG:3857 projected coordinates
    transformer_to_3857 = Transformer.from_crs("EPSG:4326", "EPSG:3857", always_xy=True)
    orig_x, orig_y = transformer_to_3857.transform(orig_lon, orig_lat)
    dest_x, dest_y = transformer_to_3857.transform(dest_lon, dest_lat)

    # nearest_nodes expects X (lon/proj_x), Y (lat/proj_y)
    try:
        orig_node = ox.nearest_nodes(G_proj, orig_x, orig_y)
        dest_node = ox.nearest_nodes(G_proj, dest_x, dest_y)
    except Exception:
        # fallback to osmnx.distance if API differs
        try:
            from osmnx import distance as _dist

            orig_node = _dist.nearest_nodes(G_proj, orig_x, orig_y)
            dest_node = _dist.nearest_nodes(G_proj, dest_x, dest_y)
        except Exception:
            raise

    print(f"Computing shortest path between nodes {orig_node} -> {dest_node}")
    route = nx.shortest_path(G_proj, orig_node, dest_node, weight="length")

    # Collect node projected coordinates (x, y) in EPSG:3857
    coords_proj = [(G_proj.nodes[n]["x"], G_proj.nodes[n]["y"]) for n in route]

    # load place bbox to normalize
    bbox_path = Path("data/santacruz_bbox.json")
    if bbox_path.exists():
        with open(bbox_path, "r", encoding="utf-8") as f:
            meta = json.load(f)
            try:
                minlon, minlat, maxlon, maxlat = meta.get("bounds")
            except Exception:
                # older tuple ordering
                minlon, minlat, maxlon, maxlat = meta.get("bounds")[0]

        # project bbox to EPSG:3857 and compute extents
        c1 = transformer_to_3857.transform(minlon, minlat)
        c2 = transformer_to_3857.transform(minlon, maxlat)
        c3 = transformer_to_3857.transform(maxlon, minlat)
        c4 = transformer_to_3857.transform(maxlon, maxlat)
        xs = [c1[0], c2[0], c3[0], c4[0]]
        ys = [c1[1], c2[1], c3[1], c4[1]]
        minx, maxx = min(xs), max(xs)
        miny, maxy = min(ys), max(ys)
    else:
        # fallback: compute bbox directly from projected coordinates
        xs = [x for x, y in coords_proj]
        ys = [y for x, y in coords_proj]
        minx, maxx = min(xs), max(xs)
        miny, maxy = min(ys), max(ys)

    width = maxx - minx if maxx - minx != 0 else 1.0
    height = maxy - miny if maxy - miny != 0 else 1.0

    points_norm = []
    for x, y in coords_proj:
        nx = (x - minx) / width
        ny = (y - miny) / height
        points_norm.append([nx, ny])

    payload = {"origin": [orig_lat, orig_lon], "destination": [dest_lat, dest_lon], "points": points_norm}
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(payload, f, indent=2)

    print(f"Wrote route to {out_path} ({len(points_norm)} points)")


if __name__ == "__main__":
    main()
