#pragma once

#include "OrderService.hpp"
#include "Validator.hpp"

// Entry point: fans out to validation and order placement.
class OrderController {
public:
    OrderController(OrderService* service, Validator* validator)
        : service_(service), validator_(validator) {}

    void submit(const Order& order) {
        validator_->validate(order);
        service_->place(order);
    }

private:
    OrderService* service_;
    Validator* validator_;
};
