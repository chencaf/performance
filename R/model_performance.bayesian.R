#' Performance of Bayesian Models
#'
#' Compute indices of model performance for (general) linear models.
#'
#' @param model Object of class \code{stanreg} or \code{brmsfit}.
#' @param metrics Can be \code{"all"}, \code{"common"} or a character vector of metrics to be computed (some of \code{c("LOOIC", "WAIC", "R2", "R2_adj", "RMSE", "SIGMA", "LOGLOSS", "SCORE")}). \code{"common"} will compute LOOIC, WAIC, R2 and RMSE.
#' @param ... Arguments passed to or from other methods.
#' @inheritParams model_performance.lm
#'
#' @return A data frame (with one row) and one column per "index" (see \code{metrics}).
#'
#' @details Depending on \code{model}, following indices are computed:
#' \itemize{
#'   \item{\strong{ELPD}} {expected log predictive density, see \code{\link{looic}}}
#'   \item{\strong{LOOIC}} {leave-one-out cross-validation (LOO) information criterion, see \code{\link{looic}}}
#'   \item{\strong{WAIC}} {widely applicable information criterion, see \code{?loo::waic}}
#'   \item{\strong{R2}} {r-squared value, see \code{\link{r2}}}
#'   \item{\strong{R2_LOO_adjusted}} {adjusted r-squared, see \code{\link{r2}}}
#'   \item{\strong{RMSE}} {root mean squared error, see \code{\link{performance_rmse}}}
#'   \item{\strong{SIGMA}} {residual standard deviation, see \code{\link[insight:get_sigma]{get_sigma()}}}
#'   \item{\strong{LOGLOSS}} {Log-loss, see \code{\link{performance_logloss}}}
#'   \item{\strong{SCORE_LOG}} {score of logarithmic proper scoring rule, see \code{\link{performance_score}}}
#'   \item{\strong{SCORE_SPHERICAL}} {score of spherical proper scoring rule, see \code{\link{performance_score}}}
#'   \item{\strong{PCP}} {percentage of correct predictions, see \code{\link{performance_pcp}}}
#' }
#'
#' @examples
#' \dontrun{
#' if (require("rstanarm") && require("rstantools")) {
#'   model <- stan_glm(mpg ~ wt + cyl, data = mtcars, chains = 1, iter = 500, refresh = 0)
#'   model_performance(model)
#'
#'   model <- stan_glmer(
#'     mpg ~ wt + cyl + (1 | gear),
#'     data = mtcars,
#'     chains = 1,
#'     iter = 500,
#'     refresh = 0
#'   )
#'   model_performance(model)
#' }
#'
#' if (require("BayesFactor") && require("rstantools")) {
#'   model <- generalTestBF(carb ~ am + mpg, mtcars)
#'
#'   model_performance(model)
#'   model_performance(model[3])
#'
#'   model_performance(model, average = TRUE)
#' }
#' }
#' @seealso \link{r2_bayes}
#' @references Gelman, A., Goodrich, B., Gabry, J., & Vehtari, A. (2018). R-squared for Bayesian regression models. The American Statistician, The American Statistician, 1-6.
#'
#' @importFrom insight find_algorithm is_multivariate model_info
#' @importFrom bayestestR map_estimate hdi
#' @importFrom stats AIC BIC mad median sd setNames
#' @export
model_performance.stanreg <- function(model, metrics = "all", verbose = TRUE, ...) {
  if (any(tolower(metrics) == "log_loss")) {
    metrics[tolower(metrics) == "log_loss"] <- "LOGLOSS"
  }

  if (all(metrics == "all")) {
    metrics <- c("LOOIC", "WAIC", "R2", "R2_adjusted", "RMSE", "SIGMA", "LOGLOSS", "SCORE")
  } else if (all(metrics == "common")) {
    metrics <- c("LOOIC", "WAIC", "R2", "R2_adjusted", "RMSE")
  }

  metrics <- toupper(metrics)

  algorithm <- insight::find_algorithm(model)
  if (algorithm$algorithm != "sampling") {
    if (verbose) warning("`model_performance()` only possible for models fit using the 'sampling' algorithm.", call. = FALSE)
    return(NULL)
  }

  if (!requireNamespace("loo", quietly = TRUE)) {
    stop("Package `loo` required for this function to work. Please install it.")
  }

  mi <- insight::model_info(model)

  out <- list()
  attri <- list()

  if (insight::is_multivariate(model)) {
    out$Response <- insight::find_response(model, combine = FALSE)
    mi <- mi[[1]]
  }

  # LOOIC ------------------
  if ("LOOIC" %in% metrics) {
    out <- append(out, suppressWarnings(looic(model, verbose = verbose)))
  }

  # WAIC ------------------
  if ("WAIC" %in% metrics) {
    out$WAIC <- suppressWarnings(loo::waic(model)$estimates["waic", "Estimate"])
  }

  # R2 ------------------
  if ("R2" %in% metrics) {
    r2 <- r2_bayes(model, verbose = verbose)
    if (!is.null(r2)) {
      attri$r2_bayes <- attributes(r2) # save attributes

      # Format to df then to list
      r2_df <- as.data.frame(t(as.numeric(r2)))
      names(r2_df) <- gsub("_Bayes", "", names(r2), fixed = TRUE)
      out <- append(out, as.list(r2_df))
    }
  }

  # LOO-R2 ------------------
  if ("R2_ADJUSTED" %in% metrics && mi$is_linear) {
    out$R2_adjusted <- tryCatch({
      suppressWarnings(r2_loo(model, verbose = verbose))
    },
    error = function(e) {
      NULL
    })
  }

  # RMSE ------------------
  if ("RMSE" %in% metrics && !mi$is_ordinal && !mi$is_multinomial && !mi$is_categorical) {
    out$RMSE <- performance_rmse(model, verbose = verbose)
  }

  # SIGMA ------------------
  if ("SIGMA" %in% metrics) {
    out$Sigma <- tryCatch({
      .get_sigma(model)
    },
    error = function(e) {
      NULL
    })
  }

  # LOGLOSS ------------------
  if (("LOGLOSS" %in% metrics) && mi$is_binomial) {
    out$Log_loss <- tryCatch({
      .logloss <- performance_logloss(model, verbose = verbose)
      if (!is.na(.logloss)) {
        .logloss
      } else {
        NULL
      }
    },
    error = function(e) {
      NULL
    })
  }

  # SCORE ------------------
  if (("SCORE" %in% metrics) && (mi$is_binomial || mi$is_count)) {
    .scoring_rules <- tryCatch({
      performance_score(model, verbose = verbose)
    },
    error = function(e) {
      NULL
    })
    if (!is.null(.scoring_rules)) {
      if (!is.na(.scoring_rules$logarithmic)) out$Score_log <- .scoring_rules$logarithmic
      if (!is.na(.scoring_rules$spherical)) out$Score_spherical <- .scoring_rules$spherical
    }
  }

  out <- as.data.frame(out)
  row.names(out) <- NULL
  out <- out[sapply(out, function(i) !all(is.na(i)))]

  attributes(out) <- c(attributes(out), attri)
  class(out) <- c("performance_model", class(out))

  out
}


#' @export
model_performance.brmsfit <- model_performance.stanreg

#' @export
model_performance.stanmvreg <- model_performance.stanreg


#' @export
#' @inheritParams r2_bayes
#' @importFrom insight model_info
#' @importFrom bayestestR point_estimate
#' @rdname model_performance.stanreg
model_performance.BFBayesFactor <- function(model, metrics = "all", verbose = TRUE,
                                            average = FALSE, prior_odds = NULL, ...) {
  if (all(metrics == "all")) {
    metrics <- c("R2", "SIGMA")
  }

  mi <- insight::model_info(model)
  if (!mi$is_linear || mi$is_correlation || mi$is_ttest || mi$is_binomial || mi$is_meta) {
    warning("Can produce ", paste0(metrics, collapse = " & "), " only for linear models.", call. = FALSE)
    return(NULL)
  }

  out <- list()
  attri <- list()

  if ("R2" %in% c(metrics)) {
    r2 <- r2_bayes(model, average = average, prior_odds = prior_odds)
    attri$r2_bayes <- attributes(r2) # save attributes

    # Format to df then to list
    r2_df <- as.data.frame(t(as.numeric(r2)))
    names(r2_df) <- gsub("_Bayes", "", names(r2), fixed = TRUE)
    out <- append(out, as.list(r2_df))
  }


  if ("SIGMA" %in% toupper(metrics)) {
    sig <- suppressMessages(.get_sigma_bfbayesfactor(model, average = average, prior_odds = prior_odds))
    out$Sigma <- bayestestR::point_estimate(sig, "median")[[1]]
  }


  out <- as.data.frame(out)
  row.names(out) <- NULL

  attributes(out) <- c(attributes(out), attri)
  class(out) <- c("performance_model", class(out))

  out
}






# helper -------------------


#' @importFrom insight get_parameters
.get_sigma_bfbayesfactor <- function(model, average = FALSE, prior_odds = NULL) {
  if (average) {
    return(.get_sigma_bfbayesfactor_model_average(model, prior_odds = prior_odds))
  }

  params <- insight::get_parameters(model)
  if (!"sig2" %in% colnames(params)) stop("This is not a linear model.")
  sqrt(params$sig2)
}


#' @importFrom bayestestR bayesfactor_models weighted_posteriors
#' @importFrom insight get_response
#' @importFrom stats sd
.get_sigma_bfbayesfactor_model_average <- function(model, prior_odds = NULL) {
  if (!requireNamespace("BayesFactor", quietly = TRUE)) {
    stop("Package `BayesFactor` needed for this function to work. Please install it.")
  }

  BFMods <- bayestestR::bayesfactor_models(model, verbose = FALSE)

  # extract parameters
  intercept_only <- which(BFMods$Model == "1")
  params <- vector(mode = "list", length = nrow(BFMods))
  for (m in seq_along(params)) {
    if (length(intercept_only) && m == intercept_only) {
      y <- insight::get_response(model)
      params[[m]] <- rep(stats::sd(y), 4000)
    } else if (m == 1) {
      # If the model is the "den" model
      params[[m]] <- suppressMessages(.get_sigma_bfbayesfactor(1 / model[1]))
    } else {
      params[[m]] <- suppressMessages(.get_sigma_bfbayesfactor(model[m - 1]))
    }
  }

  params <- lapply(params, data.frame)


  # Compute posterior model probabilities
  if (!is.null(prior_odds)) {
    prior_odds <- c(1, prior_odds)
  } else {
    prior_odds <- rep(1, nrow(BFMods))
  }
  posterior_odds <- prior_odds * BFMods$BF
  posterior_odds <- posterior_odds[-1] / posterior_odds[1]

  do.call(bayestestR::weighted_posteriors,
          c(params, list(missing = 0, prior_odds = posterior_odds)))[[1]]
}
