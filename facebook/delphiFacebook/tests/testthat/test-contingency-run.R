library(dplyr)
library(mockr)
library(data.table)

context("Verifying the data manipulation correctness of the contingency_tables pipeline")

base_aggs <- tribble(
  ~name, ~metric, ~group_by, ~compute_fn, ~post_fn,
  "freq_anxiety", "mc_anxiety", c("mc_gender"), compute_multiple_choice, I,
  "pct_hh_fever", "b_hh_fever", c("mc_gender"), compute_binary, I,
  "pct_comorbidities", "ms_comorbidities", c("mc_gender"), compute_multiselect, I,
)

# Suppress loading of archive to keep output predictable.
mock_load_archive <- function(...) {
  return(list(input_data = NULL, seen_tokens = NULL))
}


# `simple_responses.csv` was created by copying `responses.csv` and modifying
# columns C1 (comorbidities), C8_1 (anxiety), and D1 (gender).
#     - All C1 responses set to "4" (high blood pressure)
#     - All C8_1 responses set to "1" (no anxiety)
#     - All D1 responses set to "2" (female)
#
# `simple_synthetic.csv` was created by copying each row in 
# `simple_responses.csv`100 times for a total of 2000 responses and modifying
# columns C1 (comorbidities), C8_1 (anxiety), and token (for uniqueness).
#     - Obs 11 had C1 response set to "4,12" (high blood pressure + type 1 diabetes)
#     - Obs 1 had C8_1 response set to "4" (anxious all the time)
#     - Tokens were reset to row numbers to prevent errors due to non-uniqueness
#
# Weights are all set to 100.
get_params <- function(output_dir) {
  params <- read_contingency_params("params-full.json")
  params$input <- c("simple_synthetic.csv")
  params$weights_in_dir <- "./weights_simple"
  
  params <- relativize_params(params)
  
  params$export_dir <- output_dir
  return(params)
}


### This test relies on `setup-run.R` to run the pipeline. This test loads
### `input/responses.csv`, a small selected subset of test responses.
test_that("small dataset produces no output", {
  # Since the contingency tables tool removes aggregates that pose a privacy
  # risk, the small test dataset should produce no aggregates at all. In fact,
  # test output directory won't even be created.
  expected_files <- character(0)
  actual_files <- dir(test_path("receiving_contingency_test"))

  expect_setequal(expected_files, actual_files)
  expect_equal(dir.exists(test_path("receiving_contingency_test")), FALSE)
})


### Tests using equal weights

test_that("simple equal-weight dataset produces correct counts", {
  tdir <- tempfile()
  params <- get_params(tdir)
  create_dir_not_exist(params$export_dir)

  local_mock("delphiFacebook::load_archive" = mock_load_archive)
  run_contingency_tables_many_periods(params, base_aggs[1,])

  # Expected files
  expect_setequal(!!dir(params$export_dir), c("20200501_nation_gender_anxiety.csv"))

  # Expected file contents
  expected_output <- as.data.frame(tribble(
    ~geo_id, ~mc_gender, ~mc_anxiety, ~val_freq_anxiety, ~se_freq_anxiety, ~sample_size_freq_anxiety, ~represented_freq_anxiety,
    "us", "Female", 1L, 100 * (2000 - 1), NA, 2000L -1L, 100 * (2000 - 1)
    # "us", "Female", 4L, 100 * 1, xx, 1L, xx # censored due to sample size
  ))

  df <- read.csv(file.path(params$export_dir, "20200501_nation_gender_anxiety.csv"))
  expect_equivalent(df, expected_output)
})


test_that("simple equal-weight dataset produces correct percents", {
  tdir <- tempfile()
  params <- get_params(tdir)
  create_dir_not_exist(params$export_dir)

  local_mock("delphiFacebook::load_archive" = mock_load_archive)
  run_contingency_tables_many_periods(params, base_aggs[2,])

  # Expected files
  expect_setequal(!!dir(params$export_dir), c("20200501_nation_gender.csv"))

  # Expected file contents
  raw_data <- read.csv(test_path("./input/simple_synthetic.csv"))
  fever_prop <- mean( recode(raw_data[3:nrow(raw_data), "A1_1"], "1"=1, "2"=0) )

  expected_output <- as.data.frame(tribble(
    ~geo_id, ~mc_gender, ~val_pct_hh_fever, ~se_pct_hh_fever, ~sample_size_pct_hh_fever, ~represented_pct_hh_fever,
    "us", "Female", fever_prop * 100, NA, 2000L, 100 * 2000
  ))

  df <- read.csv(file.path(params$export_dir, "20200501_nation_gender.csv"))
  expect_equivalent(df, expected_output)
})


test_that("simple equal-weight dataset produces correct multiselect binary percents", {
  tdir <- tempfile()
  params <- get_params(tdir)
  create_dir_not_exist(params$export_dir)

  local_mock("delphiFacebook::load_archive" = mock_load_archive)
  run_contingency_tables_many_periods(params, base_aggs[3,])

  # Expected files
  expect_setequal(!!dir(params$export_dir), c("20200501_nation_gender.csv"))

  # Expected file contents
  expected_output <- as.data.frame(tribble(
    ~geo_id, ~mc_gender,
    ~val_pct_comorbidities_High_blood_pressure, ~se_pct_comorbidities_High_blood_pressure, ~sample_size_pct_comorbidities_High_blood_pressure, ~represented_pct_comorbidities_High_blood_pressure,
    ~val_pct_comorbidities_Type_1_diabetes, ~se_pct_comorbidities_Type_1_diabetes, ~sample_size_pct_comorbidities_Type_1_diabetes, ~represented_pct_comorbidities_Type_1_diabetes,
    "us", "Female",
    100, NA, 2000L, 100 * 2000,
    1/2000 * 100, NA, 2000L, 100 * 2000
  ))

  out <- read.csv(file.path(params$export_dir, "20200501_nation_gender.csv"))
  expect_equivalent(out, expected_output)
})


test_that("testing run with multiple aggregations per group", {
  tdir <- tempfile()
  params <- get_params(tdir)
  create_dir_not_exist(params$export_dir)

  local_mock("delphiFacebook::load_archive" = mock_load_archive)
  run_contingency_tables_many_periods(params, base_aggs)

  ## freq_anxiety
  expect_setequal(!!dir(params$export_dir), c("20200501_nation_gender.csv",
                                              "20200501_nation_gender_anxiety.csv"))

  # Expected file contents
  ## freq_anxiety
  expected_anxiety <- as.data.frame(tribble(
    ~geo_id, ~mc_gender, ~mc_anxiety, ~val_freq_anxiety, ~se_freq_anxiety, ~sample_size_freq_anxiety, ~represented_freq_anxiety,
    # "us", "Female", 4L, 100 * 1, xx, 1L, xx, # censored due to sample size
    "us", "Female", 1L, 100 * (2000 - 1), NA, 2000L -1L, 100 * (2000 - 1)
  ))

  out <- read.csv(file.path(params$export_dir, "20200501_nation_gender_anxiety.csv"))
  expect_equivalent(out, expected_anxiety)

  ## all other aggs
  raw_data <- read.csv(test_path("./input/simple_synthetic.csv"))
  fever_prop <- mean( recode(raw_data[3:nrow(raw_data), "A1_1"], "1"=1, "2"=0) )

  expected_other <- as.data.frame(tribble(
    ~geo_id, ~mc_gender,
    ~val_pct_hh_fever, ~se_pct_hh_fever, ~sample_size_pct_hh_fever, ~represented_pct_hh_fever,
    ~val_pct_comorbidities_High_blood_pressure, ~se_pct_comorbidities_High_blood_pressure, ~sample_size_pct_comorbidities_High_blood_pressure, ~represented_pct_comorbidities_High_blood_pressure,
    ~val_pct_comorbidities_Type_1_diabetes, ~se_pct_comorbidities_Type_1_diabetes, ~sample_size_pct_comorbidities_Type_1_diabetes, ~represented_pct_comorbidities_Type_1_diabetes,
    "us", "Female",
    fever_prop * 100, NA, 2000L, 100 * 2000,
    100, NA, 2000L, 100 * 2000,
    1/2000 * 100, NA, 2000L, 100 * 2000
  ))

  out <- read.csv(file.path(params$export_dir, "20200501_nation_gender.csv"))
  expect_equivalent(out, expected_other)
})


### Tests using non-equal weights. `mix_weights` is stubbed (output is fixed) so
### we can ignore the weight normalization process in calculating expected output

# Substitute mix_weights return value so can use in calculation for expected value.
set.seed(0)
rand_weights <- runif(2000)
rand_weights <- rand_weights / sum(rand_weights)

mock_join_weights <- function(data, params, weights = c("step1", "full")) {
  data <- cbind(as.data.table(data), weight=rand_weights)
  return(data)
}

mock_mix_weights <- function(weights, s_mix_coef, s_weight) {
  if ( length(weights) == 1 ) {
    return(list(
      weights=rand_weights[1],
      normalized_preweights=rand_weights[1]
    ))
  } else if ( length(weights) == 1999 ) {
    return(list(
      weights=rand_weights[2:2000],
      normalized_preweights=rand_weights[2:2000]
    ))
  } else {
    return(list(
      weights=rand_weights,
      normalized_preweights=rand_weights
    ))
  }
}

test_that("simple weighted dataset produces correct counts", {
  tdir <- tempfile()
  params <- get_params(tdir)
  create_dir_not_exist(params$export_dir)

  local_mock("delphiFacebook::join_weights" = mock_join_weights)
  local_mock("delphiFacebook::mix_weights" = mock_mix_weights)
  local_mock("delphiFacebook::load_archive" = mock_load_archive)
  run_contingency_tables_many_periods(params, base_aggs[1,])

  # Expected files
  expect_equal(!!dir(params$export_dir), c("20200501_nation_gender_anxiety.csv"))

  # Expected file contents
  raw_data <- read.csv(test_path("./input/simple_synthetic.csv"))
  anx_freq <- sum( rand_weights[raw_data[3:nrow(raw_data), "C8_1"] == "1"] )

  # Expected file contents
  expected_output <- as.data.frame(tribble(
    ~geo_id, ~mc_gender, ~mc_anxiety,
    ~val_freq_anxiety, ~se_freq_anxiety, ~sample_size_freq_anxiety, ~represented_freq_anxiety,
    # "us", "Female", 4L, xx, xx, 1L, xx, # censored due to sample size
    "us", "Female", 1L,
    anx_freq, NA, 2000L - 1L, sum(rand_weights[2:2000])
  ))

  out <- read.csv(file.path(params$export_dir, "20200501_nation_gender_anxiety.csv"))
  expect_equivalent(out, expected_output)
})


test_that("simple weighted dataset produces correct percents", {
  tdir <- tempfile()
  params <- get_params(tdir)
  create_dir_not_exist(params$export_dir)

  local_mock("delphiFacebook::join_weights" = mock_join_weights)
  local_mock("delphiFacebook::mix_weights" = mock_mix_weights)
  local_mock("delphiFacebook::load_archive" = mock_load_archive)
  run_contingency_tables_many_periods(params, base_aggs[2,])

  # Expected files
  expect_equal(!!dir(params$export_dir), c("20200501_nation_gender.csv"))

  # Expected file contents
  raw_data <- read.csv(test_path("./input/simple_synthetic.csv"))
  fever_prop <- weighted.mean( recode(raw_data[3:nrow(raw_data), "A1_1"], "1"=1, "2"=0) , rand_weights)

  expected_output <- as.data.frame(tribble(
    ~geo_id, ~mc_gender, ~val_pct_hh_fever, ~se_pct_hh_fever, ~sample_size_pct_hh_fever, ~represented_pct_hh_fever,
    "us", "Female", fever_prop * 100, NA, 2000L, sum(rand_weights)
  ))

  out <- read.csv(file.path(params$export_dir, "20200501_nation_gender.csv"))
  expect_equivalent(out, expected_output)
})


test_that("simple weighted dataset produces correct multiselect binary percents", {
  tdir <- tempfile()
  params <- get_params(tdir)
  create_dir_not_exist(params$export_dir)

  local_mock("delphiFacebook::join_weights" = mock_join_weights)
  local_mock("delphiFacebook::mix_weights" = mock_mix_weights)
  local_mock("delphiFacebook::load_archive" = mock_load_archive)
  run_contingency_tables_many_periods(params, base_aggs[3,])

  # Expected files
  expect_equal(!!dir(params$export_dir), c("20200501_nation_gender.csv"))

  # Expected file contents
  raw_data <- read.csv(test_path("./input/simple_synthetic.csv"))
  comorbid_prop <- weighted.mean( recode(raw_data[3:nrow(raw_data), "C1"], "4"=0, .default=1) , rand_weights)
  comorbid_prop <- round(comorbid_prop, digits=7)

  expected_output <- as.data.frame(tribble(
    ~geo_id, ~mc_gender,
    ~val_pct_comorbidities_High_blood_pressure, ~se_pct_comorbidities_High_blood_pressure, ~sample_size_pct_comorbidities_High_blood_pressure, ~represented_pct_comorbidities_High_blood_pressure,
    ~val_pct_comorbidities_Type_1_diabetes, ~se_pct_comorbidities_Type_1_diabetes, ~sample_size_pct_comorbidities_Type_1_diabetes, ~represented_pct_comorbidities_Type_1_diabetes,
    "us", "Female",
    100, NA, 2000L, sum(rand_weights),
    comorbid_prop * 100, NA, 2000L, sum(rand_weights)
  ))

  out <- read.csv(file.path(params$export_dir, "20200501_nation_gender.csv"))
  expect_equivalent(out, expected_output)
})

### Providing a range of dates to produce aggregates for
test_that("production of historical CSVs for range of dates", {
  tdir <- tempfile()

  params <- get_params(tdir)
  params$aggregate_range <- "week"
  params$n_periods <- 4
  params$input <- c("full_synthetic.csv")
  params$weights_in_dir <- "./weights_full"

  create_dir_not_exist(params$export_dir)

  run_contingency_tables_many_periods(params, base_aggs[2,])
  # Expected files
  expect_equal(!!dir(params$export_dir), c("20200503_nation_gender.csv", "20200510_nation_gender.csv"))
})


## Megacounties
test_that("county aggs are created correctly", {
  tdir <- tempfile()
  params <- get_params(tdir)
  params$num_filter <- 100
  params$s_mix_coef <- 0.05
  
  agg <- tribble(
    ~name, ~metric, ~group_by, ~compute_fn, ~post_fn, ~id, ~var_weight, ~skip_mixing,
    "pct_hh_fever", "b_hh_fever", c("mc_gender", "geo_id"), compute_binary, I, "pct_hh_fever", "weight", FALSE
  )
  geomap <- tribble(
    ~zip5, ~geo_id,
    "10001", "10001",
    "10004", "10004",
    "20004", "20004",
  )
  input <- as.data.table(
    data.frame(
      mc_gender = 1,
      b_hh_fever = c(rep(0, 75), rep(1, 30), rep(0, 101)),
      zip5 = c(rep("10001", 75), rep("10004", 30), rep("20004", 101)),
      weight = 100,
      weight_in_location = 1
    )
  )
  
  output <- summarize_aggs(input, geomap, agg, "county", params)
  # "AsIs" class originating from use of identity `I` in `post_fn` causes test
  # failure. Force to common format.
  output[[1]] <- tibble(output[[1]])
  
  expected_output <- list(
    "pct_hh_fever" = tribble(
      ~mc_gender, ~geo_id, ~val, ~se, ~sample_size, ~effective_sample_size, ~represented,
      1, "20004", 0, NA_real_, 101, 101,  100 * 101,
      ## Megacounties are not created.
      # 1, "10000", 30/105 * 100, NA_real_, 105, 105,  NA_real_
    )
  )
  
  expect_equal(output, expected_output)
})
