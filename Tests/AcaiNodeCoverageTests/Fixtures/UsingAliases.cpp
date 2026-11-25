#include <string>
#include <vector>

namespace alias {

using Amount = double;
using Name = std::string;
using Basket = std::vector<Name>;

class Ledger {
public:
    using Entry = Amount;

    Amount total() const {
        return balance;
    }

private:
    Amount balance;
};

}
