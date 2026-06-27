#include <string>

class Account {};

class User : public Account {
    std::string name;
};

class AdminUser : public User {};

class PaymentGateway {};

class OrderService {
public:
    void place() {}
};

class LegacyAudit {
public:
    void review() {}
};
