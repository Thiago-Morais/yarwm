package filter

import (
	"errors"
	"testing"
)

func TestRangeMatches(test *testing.T) {
	testCases := []struct {
		name        string
		valueRange  Range
		matching    []int
		notMatching []int
	}{
		{"empty matches everything", Range{}, []int{1, 10}, nil},
		{"exact matches only its value", Range{Exact: new(5)}, []int{5}, []int{4, 6}},
		{"min only", Range{Min: new(7)}, []int{7, 10}, []int{6}},
		{"max only", Range{Max: new(3)}, []int{1, 3}, []int{4}},
		{"min and max include both ends", Range{Min: new(4), Max: new(6)}, []int{4, 5, 6}, []int{3, 7}},
	}

	for _, testCase := range testCases {
		test.Run(testCase.name, func(subtest *testing.T) {
			for _, value := range testCase.matching {
				if !testCase.valueRange.Matches(value) {
					subtest.Errorf("%v should match %d", testCase.valueRange, value)
				}
			}
			for _, value := range testCase.notMatching {
				if testCase.valueRange.Matches(value) {
					subtest.Errorf("%v shouldn't match %d", testCase.valueRange, value)
				}
			}
		})
	}
}

func TestRangeIsEmpty(test *testing.T) {
	if !(Range{}).IsEmpty() {
		test.Error("zero Range should be empty")
	}
	if (Range{Max: new(3)}).IsEmpty() {
		test.Error("Range with a max shouldn't be empty")
	}
}

func TestRangeValidate(test *testing.T) {
	testCases := []struct {
		name       string
		valueRange Range
		expected   error
	}{
		{"empty", Range{}, nil},
		{"exact", Range{Exact: new(5)}, nil},
		{"min and max", Range{Min: new(4), Max: new(6)}, nil},
		{"min equal to max", Range{Min: new(5), Max: new(5)}, nil},
		{"exact with min", Range{Exact: new(5), Min: new(4)}, ErrExactWithBounds},
		{"exact with max", Range{Exact: new(5), Max: new(6)}, ErrExactWithBounds},
		{"min above max", Range{Min: new(7), Max: new(3)}, ErrMinAboveMax},
	}

	for _, testCase := range testCases {
		test.Run(testCase.name, func(subtest *testing.T) {
			actual := testCase.valueRange.Validate()
			if !errors.Is(actual, testCase.expected) {
				subtest.Errorf("Validate() = %v, want %v", actual, testCase.expected)
			}
		})
	}
}

func TestRangeString(test *testing.T) {
	testCases := []struct {
		valueRange Range
		expected   string
	}{
		{Range{}, "any"},
		{Range{Exact: new(5)}, "5"},
		{Range{Min: new(7)}, ">= 7"},
		{Range{Max: new(3)}, "<= 3"},
		{Range{Min: new(4), Max: new(6)}, "4-6"},
	}

	for _, testCase := range testCases {
		if actual := testCase.valueRange.String(); actual != testCase.expected {
			test.Errorf("String() = %q, want %q", actual, testCase.expected)
		}
	}
}
