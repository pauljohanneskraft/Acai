#pragma once

#include "PaymentGateway.hpp"

// Charges an order by delegating to the payment gateway.
class PaymentService {
public:
    explicit PaymentService(PaymentGateway* gateway) : gateway_(gateway) {}

    void charge() {
        gateway_->authorize();
    }

private:
    PaymentGateway* gateway_;
};
