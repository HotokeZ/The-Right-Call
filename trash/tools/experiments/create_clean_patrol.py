#!/usr/bin/env python3
"""
Generate patrol routes from clean road line data.
This creates connected paths along actual road geometries only.
"""

import json
import numpy as np
from scipy.spatial.distance import cdist
import networkx as nx
from collections import defaultdict

def create_road_line_graph(road_points, connection_threshold=0.01):
    """
    Create a graph connecting road line points that are actually connected.
    
    Args:
        road_points: List of road line coordinates  
        connection_threshold: Maximum distance to connect points
    """
    
    print(f"Creating road line graph from {len(road_points)} points...")
    
    # Extract coordinates
    coords = np.array([[p['x'], p['y']] for p in road_points])
    
    # Create graph
    G = nx.Graph()
    
    # Add nodes with positions
    for i, point in enumerate(road_points):
        G.add_node(i, x=point['x'], y=point['y'])
    
    print("Connecting road line segments...")
    
    # Calculate all pairwise distances
    distances = cdist(coords, coords)
    
    # Connect points that are very close (likely part of same road segment)
    connections_added = 0
    
    for i in range(len(road_points)):
        # Find nearby points within threshold
        nearby_indices = np.where((distances[i] < connection_threshold) & (distances[i] > 0))[0]
        
        # Sort by distance and take closest ones
        if len(nearby_indices) > 0:
            nearby_distances = distances[i][nearby_indices]
            sorted_indices = nearby_indices[np.argsort(nearby_distances)]
            
            # Connect to closest few points (limit connections per node)
            max_connections = min(4, len(sorted_indices))
            
            for j in sorted_indices[:max_connections]:
                if not G.has_edge(i, j):
                    weight = distances[i][j]
                    G.add_edge(i, j, weight=weight)
                    connections_added += 1
    
    print(f"Added {connections_added} connections")
    print(f"Graph: {G.number_of_nodes()} nodes, {G.number_of_edges()} edges")
    
    return G

def find_main_road_network(G):
    """
    Find the largest connected component (main road network).
    """
    
    components = list(nx.connected_components(G))
    components.sort(key=len, reverse=True)
    
    print(f"Found {len(components)} connected components")
    
    if components:
        main_component = components[0] 
        print(f"Main road network: {len(main_component)} connected points")
        
        # Return subgraph of largest component
        return G.subgraph(main_component).copy()
    
    return G

def generate_road_patrol_circuit(G, target_points=200):
    """
    Generate a patrol circuit that follows the road network comprehensively.
    """
    
    print(f"Generating patrol circuit with ~{target_points} points...")
    
    if G.number_of_nodes() < 10:
        print("Warning: Not enough connected road points")
        return []
    
    # Use a more systematic approach to cover the road network
    all_nodes = list(G.nodes())
    
    # Start from a central node (node with high degree/centrality)
    if G.number_of_nodes() > 1:
        # Find node with highest betweenness centrality (likely on main roads)
        centrality = nx.betweenness_centrality(G, k=min(100, G.number_of_nodes()))
        start_node = max(centrality.items(), key=lambda x: x[1])[0]
    else:
        start_node = all_nodes[0]
    
    print(f"Starting patrol from node {start_node}")
    
    circuit = []
    visited = set()
    current_node = start_node
    
    while len(circuit) < target_points and len(visited) < G.number_of_nodes():
        
        circuit.append(current_node)
        visited.add(current_node)
        
        # Get unvisited neighbors
        neighbors = list(G.neighbors(current_node))
        unvisited_neighbors = [n for n in neighbors if n not in visited]
        
        if unvisited_neighbors:
            # Choose neighbor that leads to largest unvisited area
            next_node = max(unvisited_neighbors, 
                          key=lambda n: len(set(nx.single_source_shortest_path_length(G, n, cutoff=3).keys()) - visited))
        else:
            # No unvisited neighbors - find path to unvisited area
            unvisited = set(G.nodes()) - visited
            if unvisited:
                # Find closest unvisited node
                try:
                    target = min(unvisited, key=lambda n: nx.shortest_path_length(G, current_node, n))
                    path = nx.shortest_path(G, current_node, target)
                    if len(path) > 1:
                        next_node = path[1]  # Next step in path
                    else:
                        next_node = target
                except nx.NetworkXNoPath:
                    # If no path, pick any unvisited node
                    next_node = list(unvisited)[0]
                    circuit.append(next_node)
                    visited.add(next_node)
                    break
            else:
                break
        
        current_node = next_node
    
    # Connect back to start if possible
    if len(circuit) > 1 and current_node != start_node:
        try:
            return_path = nx.shortest_path(G, current_node, start_node)
            if len(return_path) > 1:
                circuit.extend(return_path[1:])  # Add return path (skip current node)
        except nx.NetworkXNoPath:
            pass  # Can't connect back - that's okay
    
    print(f"Generated circuit with {len(circuit)} points")
    
    # Remove duplicates while preserving order
    seen = set()
    unique_circuit = []
    for node in circuit:
        if node not in seen:
            seen.add(node)
            unique_circuit.append(node)
    
    print(f"Final circuit: {len(unique_circuit)} unique points")
    return unique_circuit

def create_clean_patrol_from_roads(road_points_file, output_file, target_points=200):
    """
    Create patrol route from clean road line data.
    """
    
    # Load clean road data
    with open(road_points_file, 'r') as f:
        data = json.load(f)
    
    road_points = data['road_points']
    
    if len(road_points) < 10:
        raise ValueError(f"Not enough road points: {len(road_points)}")
    
    print(f"Loaded {len(road_points)} clean road line points")
    
    # Create road line graph
    G = create_road_line_graph(road_points, connection_threshold=0.008)
    
    # Find main road network
    G = find_main_road_network(G)
    
    if G.number_of_nodes() < 10:
        raise ValueError(f"Main road network too small: {G.number_of_nodes()} nodes")
    
    # Generate patrol circuit
    circuit_nodes = generate_road_patrol_circuit(G, target_points)
    
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
            "source": "clean_road_lines_osm",
            "method": "road_network_traversal"
        },
        "points": patrol_points
    }
    
    # Save route
    with open(output_file, 'w') as f:
        json.dump(route_data, f, indent=2)
    
    print(f"Saved clean road patrol route: {output_file}")
    
    # Calculate coverage
    if patrol_points:
        x_coords = [p['x'] for p in patrol_points]
        y_coords = [p['y'] for p in patrol_points]
        
        print(f"Route coverage:")
        print(f"  X range: {min(x_coords):.3f} to {max(x_coords):.3f}")
        print(f"  Y range: {min(y_coords):.3f} to {max(y_coords):.3f}")
    
    return patrol_points

if __name__ == "__main__":
    road_points_file = "data/clean_road_points.json"
    output_file = "data/clean_patrol_route.json"
    
    try:
        print("Generating patrol route from clean road lines...")
        points = create_clean_patrol_from_roads(road_points_file, output_file, target_points=250)
        
        print("✓ Clean road patrol route generated!")
        print(f"  Route file: {output_file}")
        print(f"  Total points: {len(points)}")
        
    except Exception as e:
        print(f"Error: {e}")
        import traceback
        traceback.print_exc()