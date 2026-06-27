class PaymentService {
public:
    void charge() {}
    void verify() {}
};

class Checkout {
    PaymentService *payment;
public:
    void placeOrder() {
        payment->charge();
        payment->verify();
    }
};
