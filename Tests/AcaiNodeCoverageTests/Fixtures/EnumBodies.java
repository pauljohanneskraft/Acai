package shop;

/// Each constant overrides the enum's abstract member in its own body — syntax #610 drops.
enum Shipping {
    STANDARD {
        @Override
        public int days() {
            return 5;
        }

        @Override
        public String label() {
            return "Standard";
        }
    },
    EXPRESS {
        @Override
        public int days() {
            return 1;
        }

        @Override
        public String label() {
            return "Express";
        }
    };

    public abstract int days();

    public abstract String label();
}
