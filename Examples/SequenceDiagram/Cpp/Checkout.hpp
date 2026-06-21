#pragma once

#include "PaymentService.hpp"

// Entry point: placing an order drives the whole payment sequence.
class Checkout {
public:
    explicit Checkout(PaymentService* payment) : payment_(payment) {}

    void placeOrder() {
        payment_->charge();
    }

private:
    PaymentService* payment_;
};
