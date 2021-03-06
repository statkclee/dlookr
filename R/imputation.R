#' Imputate Missing values
#'
#' @description
#' Missing values are imputated with some representative values and
#' statistical methods.
#'
#' @details
#' imputate_na () creates an imputation class.
#' The `imputation` class includes missing value position, imputated value,
#' and method of missing value imputation, etc.
#' The `imputation` class compares the imputated value with the original value
#' to help determine whether the imputated value is used in the analysis.
#'
#' See vignette("transformation") for an introduction to these concepts.
#'
#' @param .data a data.frame or a \code{\link{tbl_df}}.
#' @param xvar variable name to replace missing value.
#' @param yvar target variable.
#' @param method method of missing values imputation.
#' @param seed integer. the random seed used in mice. only used "mice" method.
#' @param print_flag logical. If TRUE, mice will print history on console.
#' Use print_flag=FALSE for silent computation. Used only when method is "mice".
#' @return An object of imputation class.
#' Attributes of imputation class is as follows.
#' \itemize{
#' \item var_type : the data type of predictor to replace missing value.
#' \item method : method of missing value imputation.
#' \itemize{
#'   \item predictor is numerical variable
#'   \itemize{
#'     \item "mean" : arithmetic mean
#'     \item "median" : median
#'     \item "mode" : mode
#'     \item "knn" : K-nearest neighbors
#'     \item "rpart" : Recursive Partitioning and Regression Trees
#'     \item "mice" : Multivariate Imputation by Chained Equations
#'   }
#'   \item predictor is categorical variable
#'   \itemize{
#'     \item "mode" : mode
#'     \item "rpart" : Recursive Partitioning and Regression Trees
#'     \item "mice" : Multivariate Imputation by Chained Equations
#'   }
#' }
#' \item na_pos : position of missing value in predictor.
#' \item seed : the random seed used in mice. only used "mice" method.
#' \item type : "missing values". type of imputation.
#' }
#' @seealso \code{\link{imputate_outlier}}.
#' @examples
#' \donttest{
#' # Generate data for the example
#' carseats <- ISLR::Carseats
#' carseats[sample(seq(NROW(carseats)), 20), "Income"] <- NA
#' carseats[sample(seq(NROW(carseats)), 5), "Urban"] <- NA
#'
#' # Replace the missing value of the Income variable with median
#' imputate_na(carseats, Income, method = "median")
#'
#' # Replace the missing value of the Income variable with rpart
#' # The target variable is US.
#' imputate_na(carseats, Income, US, method = "rpart")
#'
#' # Replace the missing value of the Urban variable with median
#' imputate_na(carseats, Urban, method = "mode")
#'
#' # Replace the missing value of the Urban variable with mice
#' # The target variable is US.
#' imputate_na(carseats, Urban, US, method = "mice")
#'
#' ## using dplyr -------------------------------------
#' library(dplyr)
#'
#' # The mean before and after the imputation of the Income variable
#' carseats %>%
#'   mutate(Income_imp = imputate_na(carseats, Income, US, method = "knn")) %>%
#'   group_by(US) %>%
#'   summarise(orig = mean(Income, na.rm = TRUE),
#'     imputation = mean(Income_imp))
#'
#' # If the variable of interest is a numarical variable
#' income <- imputate_na(carseats, Income, US, method = "rpart")
#' income
#' summary(income)
#' plot(income)
#'
#' # If the variable of interest is a categorical variable
#' urban <- imputate_na(carseats, Urban, US, method = "mice")
#' urban
#' summary(urban)
#' plot(urban)
#' }
#' @export
#'
imputate_na <- function(.data, xvar, yvar, method, seed, print_flag) {
  UseMethod("imputate_na")
}

#' @method imputate_na data.frame
#' @importFrom tidyselect vars_select
#' @importFrom rlang enquo
#' @import mice
#' @export
imputate_na.data.frame <- function(.data, xvar, yvar = NULL,
  method = c("mean", "median", "mode", "rpart", "knn", "mice"), seed = NULL,
  print_flag = TRUE) {
  tryCatch(vars <- tidyselect::vars_select(names(.data), !!! rlang::enquo(xvar)),
    error = function(e) {
      pram <- as.character(substitute(xvar))
      stop(sprintf("Column %s is unknown", pram))
    }, finally = NULL)

  tryCatch(target <- tidyselect::vars_select(names(.data), !!! rlang::enquo(yvar)),
    error = function(e) {
      pram <- as.character(substitute(yvar))
      stop(sprintf("Column %s is unknown", pram))
    }, finally = NULL)

  method <- match.arg(method)

  imputate_na_impl(.data, vars, target, method, seed, print_flag)
}


#' @import tibble
#' @import dplyr
#' @import mice
#' @importFrom DMwR knnImputation
#' @importFrom rpart rpart
#' @importFrom stats predict
#' @importFrom methods is
imputate_na_impl <- function(df, xvar, yvar, method, seed = NULL, print_flag = TRUE) {
  type <- ""

  if (is(pull(df, xvar))[1] %in% c("integer", "numeric")) {
    type <- "numerical"
  } else if (is(pull(df, xvar))[1] %in% c("factor", "ordered")) {
    if (method %in% c("mean", "median", "knn")) {
      stop(sprintf("Categorical variable(%s) not support %s method",
        xvar, method))
    }

    type <- "categorical"
  }

  data <- pull(df, xvar)
  na_pos <- which(is.na(data))

  na_flag <- length(na_pos) > 0
  if (!na_flag) {
    warning(sprintf("There are no missing values in %s.", xvar))
  }

  get_mean <- function() {
    ifelse(is.na(data), mean(data, na.rm = TRUE), data)
  }

  get_median <- function() {
    ifelse(is.na(data), median(data, na.rm = TRUE), data)
  }

  get_mode <- function() {
    tab <- table(data)

    if (type == "numerical")
      mode_value <- as.numeric(names(tab)[which.max(tab)])
    else if (type == "categorical") {
      mode_value <- levels(data)[which.max(tab)]
    }

    data[is.na(data)] <- mode_value
    data
  }

  get_knn <- function(x, y) {
    impute <- knnImputation(df[, !names(df) %in% y])
    pred <- impute[, x]

    ifelse(is.na(data), pred, data)
  }

  get_rpart <- function(x, y) {
    if (type == "numerical") {
      method <- "anova"
      pred_type <- "vector"
    } else if (type == "categorical") {
      method <- "class"
      pred_type <- "class"
    }


    model <- rpart::rpart(sprintf("%s ~ .", x),
      data = df[!is.na(pull(df, x)), !names(df) %in% y],
      method = method, na.action = na.omit)

    pred <- predict(model, df[is.na(pull(df, x)), !names(df) %in% y],
      type = pred_type)

    data[is.na(data)] <- pred
    data
  }

  get_mice <- function(x, y, seed = NULL, print_flag = TRUE) {
    if (is.null(seed))
      seed <<- sample(seq(1e5), size = 1)

    if (!na_flag) {
      data <- pull(df, x)
    } else {
      set.seed(seed = seed)
      model <- mice(df[, !names(df) %in% y], method = "rf", printFlag = print_flag)

      if (type == "numerical") {
        pred <- apply(model$imp[[x]], 1, mean)

        data[is.na(data)] <- pred
      } else if (type == "categorical") {
        pred <- apply(model$imp[[x]], 1,
          function(x) unique(x)[which.max(table(x))])

        data[is.na(data)] <- pred
      }
    }

    data
  }

  if (method == "mean")
    result <- get_mean()
  else if (method == "median")
    result <- get_median()
  else if (method == "mode")
    result <- get_mode()
  else if (method == "knn")
    result <- get_knn(xvar, yvar)
  else if (method == "rpart")
    result <- get_rpart(xvar, yvar)
  else if (method == "mice")
    result <- get_mice(xvar, yvar, seed, print_flag)

  attr(result, "var_type") <- type
  attr(result, "method") <- method
  attr(result, "na_pos") <- na_pos
  attr(result, "seed") <- seed
  attr(result, "type") <- "missing values"

  class(result) <- append("imputation", class(result))
  result
}


#' Imputate Outliers
#'
#' @description
#' Outliers are imputated with some representative values and
#' statistical methods.
#'
#' @details
#' imputate_outlier() creates an imputation class.
#' The `imputation` class includes missing value position, imputated value,
#' and method of missing value imputation, etc.
#' The `imputation` class compares the imputated value with the original value
#' to help determine whether the imputated value is used in the analysis.
#'
#' See vignette("transformation") for an introduction to these concepts.
#'
#' @param .data a data.frame or a \code{\link{tbl_df}}.
#' @param xvar variable name to replace missing value.
#' @param method method of missing values imputation.
#' @return An object of imputation class.
#' Attributes of imputation class is as follows.
#' \itemize{
#' \item method : method of missing value imputation.
#' \itemize{
#'   \item predictor is numerical variable
#'   \itemize{
#'     \item "mean" : arithmetic mean
#'     \item "median" : median
#'     \item "mode" : mode
#'     \item "capping" : Imputate the upper outliers with 95 percentile,
#'     and Imputate the bottom outliers with 5 percentile.
#'   }
#' }
#' \item outlier_pos : position of outliers in predictor.
#' \item outliers : outliers. outliers corresponding to outlier_pos.
#' \item type : "outliers". type of imputation.
#' }
#' @seealso \code{\link{imputate_na}}.
#' @examples
#' # Generate data for the example
#' carseats <- ISLR::Carseats
#' carseats[sample(seq(NROW(carseats)), 20), "Income"] <- NA
#' carseats[sample(seq(NROW(carseats)), 5), "Urban"] <- NA
#'
#' # Replace the missing value of the Price variable with median
#' imputate_outlier(carseats, Price, method = "median")
#'
#' # Replace the missing value of the Price variable with rpart
#' # The target variable is US.
#' imputate_outlier(carseats, Price, method = "capping")
#'
#' ## using dplyr -------------------------------------
#' library(dplyr)
#'
#' # The mean before and after the imputation of the Price variable
#' carseats %>%
#'   mutate(Price_imp = imputate_outlier(carseats, Price, method = "capping")) %>%
#'   group_by(US) %>%
#'   summarise(orig = mean(Price, na.rm = TRUE),
#'     imputation = mean(Price_imp, na.rm = TRUE))
#'
#' # If the variable of interest is a numarical variable
#' price <- imputate_outlier(carseats, Price)
#' price
#' summary(price)
#' plot(price)
#' @export
imputate_outlier <- function(.data, xvar, method) {
  UseMethod("imputate_outlier")
}

#' @method imputate_outlier data.frame
#' @importFrom tidyselect vars_select
#' @importFrom rlang enquo
#' @export
imputate_outlier.data.frame <- function(.data, xvar,
  method = c("capping", "mean", "median", "mode")) {
  tryCatch(vars <- tidyselect::vars_select(names(.data), !!! rlang::enquo(xvar)),
    error = function(e) {
      pram <- as.character(substitute(xvar))
      stop(sprintf("Column %s is unknown", pram))
    }, finally = NULL)

  method <- match.arg(method)

  imputate_outlier_impl(.data, vars, method)
}

#' @import dplyr
#' @importFrom grDevices boxplot.stats
#' @importFrom methods is
imputate_outlier_impl <- function(df, xvar, method) {
  if (!is(pull(df, xvar))[1] %in% c("integer", "numeric")) {
    stop(sprintf("Categorical variable(%s) not support imputate_outlier()",
      xvar))
  }

  data <- pull(df, xvar)
  outliers <- boxplot.stats(data)$out
  outlier_pos <- which(data %in% outliers)
  outliers <- data[outlier_pos]

  outlier_flag <- length(outlier_pos) > 0
  if (!outlier_flag) {
    warning(sprintf("There are no outliers in %s.", xvar))
  }

  get_mean <- function(x) {
    data[outlier_pos] <- mean(data, na.rm = TRUE)
    data
  }

  get_median <- function() {
    data[outlier_pos] <- median(data, na.rm = TRUE)
    data
  }

  get_mode <- function() {
    tab <- table(data)

    mode_value <- as.numeric(names(tab)[which.max(tab)])

    data[outlier_pos] <- mode_value
    data
  }

  get_capping <- function() {
    hinges <- quantile(data, probs = c(0.25, 0.75), na.rm = TRUE)
    caps <- quantile(data, probs = c(0.05, 0.95), na.rm = TRUE)

    whisker <- 1.5 * diff(hinges)

    data[data < (hinges[1] - whisker)] <- caps[1]
    data[data > (hinges[2] + whisker)] <- caps[2]
    data
  }

  if (method == "mean")
    result <- get_mean()
  else if (method == "median")
    result <- get_median()
  else if (method == "mode")
    result <- get_mode()
  else if (method == "capping")
    result <- get_capping()

  attr(result, "method") <- method
  attr(result, "var_type") <- "numerical"
  attr(result, "outlier_pos") <- outlier_pos
  attr(result, "outliers") <- outliers
  attr(result, "type") <- "outliers"

  class(result) <- append("imputation", class(result))
  result
}

#' Summarizing imputation information
#'
#' @description print and summary method for "imputation" class.
#' @param object an object of class "imputation", usually, a result of a call to imputate_na() or
#' imputate_outlier().
#' @param ... further arguments passed to or from other methods.
#' @details
#' summary.imputation tries to be smart about formatting two kinds of imputation.
#'
#' @seealso \code{\link{imputate_na}}, \code{\link{imputate_outlier}}, \code{\link{summary.imputation}}.
#' @examples
#' \donttest{
#' # Generate data for the example
#' carseats <- ISLR::Carseats
#' carseats[sample(seq(NROW(carseats)), 20), "Income"] <- NA
#' carseats[sample(seq(NROW(carseats)), 5), "Urban"] <- NA
#'
#' # Imputate missing values -----------------------------
#' # If the variable of interest is a numarical variable
#' income <- imputate_na(carseats, Income, US, method = "rpart")
#' income
#' summary(income)
#' plot(income)
#'
#' # If the variable of interest is a categorical variable
#' urban <- imputate_na(carseats, Urban, US, method = "mice")
#' urban
#' summary(urban)
#' plot(urban)
#'
#' # Imputate outliers ----------------------------------
#' # If the variable of interest is a numarical variable
#' price <- imputate_outlier(carseats, Price, method = "capping")
#' price
#' summary(price)
#' plot(price)
#' }
#' @method summary imputation
#' @importFrom tidyr gather
#' @export
summary.imputation <- function(object, ...) {
  type <- attr(object, "type")
  method <- attr(object, "method")
  var_type <- attr(object, "var_type")

  original <- object

  if (type == "missing values") {
    na_pos <- attr(object, "na_pos")
    seed <- attr(object, "seed")

    original[na_pos] <- NA
  } else if (type == "outliers") {
    outlier_pos <- attr(object, "outlier_pos")
    outliers <- attr(object, "outliers")

    original[outlier_pos] <- outliers
  }

  if (var_type == "numerical") {
    original <- as.numeric(original)
    object <- as.numeric(object)
  } else if (var_type == "categorical") {
    original <- factor(original)
    object <- factor(object)
  }

  dframe <- data.frame(original = original,
    imputation = object) %>%
    tidyr::gather()

  if (var_type == "numerical") {
    smmry <- dframe %>%
      group_by(key) %>%
      describe("value") %>%
      select(-variable, -key) %>%
      t

    smmry <- smmry[, 2:1]
    colnames(smmry) <- c("Original", "Imputation")
  } else if (var_type == "categorical") {
    tab_freq <- xtabs(~ value + key, dframe, addNA = TRUE)
    tab_relat <- round(prop.table(tab_freq, 2) * 100, 2)

    smmry <- cbind(tab_freq, tab_relat)
    smmry <- smmry[, c(2, 1, 4, 3)]
    colnames(smmry) <- c("original", "imputation",
      "original_percent", "imputation_percent")
  }

  if (method %in% c("mean", "median", "mode", "capping")) {
    cat(sprintf("Impute %s with %s\n\n", type, method))
  } else if (method %in% c("knn", "rpart", "mice")) {
    if (method == "knn") {
      met <- "K-Nearest Neighbors"
      met <- sprintf("%s\n - method : knn", met)
    } else if (method == "rpart") {
      met <- "Recursive Partitioning and Regression Trees"
      met <- sprintf("%s\n - method : rpart", met)
    } else if (method == "mice") {
      met <- "Multivariate Imputation by Chained Equations"
      met <- sprintf("%s\n - method : mice", met)
      met <- sprintf("%s\n - random seed : %s", met, seed)
    }
    cat(sprintf("* Impute %s based on %s\n\n", type, met))
  }

  cat("* Information of Imputation (before vs after)\n")
  print(smmry)

  invisible(smmry)
}


#' Visualize Information for an "imputation" Object
#'
#' @description
#' Visualize two kinds of plot by attribute of `imputation` class.
#' The imputation of a numerical variable is a density plot,
#' and the imputation of a categorical variable is a bar plot.
#'
#' @param x an object of class "imputation", usually, a result of a call to imputate_na()
#' or imputate_outlier().
#' @param ... arguments to be passed to methods, such as graphical parameters (see par).
#' only applies when the model argument is TRUE, and is used for ... of the plot.lm () function.
#' @seealso \code{\link{imputate_na}}, \code{\link{imputate_outlier}}, \code{\link{summary.imputation}}.
#' @examples
#' \donttest{
#' # Generate data for the example
#' carseats <- ISLR::Carseats
#' carseats[sample(seq(NROW(carseats)), 20), "Income"] <- NA
#' carseats[sample(seq(NROW(carseats)), 5), "Urban"] <- NA
#'
#' # Imputate missing values -----------------------------
#' # If the variable of interest is a numarical variable
#' income <- imputate_na(carseats, Income, US, method = "rpart")
#' income
#' summary(income)
#' plot(income)
#'
#' # If the variable of interest is a categorical variable
#' urban <- imputate_na(carseats, Urban, US, method = "mice")
#' urban
#' summary(urban)
#' plot(urban)
#'
#' # Imputate outliers ----------------------------------
#' # If the variable of interest is a numarical variable
#' price <- imputate_outlier(carseats, Price, method = "capping")
#' price
#' summary(price)
#' plot(price)
#' }
#' @method plot imputation
#' @import ggplot2
#' @importFrom tidyr gather
#' @export
plot.imputation <- function(x, ...) {
  type <- attr(x, "type")
  var_type <- attr(x, "var_type")
  method <- attr(x, "method")

  original <- x

  if (type == "missing values") {
    na_pos <- attr(x, "na_pos")
    seed <- attr(x, "seed")

    original[na_pos] <- NA
  } else if (type == "outliers") {
    outlier_pos <- attr(x, "outlier_pos")
    outliers <- attr(x, "outliers")

    original[outlier_pos] <- outliers
  }

  if (method == "mice") {
    method <- sprintf("%s (seed = %s)", method, seed)
  }

  if (var_type == "numerical") {
    suppressWarnings({data.frame(original = original, imputation = x) %>%
        tidyr::gather() %>%
        ggplot(aes(x = value, color = key)) +
        geom_density(na.rm = TRUE) +
        ggtitle(sprintf("imputation method : %s", method)) +
        theme(plot.title = element_text(hjust = 0.5))})
  } else if (var_type == "categorical") {
    suppressWarnings({data.frame(original = original, imputation = x) %>%
        tidyr::gather() %>%
        ggplot(aes(x = value, fill = key)) +
        geom_bar(position = "dodge") +
        ggtitle(sprintf("imputation method : %s", method)) +
        theme(plot.title = element_text(hjust = 0.5))})
  }
}
