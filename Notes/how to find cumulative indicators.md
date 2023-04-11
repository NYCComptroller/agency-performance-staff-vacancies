In the course of this analysis we found that the categorization of indicators as ‘Additive’ in the source MMR data is not fully accurate. For some indicators, the patterns of data show that they are recorded cumulatively, but they are not accurately tagged as ‘Additive.’ 

This inconsistent labeling was a problem for this analysis because we made estimates of the full-year FY23 performance based on scaling cumulative measures from the reported October 2022 value to the projected June 2023 value. If we relied on the tagging and mischaracterized indicators as not additive, we would severely underestimate the performance.

Ideally, some of this data will be cleaned up in the future, but this is still a good thing to check. Here’s how we did it:

First, compute scaling by naively relying on the ‘Additive’ tags and the data types to select which indicators should be scaled. That’s how we ran `get_scale_from_oct_to_full_year.py` the first time. You can run it again this way by commenting-out lines `31-33`, `46`, `73-75`, and `86`, or temporarily making `reset Additive.csv` and `add scaler.csv` empty files. (Sorry for not versioning the original for you! We’re learning.)

With those initial scalers created, run the `MMR  Evaluation.R` which will filter the indicators to only those with usable direction and data, then scale those indicators with the scalers created above to the full-year, and save out a summary.

Now you want to check that output for indicators that are far off from their levels in earlier years to identify ones that actually should be scaled. 

I did that with the notebook [Notes/check indicator scaling to full year.ipynb](Notes/check indicator scaling to full year.ipynb). 

Select the indicators where the FY23 estimate is <0.75x or >1.5x the indicator’s five-year average, then go back to the raw data and plot the timelines of those indicators. The ones that are logged cumulatively are easy to spot by their saw-tooth pattern. Any that _are_ cumulative can be added to the `reset Additive.csv` list, by adding a row with the indicator ID and the field `reset Additive to` as `True`.  Additionally, check for indicators that historically were only logged once per year, but for which we do have data for the most recent October. For these, set a default scaling of 0.333 in `add scaler.csv`.

Now. run `get_scale_from_oct_to_full_year.py` again (uncommenting those skipped lines) to create a better list of scalers. Then run `MMR Evaluation.R` again to get more accurate summary data.

Tada!
