# Tab 2 distance/duration: refresh displayed units and investigate PT save failure

*Last content commit: 2026-09-07. Organized: 2026-09-11. Review/validation; conclusions retain their original scope.*

Two findings from the test-user review (IDs 32 and 39). Scope: the distance/duration modal, not a sampling redesign.

## 32: REF amount does not follow its displayed units

Reported: changing week/year, distance/duration, or total/per-person leaves the same suggested REF number in the modal. Saving can therefore give an unchanged number a different meaning.

### What the tester experienced

In **Basic mode, Tab 2, distance/duration input**, the prefilled Reference amount reportedly stays numerically identical when the user changes its interpretation: kilometres per week, minutes per year, or an average per person. The problem is not simply an outdated label: saving the same number under a different unit can describe a very different amount of active travel.

For illustration (not a recorded test value), 100 km/week should become about 5,218 km/year when expressing the same activity annually, not remain 100. Converting a total to a per-person average also requires a population denominator. Switching between distance and duration additionally needs a speed assumption. These are distinct conversions, not interchangeable labels.

**Suggested reproduction:** select Basic and distance/duration; open a mode's Tab 2 input modal; note the suggested REF amount and its settings; change week to year, then test total versus average per person and distance versus duration separately. Check the visible amount, save, and reopen to check the stored amount and settings agree.

**Expected:** the amount and selected units describe the same activity after a representational change, or the app clearly asks for a new value where it cannot convert. **Reported actual:** the REF number stays unchanged. This can silently alter the assessed volume, potentially by a factor of about 52 for week/year alone. The downstream numerical effect has not been independently reproduced here.

### Implementation pointers

Code inspection: `modal_data_entry_distance()` creates the numeric fields once. I could not find a corresponding unit-change observer in `modules/tab2/tab2Server.R`. The modal also borrows unit selections from the first selected mode with an existing input, which can disagree with the basis of another mode's stored amounts.

HUB already handles distance/duration units, timeframes and denominators in `R/tab2_input_conversion.R`; reference defaults use the same settings in `R/reference_data_extract_reference_ui_values.R`. The existing conversion test file passes (15 expectations), but this does not test modal updates or the complete PT path.

- [ ] Keep REF/CF amounts, labels and saved unit settings consistent when changing controls or reopening a modal. A unit change should not silently reinterpret the previous number.
- [ ] Convert explicitly entered amounts where the conversion is defined; do not replace manual entries with source defaults. For distance versus duration, use the effective speed assumption or request confirmation/new values.
- [ ] Check week/year, km/miles, minutes/hours and total/per-person. Equivalent representations should reach HUB as equivalent weekly totals (within rounding). The current per-person denominator in HUB is assessed population size, not mode-user count.

## 39: Walk-to-PT modal closes without saving successfully

Reported: in Basic distance/duration mode, save the Walk-to-PT modal; it closes, the card still says "not provided", and the session becomes unusable.

### What the tester experienced

In **Basic mode, Tab 2, distance/duration input**, the tester opens the **Walking to/from public transport (Walk-to-PT)** modal and attempts to save the input. The modal disappears as though saving succeeded. The assumptions display updates, but the PT input card still says **"not provided"**. The tester then reports that the session is dead/unusable. There is no useful visible explanation of what failed.

**Suggested reproduction:** include PT among the assessed modes; choose distance/duration in Tab 2; open the PT input modal; enter valid REF/CF values and select "Verify, save and close". Check whether the PT card changes to provided, whether reopening retains the values, and whether calculation/navigation still works. Repeat with PT alone and with walking + PT. The original report does not provide exact values or a server traceback, so these are reproduction steps to investigate, not a confirmed minimal failing example.

**Expected:** valid inputs are saved, the card acknowledges them, and the session remains usable. If saving fails, the app explains the problem rather than closing as if it succeeded. **Reported actual:** modal closes, PT remains "not provided", and the session stops working.

### Implementation pointers

The PT-specific root cause is not confirmed. However, `www/miamiv1.js` sends input names and immediately hides the modal. The save observer in `server.R` subsequently reads those inputs and can abort before updating the data-entry flag. This is a plausible failure path, not a reproduced diagnosis.

- [ ] Reproduce with PT alone and walking + PT, for both kilometres and minutes; capture the first server error and submitted input IDs/values.
- [ ] Check the PT fields and `data_entry_flags$pt$distance` through save, card refresh and reopening. Close as successful only after server acceptance; show any validation/save error without ending the session.
- [ ] Confirm successful inputs reach HUB and produce a calculable scenario; escalate any valid-payload failure to HUB with that payload.

Nearby misleading field: `distdur_default_*` displays 7.5 under a sentence about the number of users, but no HUB consumer was found for these fields. It should not suggest that an editable value affects calculations when it does not.

Inspected UI `dev` (`f95148b`) and advanced `dev-pub` (`8ee6a06`); the distance/duration modal and shared JavaScript save behavior are present in both. HUB inspected at `9f34661`. No interactive reproduction or UI edits made in this assessment.
