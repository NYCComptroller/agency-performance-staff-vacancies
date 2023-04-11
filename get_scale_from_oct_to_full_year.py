#%%

import pandas as pd
import numpy as np

# %%

# download data from https://data.cityofnewyork.us/City-Government/Mayor-s-Management-Report-Agency-Performance-Indic/rbed-zzin
# TODO: read this directly from api

indicators = pd.read_csv('./Raw Data/Mayor_s_Management_Report_-_Agency_Performance_Indicators.csv', true_values=['Yes'], false_values=['No'], parse_dates=['Created On', 'Value Date'])

indicators = indicators.drop_duplicates()
indicators = indicators.set_index('ID')

#%%

# we manually identified miscoded indicators that should be 'Additive', or that should be scaled to full-year

reset_Additive = pd.read_csv('./Processed Data/reset Additive.csv')
reset_Additive = reset_Additive.set_index('ID')

add_scaler = pd.read_csv('./Processed Data/add scaler.csv')
add_scaler = add_scaler.set_index('ID')


#%%

# overwrite 'Additive'

indicators.loc[
    indicators.index.isin(reset_Additive.index), 'Additive'
] = reset_Additive['reset Additive to']

#%%

# pull out 'Accepted Value YTD' for Oct and Jun for additive measures
# keep indicators with an additive data type or that have been manually identified as additive

indicators = indicators.reset_index()

indicators_additive_oct_jun = (
    indicators[
        (
            (indicators['Measurement Type'].isin(['Number','Currency','TimeSpan'])) | 
            (indicators['ID'].isin(reset_Additive.index))
        ) & 
        (indicators['Additive']) &
        (indicators['Value Date'].dt.month.isin([10,6]))
    ]
    .set_index(['ID','Value Date'])
    ['Accepted Value YTD']
    .sort_index()
    .unstack()
)


# compute scale as value in each time period (i.e. Oct) divided by value in the next time period (i.e. June). keep only the Oct columns.

indicators_additive_scale = (
    indicators_additive_oct_jun / indicators_additive_oct_jun.shift(-1, axis=1)
)[[col for col in indicators_additive_oct_jun.columns if col.month == 10]]    


# get mean of non-NaN values

indicators_additive_scaler = indicators_additive_scale.apply(np.nanmean, axis=1)


#%%
# replace some wrong scalers (identified by manually reviewing history) with 0.333

indicators_additive_scaler.loc[
    indicators_additive_scaler.index.isin(add_scaler.index)
] = 0.333



#%%
# add scalers for others that should be scaled (from manually reviewing history)
# (these are instances where historically the data is only presented annually, so there is not way to compute an Oct-->full-year scale, but the measure is cumulative so should be scaled)

indicators_scaler_fixed = (
    pd.concat([
        indicators_additive_scaler,
        add_scaler[~add_scaler.index.isin(indicators_additive_scaler.index)]['set Oct value fraction of full year value to']
        ])
)

#%% 
# save out.

(
    indicators_scaler_fixed
    .rename('Oct value fraction of full year value')
    .to_frame()
    .to_csv('./Processed Data/scale Oct value to full-year value.csv')
)

