package com.example.shop;

import java.util.ArrayList;
import java.util.List;

interface Priced {
    double price();
}

enum Category {
    FOOD,
    TOOL;

    public String label() {
        return name().toLowerCase();
    }
}

record Money(double amount, String currency) {
}

abstract class Item implements Priced {

    protected final String name;

    Item(String name) {
        this.name = name;
    }

    public abstract double price();

    public String describe() {
        return this.name;
    }
}

public class Product extends Item {

    private final Logger audit = new Logger();
    private double base;
    public double discount;
    private final List<String> tags = new ArrayList<>();

    public static class Builder {
        private String name = "";

        public Product build() {
            return new Product(this.name, 0.0);
        }
    }

    public Product(String name, double base) {
        super(name);
        this.base = base;
    }

    @Override
    public double price() {
        this.audit.log("pricing");
        return this.base - this.discount;
    }

    @Override
    public String describe() {
        Logger local = new Logger();
        local.log(this.name);
        return this.name;
    }

    public Category classify(int value) {
        if (value > 10) {
            return Category.TOOL;
        } else if (value > 5) {
            return Category.FOOD;
        }
        for (int index = 0; index < value; index++) {
            this.discount += index;
        }
        return Category.FOOD;
    }

    public <T> T identity(T value) {
        return value;
    }
}

class Logger {
    void log(String message) {
    }
}
