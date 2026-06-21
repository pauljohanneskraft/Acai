#pragma once

// The leaf of the call chain: talks to the bank.
class PaymentGateway {
public:
    void authorize() {
        // Contacts the bank and approves the charge.
    }
};
