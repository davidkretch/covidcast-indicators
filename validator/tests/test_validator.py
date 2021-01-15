"""Tests for Validator"""
import pytest
from delphi_validator.validate import Validator

class TestValidatorInitialization:
    """Tests for proper initialization."""
    def test_default_settings(self):
        """Test default initialization."""
        params = {"data_source": "", "span_length": 0,
                  "end_date": "2020-09-01", "expected_lag": {}}
        validator = Validator(params)
        assert len(validator.suppressed_errors) == 0
        assert isinstance(validator.suppressed_errors, set)

    def test_suppressed_errors(self):
        """Test initialization with suppressed errors."""
        params = {"data_source": "",
                  "span_length": 0,
                  "end_date": "2020-09-01",
                  "expected_lag": {},
                  "suppressed_errors": [["a", "b"], ["c", "d"], ["a", "b"]]
                 }

        validator = Validator(params)
        assert validator.suppressed_errors == set([("a", "b"), ("c", "d")])

    def test_incorrect_suppressed_errors(self):
        """Test initialization with improperly coded suppressed errors."""
        with pytest.raises(AssertionError):
            # entry of length not equal to 2
            Validator({"data_source": "",
                       "span_length": 0,
                       "end_date": "2020-09-01",
                       "expected_lag": {},
                       "suppressed_errors": [["a", "b"], ["c", "d"], ["ab"]]
                      })

        with pytest.raises(AssertionError):
            # entry that is not a list
            Validator({"data_source": "",
                       "span_length": 0,
                       "end_date": "2020-09-01",
                       "expected_lag": {},
                       "suppressed_errors": [["a", "b"], ["c", "d"], "ab"]
                      })