# -*- coding: utf-8 -*-
"""Functions to call when running the module.
"""
import numpy as np
import os
import pandas as pd
from delphi_utils import read_params

from .qualtrics import make_fetchers,get

def run_module():
    params = read_params()
    qparams = params['qualtrics']
    qparams['qualtrics_dir'] = params['input_dir']

    if not os.path.exists(qparams['qualtrics_dir']):
        os.makedirs(qparams['qualtrics_dir'])

    if not qparams['token']:
        print("\nDRY-RUN MODE\n")
    fetch,post = make_fetchers(qparams)

    get(fetch, post, qparams)
