#pragma once

#include <string>

// A currency amount. Part of the `Core` module.
class Money {
public:
    Money(double amount, std::string currency);

    Money adding(const Money& other) const;

private:
    double amount_;
    std::string currency_;
};
