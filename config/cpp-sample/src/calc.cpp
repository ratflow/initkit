#include "calc.hpp"

namespace calc {

int add(int a, int b) { return a + b; }

int multiply(int a, int b) { return a * b; }

long long factorial(int n) {
    long long result = 1;
    for (int i = 2; i <= n; ++i) {
        result *= i;  // put a breakpoint here (<leader>db) and step through
    }
    return result;
}

bool is_prime(int n) {
    if (n < 2) return false;
    for (int d = 2; d * d <= n; ++d) {
        if (n % d == 0) return false;
    }
    return true;
}

std::vector<int> primes_up_to(int limit) {
    std::vector<int> primes;
    for (int n = 2; n <= limit; ++n) {
        if (is_prime(n)) primes.push_back(n);
    }
    return primes;
}

std::string format_report(const std::vector<int>& numbers) {
    std::string out = "numbers:";
    for (int n : numbers) {
        out += " " + std::to_string(n);
    }
    return out;
}

}  // namespace calc
