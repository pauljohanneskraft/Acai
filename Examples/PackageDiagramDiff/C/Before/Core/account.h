#ifndef CORE_ACCOUNT_H
#define CORE_ACCOUNT_H

#include "money.h"

/* A bank account holding a balance. Part of the `Core` module. */
struct Account {
    const char *id;
    struct Money balance;
};

void account_deposit(struct Account *account, struct Money amount);

#endif /* CORE_ACCOUNT_H */
