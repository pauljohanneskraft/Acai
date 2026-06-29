#include <string>

class Account {};

class User {
    std::string name;
    std::string email;
};

class AdminUser : public User {};

class PaymentGateway {};

class OrderService {
public:
    PaymentGateway *gateway;
    void place() {}
};

class Receipt {
public:
    int total;
};
