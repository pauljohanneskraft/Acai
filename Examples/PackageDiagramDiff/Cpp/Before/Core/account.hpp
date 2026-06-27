#pragma once

#include <string>

#include "money.hpp"

// A bank account holding a balance. Part of the `Core` module.
class Account {
public:
    Account(std::string id, Money balance);

    void deposit(const Money& amount);

private:
    std::string id_;
    Money balance_;
};
