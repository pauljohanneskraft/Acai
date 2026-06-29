#ifndef CORE_MONEY_H
#define CORE_MONEY_H

/* A currency amount. Part of the `Core` module. */
struct Money {
    double amount;
    const char *currency;
};

struct Money money_adding(struct Money self, struct Money other);

#endif /* CORE_MONEY_H */
