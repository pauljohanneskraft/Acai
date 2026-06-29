#pragma once

#include "../Core/account.hpp"

// Generates account statements. Part of the `Reporting` module; depends on `Core`.
class StatementGenerator {
public:
    Account *account;
};
