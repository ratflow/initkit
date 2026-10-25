#include <cstdio>
#include <vector>

#include "calc.hpp"

int main() {
    std::printf("cpp-sample: up and running\n");

    for (int n = 1; n <= 10; ++n) {
        std::printf("factorial(%d) = %lld\n", n, calc::factorial(n));
    }

    const std::vector<int> primes = calc::primes_up_to(50);
    std::printf("%s\n", calc::format_report(primes).c_str());
    std::printf("primes found: %zu\n", primes.size());

    return 0;
}
