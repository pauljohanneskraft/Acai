library geometry;

abstract class Entity {
  String get id;
}

mixin Timestamped on Entity {
  DateTime? updatedAt;

  void touch() {
    updatedAt = DateTime.now();
  }
}

mixin Named implements Entity {
  String get name => id;
}

mixin Serializable {
  Map<String, Object?> toJson() => {};
}

class Vector<T extends num> {
  final List<T> values;
  const Vector(this.values);

  Vector<T> scaled(T factor) => Vector(values);
}

class Matrix<T extends num, U> extends Vector<T> with Serializable implements Comparable<Matrix<T, U>> {
  final int rows;
  final Map<String, List<T>>? cache;

  Matrix(List<T> values, this.rows, {this.cache}) : super(values);

  @override
  int compareTo(Matrix<T, U> other) => rows.compareTo(other.rows);
}

sealed class Result {}

final class Success extends Result {
  final String value;
  Success(this.value);
}

final class Failure extends Result implements Exception {
  final Object error;
  Failure(this.error);
}

abstract class Store extends Entity with Timestamped, Named {
  @override
  String get id => 'store';

  Result load();
}

enum Priority with Serializable implements Comparable<Priority> {
  low(1),
  high(2);

  final int weight;
  const Priority(this.weight);

  @override
  int compareTo(Priority other) => weight - other.weight;
}

extension VectorMath<T extends num> on Vector<T> {
  T get first => values.first;

  Vector<T> doubled() => scaled(first);
}

extension on String {
  String get shouted => toUpperCase();
}

extension type Meters(double value) implements Comparable<Meters> {
  Meters operator +(Meters other) => Meters(value + other.value);

  @override
  int compareTo(Meters other) => value.compareTo(other.value);
}

typedef Callback = void Function(Result result);

class Handler {
  Callback? onResult;
  void Function()? onDone;
  final Store store;
  Handler(this.store);

  void run() {
    final result = store.load();
    onResult?.call(result);
    store.touch();
    Vector<int>(const [1]).scaled(2);
  }
}
