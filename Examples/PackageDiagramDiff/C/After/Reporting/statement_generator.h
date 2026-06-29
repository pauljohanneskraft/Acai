#ifndef REPORTING_STATEMENT_GENERATOR_H
#define REPORTING_STATEMENT_GENERATOR_H

#include "../Core/account.h"

/* Generates account statements. Part of the `Reporting` module; depends on `Core`. */
struct StatementGenerator {
    struct Account *account;
};

#endif /* REPORTING_STATEMENT_GENERATOR_H */
