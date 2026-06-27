class PaymentService {
public:
    void charge() {}
    void verify() {}
};

class AuditService {
public:
    void log() {}
};

class Checkout {
    PaymentService *payment;
    AuditService *audit;
public:
    void placeOrder() {
        payment->charge();
        audit->log();
    }
};
