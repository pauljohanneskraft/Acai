import 'dart:math';

enum Status {
  idle,
  running,
  done;

  bool get isTerminal => this == Status.done;

  Status next() => Status.values[(index + 1) % Status.values.length];
}

abstract class Shape {
  double area();
  String describe();
  static int created = 0;
  const Shape();
}

class Point {
  final double x, y;
  @override
  int hashCode = 0;
  const Point(this.x, this.y);
}

class Counter {
  int _count = 0;
  int limit;
  static const int defaultLimit = 10;
  late final String label;
  Status status = Status.idle;
  final Point origin = Point(0, 0);
  final Point computed = makePoint();
  List<int> history = [];
  String? note;

  Counter(this.limit) : label = describeLimit(limit) {
    reset();
  }

  Counter.unlimited() : this(-1);

  factory Counter.fromLabel(String label) {
    final counter = Counter(defaultLimit);
    counter.label = label;
    return counter;
  }

  static String describeLimit(int limit) => 'limit $limit';

  static Point makePoint() => Point(1, 1);

  int get count => _count;

  set count(int value) {
    _count = value;
  }

  bool get atLimit => limit >= 0 && _count >= limit;

  void increment() {
    _count++;
    history.add(_count);
    status = Status.running;
    if (atLimit) {
      status = Status.done;
    }
  }

  void decrement() {
    --_count;
    _count -= 1;
    note = 'went down to $_count';
    note = 'constant';
  }

  Future<int> load() async {
    await Future.delayed(Duration.zero);
    return _count;
  }

  void reset() {
    _count = 0;
    status = Status.idle;
    history = [];
    origin.x;
    this.increment();
    Counter.describeLimit(3);
    var other = Counter(1);
    other.increment();
    Counter fixed = Counter.unlimited();
    fixed.reset();
    final derived = makePoint();
    derived.hashCode;
    final built = copy();
    built.reset();
  }

  Counter copy() => Counter(limit);

  @override
  String toString() => 'Counter($_count)';

  @Deprecated('use increment')
  void bump() => increment();

  Counter operator +(Counter other) => Counter(limit + other.limit);

  bool operator ==(Object other) => other is Counter && other._count == _count;

  Counter operator -() => Counter(-limit);

  void _internal() {}

  external void nativeHook();

  void withCallback(void Function(int) callback, {required int times, int repeat = 1, covariant Point? at}) {
    for (var i = 0; i < times; i++) {
      callback(i);
    }
    while (_count < 3) {
      increment();
    }
    do {
      decrement();
    } while (_count > 0);
    switch (status) {
      case Status.idle:
        break;
      case Status.running:
        break;
      default:
        break;
    }
    try {
      load();
    } catch (error) {
      note = error.toString();
    }
    final squares = [for (final value in history) value * value];
    squares.length;
  }
}
