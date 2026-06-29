#ifndef CORE_ACCOUNT_REPOSITORY_H
#define CORE_ACCOUNT_REPOSITORY_H

#include "account.h"

/* Persistence boundary for `Account`s, as a table of function pointers.
   The abstraction in the `Core` module. */
struct AccountRepository {
    struct Account *(*find)(const char *id);
    void (*save)(struct Account *account);
};

#endif /* CORE_ACCOUNT_REPOSITORY_H */
