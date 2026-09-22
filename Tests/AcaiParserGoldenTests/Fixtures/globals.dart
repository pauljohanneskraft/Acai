library inventory;

import 'dart:async';
part 'inventory_helpers.dart';

const int maxItems = 100;
final String storeName = 'Main';
late String region;
var counter = 0;
double ratio = 0.5, threshold = 1.5;
List<String>? tags;
Map<String, int> stock = {};
final Registry registry = Registry();
final Registry alias = makeRegistry();

class Registry {
  int size = 0;
}

Registry makeRegistry() => Registry();

Future<void> refresh() async {
  region = 'eu';
  counter++;
  counter += 2;
  registry.size = 1;
}

Stream<int> ticks() async* {
  yield counter;
}

Iterable<int> range() sync* {
  yield 1;
}

int _hidden(int value) => value * 2;

void bootstrap() {
  refresh();
  makeRegistry();
  final local = Registry();
  local.size = 3;
}
