\name{get_scheme_effect_timeline}
\alias{get_scheme_effect_timeline}
\title{Calculate the annual scheme effect curve}
\usage{get_scheme_effect_timeline(profile = list(), cycles = 0:40)}
\arguments{
\item{profile}{Appraisal profile or flat list containing scheme_peak_year,
scheme_no_decline, scheme_decline_year and scheme_end_year. Active year settings
must be whole numbers from 0 to 40; decline starts at or after peak and ends later.}
\item{cycles}{Non-negative integer model years. Cycle zero is baseline.}
}
\value{A data frame with cycle, effect_factor (annual average), and
effect_at_year_end (instantaneous effect for previews).}
\description{Validates and integrates a linear build-up, plateau and optional
linear decline. Defaults to one year of build-up and permanent effect. This
read-only function does not sample data or modify the profile.}
