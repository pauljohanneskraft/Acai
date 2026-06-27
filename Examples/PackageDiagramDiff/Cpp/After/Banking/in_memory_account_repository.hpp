#pragma once

#include <string>
#include <unordered_map>

#include "../Core/account.hpp"
#include "../Core/account_repository.hpp"

// An in-memory `AccountRepository`. Part of the `Banking` module; depends on `Core`.
class InMemoryAccountRepository : public AccountRepository {
public:
    Account* find(const std::string& id) override;
    void save(const Account& account) override;

private:
    std::unordered_map<std::string, Account> storage_;
};
