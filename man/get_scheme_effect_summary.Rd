\name{get_scheme_effect_summary}
\alias{get_scheme_effect_summary}
\title{Describe the effective scheme lifetime}
\usage{get_scheme_effect_summary(profile = list())}
\arguments{\item{profile}{Appraisal profile or flat list of scheme timeline fields.}}
\value{A named character vector of display-ready descriptions, keyed by the
applicable scheme field IDs. Years are measured from scheme start.}
\description{Uses the same validated effective settings as
\code{get_scheme_effect_timeline}. Hidden decline years are omitted when the
scheme has no decline. Does not modify the profile.}
