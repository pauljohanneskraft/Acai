#ifndef BANKING_IN_MEMORY_ACCOUNT_REPOSITORY_H
#define BANKING_IN_MEMORY_ACCOUNT_REPOSITORY_H

#include "../Core/account.h"

/* A fixed-capacity in-memory account store. Part of the `Banking` module; depends on `Core`. */
struct InMemoryAccountRepository {
    struct Account *entries;
    int count;
};

struct Account *in_memory_account_repository_find(struct InMemoryAccountRepository *self,
                                                  const char *id);

#endif /* BANKING_IN_MEMORY_ACCOUNT_REPOSITORY_H */
