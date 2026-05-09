#!/usr/bin/env python3
"""
Generate patrol routes based on pixel-level road data extracted from satellite imagery.
Creates connected paths that follow the actual visual roads.
"""

import json
import numpy as np
from scipy.spatial.distance import cdist
from scipy.sparse.csgraph import minimum_spanning_tree
import networkx as nx

def load_road_pixels(road_pixels_path):
    """Load road pixel data from JSON."""
    with open(road_pixels_path, 'r') as f:
        data = json.load(f)
    return data['road_pixels'], data['image_dimensions']

def create_pixel_graph(road_pixels, connection_threshold=0.02):
    """
    Create a graph connecting nearby road pixels.
    
    Args:
        road_pixels: List of road pixel coordinates
        connection_threshold: Maximum distance to connect pixels (normalized)
    """
    
    print(f"Creating graph from {len(road_pixels)} road pixels...")
    
    # Extract coordinates
    coords = np.array([[p['x'], p['y']] for p in road_pixels])
    
    # Create graph
    G = nx.Graph()
    
    # Add nodes
    for i, pixel in enumerate(road_pixels):
        G.add_node(i, x=pixel['x'], y=pixel['y'])
    
    # Connect nearby pixels
    print("Connecting nearby pixels...")
    distances = cdist(coords, coords)
    
    connections_added = 0
    for i in range(len(road_pixels)):
        # Find pixels within connection threshold
        nearby_indices = np.where((distances[i] < connection_threshold) & (distances[i] > 0))[0]
        
        for j in nearby_indices:
            if not G.has_edge(i, j):
                weight = distances[i][j]
                G.add_edge(i, j, weight=weight)
                connections_added += 1
    
    print(f"Added {connections_added} connections between pixels")
    print(f"Graph has {G.number_of_nodes()} nodes and {G.number_of_edges()} edges")
    
    return G

def find_connected_components(G):
    """Find the largest connected component for patrol routing."""
    components = list(nx.connected_components(G))
    components.sort(key=len, reverse=True)
    
    print(f"Found {len(components)} connected components")
    if components:
        print(f"Largest component has {len(components[0])} nodes")
        return G.subgraph(components[0]).copy()
    
    return G

def generate_patrol_circuit(G, circuit_length=200):
    """
    Generate a patrol circuit that covers different areas of the road network.
    
    Args:
        G: Road pixel graph
        circuit_length: Desired number of points in the patrol circuit
    """
    
    print(f"Generating patrol circuit with ~{circuit_length} points...")
    
    if G.number_of_nodes() == 0:
        return []
    
    # Start from a random node
    start_node = list(G.nodes())[0]
    current_node = start_node
    visited = set()
    circuit = [current_node]
    visited.add(current_node)
    
    # Use a greedy approach to build a circuit
    while len(circuit) < circuit_length and len(visited) < G.number_of_nodes():
        
        # Get neighbors of current node
        neighbors = list(G.neighbors(current_node))
        
        # Prefer unvisited neighbors, then closest visited ones
        unvisited_neighbors = [n for n in neighbors if n not in visited]
        
        if unvisited_neighbors:
            # Choose the unvisited neighbor (prefer ones with many connections)
            next_node = max(unvisited_neighbors, key=lambda n: G.degree(n))
        elif neighbors:
            # If all neighbors visited, choose the one with shortest path back to unvisited areas
            next_node = min(neighbors, key=lambda n: G[current_node][n]['weight'])
        else:
            # Dead end, try to find path to unvisited area
            unvisited = set(G.nodes()) - visited
            if unvisited:
                try:
                    target = list(unvisited)[0]
                    path = nx.shortest_path(G, current_node, target)
                    if len(path) > 1:
                        next_node = path[1]
                    else:
                        next_node = target
                except nx.NetworkXNoPath:
                    break
            else:
                break
        
        circuit.append(next_node)
        visited.add(next_node)
        current_node = next_node
    
    # Try to connect back to start for a proper circuit
    try:
        if current_node != start_node:
            return_path = nx.shortest_path(G, current_node, start_node)
            if len(return_path) > 1:
                circuit.extend(return_path[1:])  # Skip the current node
    except nx.NetworkXNoPath:
        pass
    
    print(f"Generated circuit with {len(circuit)} points")
    return circuit

def create_patrol_route_from_pixels(road_pixels_path, output_route_path, circuit_length=200):
    """
    Create a patrol route from pixel-level road data.
    """
    
    # Load road pixel data
    road_pixels, image_dims = load_road_pixels(road_pixels_path)
    
    if len(road_pixels) < 10:
        raise ValueError(f"Not enough road pixels found: {len(road_pixels)}")
    
    # Create pixel graph
    G = create_pixel_graph(road_pixels, connection_threshold=0.015)
    
    # Find largest connected component
    G = find_connected_components(G)
    
    if G.number_of_nodes() < 10:
        raise ValueError(f"Not enough connected road pixels: {G.number_of_nodes()}")
    
    # Generate patrol circuit
    circuit_nodes = generate_patrol_circuit(G, circuit_length)
    
    if len(circuit_nodes) < 10:
        raise ValueError(f"Generated circuit too short: {len(circuit_nodes)}")
    
    # Convert to patrol route format
    patrol_points = []
    for node_id in circuit_nodes:
        node_data = G.nodes[node_id]
        patrol_points.append({
            "x": node_data['x'],
            "y": node_data['y']
        })
    
    # Create route data
    route_data = {
        "route_info": {
            "total_points": len(patrol_points),
            "source": "pixel_based_road_extraction",
            "connection_method": "graph_based_patrol_circuit"
        },
        "points": patrol_points
    }
    
    # Save route
    with open(output_route_path, 'w') as f:
        json.dump(route_data, f, indent=2)
    
    print(f"Saved pixel-based patrol route to: {output_route_path}")
    print(f"Route has {len(patrol_points)} points")
    
    # Calculate coverage statistics
    x_coords = [p['x'] for p in patrol_points]
    y_coords = [p['y'] for p in patrol_points]
    
    print(f"Route coverage:")
    print(f"  X range: {min(x_coords):.3f} to {max(x_coords):.3f}")
    print(f"  Y range: {min(y_coords):.3f} to {max(y_coords):.3f}")
    
    return patrol_points

if __name__ == "__main__":
    road_pixels_file = "data/road_pixels.json"
    output_route_file = "data/pixel_patrol_route.json"
    
    try:
        print("Generating pixel-based patrol route...")
        points = create_patrol_route_from_pixels(road_pixels_file, output_route_file, circuit_length=250)
        
        print("✓ Pixel-based patrol route generated successfully!")
        print(f"  Route file: {output_route_file}")
        print(f"  Total points: {len(points)}")
        
    except Exception as e:
        print(f"Error: {e}")
        import traceback
        traceback.print_exc()