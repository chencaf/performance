if (require("testthat") && require("performance")) {
  data(iris)
  lm1 <- lm(Sepal.Length ~ Species, data = iris)
  lm2 <- lm(Sepal.Length ~ Species + Petal.Length, data = iris)
  lm3 <- lm(Sepal.Length ~ Species * Petal.Length, data = iris)
  lm4 <- lm(Sepal.Length ~ Species * Petal.Length, data = iris[-1, ])

  test_that("compare_performance", {
    testthat::expect_equal(
      colnames(compare_performance(lm1, lm2, lm3)),
      c("Name", "Model", "AIC", "BIC", "R2", "R2_adjusted", "RMSE", "Sigma")
    )

    testthat::expect_warning(
      testthat::expect_equal(
        colnames(compare_performance(lm1, lm2, lm3, lm4)),
        c("Name", "Model", "AIC", "BIC", "R2", "R2_adjusted", "RMSE", "Sigma")
      )
    )
    testthat::expect_equal(
      colnames(compare_performance(lm1, lm2, lm3, lm4, verbose = FALSE)),
      c("Name", "Model", "AIC", "BIC", "R2", "R2_adjusted", "RMSE", "Sigma")
    )
  })
}
