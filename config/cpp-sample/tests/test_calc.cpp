#include "calc.hpp"

#include <gtest/gtest.h>

TEST(Calc, Add) { EXPECT_EQ(calc::add(2, 3), 5); }

TEST(Calc, Multiply) { EXPECT_EQ(calc::multiply(6, 7), 42); }

TEST(Calc, Factorial) {
    EXPECT_EQ(calc::factorial(0), 1);
    EXPECT_EQ(calc::factorial(1), 1);
    EXPECT_EQ(calc::factorial(10), 3628800LL);
}

TEST(Calc, IsPrime) {
    EXPECT_FALSE(calc::is_prime(0));
    EXPECT_FALSE(calc::is_prime(1));
    EXPECT_TRUE(calc::is_prime(2));
    EXPECT_TRUE(calc::is_prime(97));
    EXPECT_FALSE(calc::is_prime(100));
}

TEST(Calc, PrimesUpTo) {
    const std::vector<int> expected = {2, 3, 5, 7};
    EXPECT_EQ(calc::primes_up_to(10), expected);
}
