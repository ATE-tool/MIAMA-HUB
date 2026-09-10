# Brief Response to the MIAMAT Review

Thank you for tracing the input routes and highlighting how strongly recipient
selection can influence the result. We checked the observations against the
currently installed HUB package (9001), the latest HUB source (9002), and UI dev.
Several concerns remain relevant, but some explanations need qualification.

1. **Different results from users and trips inputs:** This is an important
   concern, but equal total trips do not necessarily specify the same health
   scenario. Adding 155 cyclists differs from allocating extra trips mainly to
   existing cyclists. We need to distinguish intended differences in recipients
   and activity from unintended differences caused by the input route.

2. **Default recruitment and activity allocation:** The routes currently use
   different recruitment pools and weights. This should be explicit and consistent
   with the intended scenario. The 10% value is configurable; it does not guarantee
   that exactly 10% of trips, or of actually affected people, go to new users.
   We should clarify the denominator and new-to-mode versus new-to-any-active-travel
   definition before choosing a different default or introducing activity caps.

3. **New-user slider:** Confirmed in a focused current-version check: changing
   the advanced slider from 10% to 100% did not change the result once generated
   population counts were accepted. We should fix how the slider updates those
   estimates, while preserving the agreed rule that final Tab 3 counts remain
   authoritative and cannot be changed retrospectively by Tab 4.

4. **Stale inputs and navigation effects:** We reproduced stale users fields
   affecting a trips-route result. This is a genuine bug to fix. The reported
   24% change from selecting a Tab 4 method alone was not reproduced in our
   current staged test, but should remain a regression test. Simply disabling
   an entire handler could break legitimate downstream population/trip edits.

5. **Sampling variance:** It exists and needs reporting, but cannot explain
   all route differences. Three fresh seeds gave approximately 36.6-40.3 HALYs
   for one clean trips scenario; this is only an exploratory check, not an
   uncertainty interval. HUB already accepts seeds, and a variance study already
   exists. We should extend it to the complete UI/HUB lifecycle and separate
   sampling variation from sensitivity to allocation assumptions.

6. **Manchester and donor exhaustion:** The current Manchester package contains
   10,000 people, including the report's 4,952 walkers and 711 cyclists. That is
   49.5% walking prevalence, not 99%, unless the original appraisal explicitly
   selected a different 5,000-person scope. The explanation based on only about
   50 non-walkers therefore needs revisiting. The health diagnostic also counts
   `n_ind` and `n_changed_ind` from the same frame; comparison with the original
   source size is a separate issue. We should label source donors, appraisal
   records and donor copies distinctly.

7. **Healthy life years versus HALYs:** These should be distinguished, but
   `unhealthy` is a net state transition that includes death and recovery, not
   simple accumulating disease incidence. The proposed absorbing-state diagnosis
   is incorrect. We did identify a separate baseline-state omission in HUB's
   healthy-life-years reconstruction that needs fixing. That does not establish
   an error in the separately calculated HALYs.

8. **AMAT comparison and future model choices:** Differences in dose, recipients,
   outcome definition and cohort treatment prevent this from being an equivalence
   test. The AMAT total for the same Leeds example also differs between the summary
   and detailed table and needs reconciliation. Closed-cohort behaviour is a known
   limitation, not a newly introduced bug. We should fix route/state handling and
   validate matched scenarios before considering new cohort models or adjusting
   assumptions to bring the tools closer together.

**Suggested order:** fix stale-route inputs and advanced allocation handling;
correct and document HLY reconstruction; refresh the variance study with
reproducible, matched scenarios; then decide whether recruitment policy and
production uncertainty reporting need changing. No calculation/UI code has been
changed as part of this assessment.

See [the detailed assessment and to-do list](external_review_assessment_2026-09-09.md)
for verification limits, code pointers and indicative effort estimates.
