public class Base {
    public int rank() { return 0; }
}

public class Sub extends Base {
    @Override
    public int rank() { return 1; }
}
