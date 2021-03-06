% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/diagnose.R
\name{diagnose_outlier}
\alias{diagnose_outlier}
\title{Diagnose outlier of numerical variables}
\usage{
diagnose_outlier(.data, ...)
}
\arguments{
\item{.data}{a data.frame or a \code{\link{tbl_df}}.}

\item{...}{one or more unquoted expressions separated by commas.
You can treat variable names like they are positions.
Positive values select variables; negative values to drop variables.
If the first expression is negative, diagnose_outlier() will automatically
start with all variables.
These arguments are automatically quoted and evaluated in a context
where column names represent column positions.
They support unquoting and splicing.}
}
\value{
an object of tbl_df.
}
\description{
The diagnose_outlier() produces outlier information
for diagnosing the quality of the numerical data.
}
\details{
The scope of the diagnosis is the provide a outlier information.
If the number of outliers is small and the difference between the averages
including outliers and the averages not including them is large,
it is necessary to eliminate or replace the outliers.
}
\section{Outlier Diagnostic information}{

The information derived from the numerical data diagnosis is as follows.

\itemize{
\item variables : variable names
\item outliers_cnt : count of outliers
\item outliers_ratio : percent of outliers
\item outliers_mean : arithmetic average of outliers
\item with_mean : arithmetic average of with outliers
\item without_mean : arithmetic average of without outliers
}

See vignette("diagonosis") for an introduction to these concepts.
}

\examples{
# Generate data for the example
carseats <- ISLR::Carseats
carseats[sample(seq(NROW(carseats)), 20), "Income"] <- NA
carseats[sample(seq(NROW(carseats)), 5), "Urban"] <- NA

# Diagnosis of numerical variables
diagnose_outlier(carseats)

# Select the variable to diagnose
diagnose_outlier(carseats, Sales, Income)
diagnose_outlier(carseats, -Sales, -Income)
diagnose_outlier(carseats, "Sales", "Income")
diagnose_outlier(carseats, 5)

# Using pipes ---------------------------------
library(dplyr)

# Diagnosis of all numerical variables
carseats \%>\%
  diagnose_outlier()
# Positive values select variables
carseats \%>\%
  diagnose_outlier(Sales, Income)
# Negative values to drop variables
carseats \%>\%
  diagnose_outlier(-Sales, -Income)
# Positions values select variables
carseats \%>\%
  diagnose_outlier(5)
# Positions values select variables
carseats \%>\%
  diagnose_outlier(-1, -5)

# Using pipes & dplyr -------------------------
# outlier_ratio is more than 1\%
carseats \%>\%
  diagnose_outlier()  \%>\%
  filter(outliers_ratio > 1)
}
\seealso{
\code{\link{diagnose}}, \code{\link{diagnose_category}}, \code{\link{diagnose_numeric}}.
}
