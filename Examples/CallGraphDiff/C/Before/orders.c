/* An order-submission flow: `submit_order` fans out to validation and order placement,
   which in turn charges payment and saves the order — a small branching static call graph.
   The leaf services are forward-declared here (they live in services.c). */

void validate_order(void);
void charge_card(void);
void save_order(void);

void place_order(void) {
    charge_card();
}

void submit_order(void) {
    validate_order();
    place_order();
}
