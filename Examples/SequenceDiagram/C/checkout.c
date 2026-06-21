/* A checkout flow expressed as C free functions (C has no methods): placing an order drives the
   whole payment sequence — `place_order` -> `charge` -> `authorize`. Everything lives in one
   translation unit because the parser resolves unqualified calls within a file (a file-wide
   pre-pass) and does not follow `#include`, so no forward declarations are needed. The entry point
   is the free function `place_order`; each function renders as its own lifeline. */

void authorize(void) {
    /* Contacts the bank and approves the charge. */
}

void charge(void) {
    authorize();
}

void place_order(void) {
    charge();
}
