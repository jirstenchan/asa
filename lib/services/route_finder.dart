import '../models/mall_map.dart';

List<MapNode>? findRoute({
  required List<MapNode> nodes,
  required List<MapConnection> connections,
  required String from,
  required String to,
}) {
  final nodesById = {for (final node in nodes) node.id: node};
  if (!nodesById.containsKey(from) || !nodesById.containsKey(to)) return null;
  if (from == to) return [nodesById[from]!];

  final neighbors = <String, List<String>>{
    for (final id in nodesById.keys) id: <String>[],
  };
  for (final edge in connections) {
    if (!nodesById.containsKey(edge.from) || !nodesById.containsKey(edge.to)) {
      continue;
    }
    neighbors[edge.from]!.add(edge.to);
    neighbors[edge.to]!.add(edge.from);
  }

  final queue = <String>[from];
  final previous = <String, String?>{from: null};
  for (var index = 0; index < queue.length; index++) {
    final current = queue[index];
    for (final neighbor in neighbors[current]!) {
      if (previous.containsKey(neighbor)) continue;
      previous[neighbor] = current;
      if (neighbor == to) {
        final routeIds = <String>[to];
        var step = to;
        while (step != from) {
          step = previous[step]!;
          routeIds.add(step);
        }
        return routeIds.reversed.map((id) => nodesById[id]!).toList();
      }
      queue.add(neighbor);
    }
  }
  return null;
}
