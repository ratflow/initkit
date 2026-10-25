#pragma once

#include <string>
#include <vector>

namespace calc {

// A tiny demo library: enough surface for clangd navigation (gd, gr, gy, K,
// <leader>ch switch source/header) and enough logic to make a debugger
// session interesting.
int add(int a, int b);
int multiply(int a, int b);
long long factorial(int n);
bool is_prime(int n);
std::vector<int> primes_up_to(int limit);
std::string format_report(const std::vector<int>& numbers);

}  // namespace calc
