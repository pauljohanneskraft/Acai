struct PaymentGateway {
    int id;
};

struct Account {
    int balance;
};

struct OrderService {
    struct Account *account;
};

struct LegacyAudit {
    int code;
};
