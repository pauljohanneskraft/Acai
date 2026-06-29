#pragma once

#include "OrderRepository.hpp"
#include "PaymentService.hpp"

// Places an order by charging payment and persisting it.
class OrderService {
public:
    OrderService(PaymentService* payment, OrderRepository* repository)
        : payment_(payment), repository_(repository) {}

    void place(const Order& order) {
        payment_->charge(order);
    }

private:
    PaymentService* payment_;
    OrderRepository* repository_;
};
