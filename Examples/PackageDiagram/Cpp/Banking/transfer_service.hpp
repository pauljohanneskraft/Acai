#pragma once

#include <string>

#include "../Core/account_repository.hpp"
#include "../Core/money.hpp"

// Moves money between accounts. Part of the `Banking` module; depends on `Core`.
class TransferService {
public:
    explicit TransferService(AccountRepository* repository);

    void transfer(const Money& amount, const std::string& source, const std::string& destination);

private:
    AccountRepository* repository_;
};
