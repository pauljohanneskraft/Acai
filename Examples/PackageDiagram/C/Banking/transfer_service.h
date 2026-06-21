#ifndef BANKING_TRANSFER_SERVICE_H
#define BANKING_TRANSFER_SERVICE_H

#include "../Core/account_repository.h"
#include "../Core/money.h"

/* Moves money between accounts. Part of the `Banking` module; depends on `Core`. */
struct TransferService {
    struct AccountRepository *repository;
};

void transfer_service_transfer(struct TransferService *service, struct Money amount,
                               const char *source, const char *destination);

#endif /* BANKING_TRANSFER_SERVICE_H */
