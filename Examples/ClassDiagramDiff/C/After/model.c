struct PaymentGateway {
    int id;
};

struct Account {
    int balance;
};

struct OrderService {
    struct PaymentGateway *gateway;
};

struct Receipt {
    int total;
};
