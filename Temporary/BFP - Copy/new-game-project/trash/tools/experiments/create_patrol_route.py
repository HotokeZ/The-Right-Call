#!/usr/bin/env python3
"""Create a patrol route that follows main roads in Santa Cruz.

This script creates a circuit route that follows primary/secondary roads
like a patrol car would, staying within the city center.
"""
import argparse
import json
from pathlib import Path
import networkx as nx
from pyproj import Transformer

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--place", default="Santa Cruz, Laguna, Philippines")
    parser.add_argument("--out", default="data/patrol_route.json")
    parser.add_argument("--circuit-length", type=int, default=8, help="Target number of major intersections to visit")
    args = parser.parse_args()

    try:
        import osmnx as ox
    except ImportError:
        print("Missing dependencies: pip install osmnx")
        raise

    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)

    print("Loading graph for main roads in:", args.place)
    # Filter for main roads only (primary, secondary, trunk)
    G = ox.graph_from_place(
        args.place, 
        network_type="drive",
        custom_filter='["highway"~"primary|secondary|trunk|primary_link|secondary_link"]'
    )

    # Project to EPSG:3857
    try:
        G_proj = ox.project_graph(G, to_crs="EPSG:3857")
    except TypeError:
        G_proj = ox.project_graph(G)

    print(f"Main road network: {len(G_proj.nodes)} nodes, {len(G_proj.edges)} edges")

    # Find center point and major nodes
    nodes_data = list(G_proj.nodes(data=True))
    if not nodes_data:
        print("No main roads found!")
        return

    # Get geographic center
    x_coords = [data['x'] for _, data in nodes_data]
    y_coords = [data['y'] for _, data in nodes_data]
    center_x = sum(x_coords) / len(x_coords)
    center_y = sum(y_coords) / len(y_coords)

    # Find nodes with highest degree (major intersections) near center
    center_node = min(G_proj.nodes(), key=lambda n: 
        ((G_proj.nodes[n]['x'] - center_x)**2 + (G_proj.nodes[n]['y'] - center_y)**2)**0.5
    )

    # Create a patrol circuit by finding a path that visits major intersections
    major_nodes = [
        node for node, degree in G_proj.degree() 
        if degree >= 3  # Intersections with 3+ connections
    ]
    
    # Sort by distance from center and take the closest ones
    major_nodes.sort(key=lambda n: 
        ((G_proj.nodes[n]['x'] - center_x)**2 + (G_proj.nodes[n]['y'] - center_y)**2)**0.5
    )
    
    # Create patrol circuit visiting major intersections
    circuit_nodes = [center_node]
    visited = {center_node}
    current = center_node
    
    for _ in range(min(args.circuit_length - 1, len(major_nodes) - 1)):
        # Find closest unvisited major intersection
        candidates = [n for n in major_nodes if n not in visited]
        if not candidates:
            break
            
        try:
            # Find reachable candidates
            reachable = []
            for candidate in candidates[:5]:  # Check top 5 closest
                try:
                    path_length = nx.shortest_path_length(G_proj, current, candidate, weight='length')
                    reachable.append((candidate, path_length))
                except nx.NetworkXNoPath:
                    continue
            
            if reachable:
                # Choose closest reachable intersection
                next_node = min(reachable, key=lambda x: x[1])[0]
                circuit_nodes.append(next_node)
                visited.add(next_node)
                current = next_node
        except Exception:
            break

    # Close the circuit by returning to start
    if len(circuit_nodes) > 1:
        circuit_nodes.append(center_node)

    print(f"Patrol circuit: {len(circuit_nodes)} waypoints")

    # Build complete route through all waypoints
    route_nodes = []
    for i in range(len(circuit_nodes) - 1):
        try:
            path = nx.shortest_path(G_proj, circuit_nodes[i], circuit_nodes[i+1], weight='length')
            if i == 0:
                route_nodes.extend(path)
            else:
                route_nodes.extend(path[1:])  # Skip first node to avoid duplicates
        except nx.NetworkXNoPath:
            print(f"Warning: No path from {circuit_nodes[i]} to {circuit_nodes[i+1]}")
            continue

    if not route_nodes:
        print("Could not create patrol route!")
        return

    print(f"Complete patrol route: {len(route_nodes)} nodes")

    # Convert to coordinates
    coords_proj = [(G_proj.nodes[n]["x"], G_proj.nodes[n]["y"]) for n in route_nodes]

    # Load bounds for normalization (same as route export)
    bounds_file = Path("map.png.bounds.json")
    bbox_path = Path("data/santacruz_bbox.json")
    
    if bounds_file.exists():
        with open(bounds_file, "r", encoding="utf-8") as f:
            bounds = json.load(f)
            minx, miny = bounds["minx"], bounds["miny"]
            maxx, maxy = bounds["maxx"], bounds["maxy"]
    elif bbox_path.exists():
        with open(bbox_path, "r", encoding="utf-8") as f:
            meta = json.load(f)
            bounds_data = meta.get("bounds")
            if isinstance(bounds_data[0], (list, tuple)):
                minlon, minlat, maxlon, maxlat = bounds_data[0]
            else:
                minlon, minlat, maxlon, maxlat = bounds_data

        transformer = Transformer.from_crs("EPSG:4326", "EPSG:3857", always_xy=True)
        c1 = transformer.transform(minlon, minlat)
        c2 = transformer.transform(minlon, maxlat)
        c3 = transformer.transform(maxlon, minlat)
        c4 = transformer.transform(maxlon, maxlat)
        xs = [c1[0], c2[0], c3[0], c4[0]]
        ys = [c1[1], c2[1], c3[1], c4[1]]
        minx_base, maxx_base = min(xs), max(xs)
        miny_base, maxy_base = min(ys), max(ys)
        
        # Add same padding as map renderer
        padding = max(maxx_base - minx_base, maxy_base - miny_base) * 0.1
        minx = minx_base - padding
        maxx = maxx_base + padding
        miny = miny_base - padding
        maxy = maxy_base + padding
    else:
        # Fallback
        xs = [x for x, y in coords_proj]
        ys = [y for x, y in coords_proj]
        minx, maxx = min(xs), max(xs)
        miny, maxy = min(ys), max(ys)

    width = maxx - minx if maxx - minx != 0 else 1.0
    height = maxy - miny if maxy - miny != 0 else 1.0

    # Normalize coordinates
    points_norm = []
    for x, y in coords_proj:
        nx = (x - minx) / width
        ny = (y - miny) / height
        points_norm.append([nx, ny])

    # Create patrol route data
    payload = {
        "type": "patrol_circuit",
        "waypoints": len(circuit_nodes),
        "total_points": len(points_norm),
        "points": points_norm,
        "is_loop": True
    }

    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(payload, f, indent=2)

    print(f"Wrote patrol route to {out_path} ({len(points_norm)} points, {len(circuit_nodes)} waypoints)")

if __name__ == "__main__":
    main()