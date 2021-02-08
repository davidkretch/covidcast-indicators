from datetime import date, timedelta
from functools import partial
from typing import List

import numpy as np
from delphi_nowcast.data_containers import SensorConfig
from delphi_nowcast.deconvolution import delay_kernel, deconvolution
from delphi_nowcast.sensorization import sensor

FIRST_DATA_DATE = date(2020, 7, 1)  # first date of historical data to use


# todo: add scipy to Makefile

def compute_batch_sensors(input_locations: List[str],
                          pred_date: date,
                          as_of: date,
                          export_dir: str):
    """
    Compute batch of historical sensor values.

    Parameters
    ----------
    input_locations
        locations for which to compute sensors
    pred_date
        date to produce sensor
    as_of
        date to use data as it was as of then
    export_dir
        directory path to store sensor csv

    Returns
    -------

    """
    # define signals
    regression_indicators = [
        SensorConfig('usa-facts', 'confirmed_incidence_num', 'ar3', 1),
        SensorConfig('fb-survey', 'smoothed_hh_cmnty_cli', 'fb', 3)
    ]

    convolved_truth_indicator = SensorConfig(
        'usa-facts', 'confirmed_cumulative_prop', 'test_truth', 0)

    # sensor_indicators = [convolved_truth_indicator] + regression_indicators

    # get deconvolved ground truth
    kernel, delay_coefs = delay_kernel.get_florida_delay_distribution()  # param-to-store: delay_coefs
    cv_grid = np.logspace(1, 3.5, 20)  # param-to-store
    n_cv_folds = 10  # param-to-store
    deconvolve_func = partial(deconvolution.deconvolve_tf_cv,
                              cv_grid=cv_grid, n_folds=n_cv_folds)

    ground_truth = deconvolution.deconvolve_signal(convolved_truth_indicator,
                                                   FIRST_DATA_DATE,
                                                   pred_date - timedelta(days=1),
                                                   as_of,
                                                   input_locations,
                                                   np.array(kernel),
                                                   deconvolve_func)

    out_sensors = sensor.compute_sensors(as_of,
                                         regression_indicators,
                                         convolved_truth_indicator,
                                         ground_truth,
                                         export_dir)

