#pragma once

#include <string>

class Order {
public:
    explicit Order(std::string id) : id_(std::move(id)) {}

private:
    std::string id_;
};
