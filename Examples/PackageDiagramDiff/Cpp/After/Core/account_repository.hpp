#pragma once

#include <string>

#include "account.hpp"

// Persistence boundary for `Account`s. The abstraction in the `Core` module.
class AccountRepository {
public:
    virtual ~AccountRepository() = default;

    virtual Account* find(const std::string& id) = 0;
    virtual void save(const Account& account) = 0;
};
