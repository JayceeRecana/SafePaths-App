import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Graph Topology Engine', () {
    // Isolated version of graph analysis logic
    Map<String, dynamic> analyzeGraph(Map<String, List<String>> adjList) {
      int totalNodes = adjList.length;
      int orphanCount = 0;
      int symmetryViolations = 0;
      List<String> disconnectedNodes = [];

      for (var entry in adjList.entries) {
        String nodeId = entry.key;
        List<String> neighbors = entry.value;

        if (neighbors.isEmpty) {
          orphanCount++;
          disconnectedNodes.add(nodeId);
        }

        for (var neighborId in neighbors) {
          if (!adjList.containsKey(neighborId) || !adjList[neighborId]!.contains(nodeId)) {
            symmetryViolations++;
          }
        }
      }

      // Graph Component Traversal
      Set<String> visited = {};
      int connectedComponents = 0;
      
      void dfs(String node) {
        visited.add(node);
        for (var n in adjList[node]!) {
          if (!visited.contains(n) && adjList.containsKey(n)) {
            dfs(n);
          }
        }
      }

      for (var node in adjList.keys) {
        if (!visited.contains(node)) {
          connectedComponents++;
          dfs(node);
        }
      }

      return {
        'totalNodes': totalNodes,
        'orphanCount': orphanCount,
        'symmetryViolations': symmetryViolations,
        'disconnectedNodes': disconnectedNodes,
        'connectedComponents': connectedComponents,
      };
    }

    test('Identifies symmetric vs asymmetric edges', () {
      Map<String, List<String>> graph = {
        'A': ['B'],
        'B': ['A', 'C'],
        'C': ['B'],
      };
      
      var result = analyzeGraph(graph);
      expect(result['symmetryViolations'], 0); // Completely symmetric

      graph['B']!.remove('A'); // Break symmetry
      result = analyzeGraph(graph);
      expect(result['symmetryViolations'], 1); // 'A' points to 'B', but 'B' doesn't point back
    });

    test('Identifies orphan and disconnected components', () {
      Map<String, List<String>> graph = {
        'A': ['B'],
        'B': ['A'],
        'C': ['D'],
        'D': ['C'],
        'E': [], // Orphan
      };

      var result = analyzeGraph(graph);
      expect(result['orphanCount'], 1);
      expect(result['disconnectedNodes'].contains('E'), true);
      expect(result['connectedComponents'], 3); // {A,B}, {C,D}, {E}
    });
  });
}
