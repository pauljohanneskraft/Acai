class Base {
  int rank() => 0;
}

class Sub extends Base {
  @override
  int rank() => 1;
}
