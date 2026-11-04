package main

import "testing"

func TestResolveVersion(test *testing.T) {
	testCases := []struct {
		name             string
		injected         string
		buildInfoVersion string
		expected         string
	}{
		{"injected wins over build info", "v0.1.0-3-g257be6f-dirty", "v0.1.0", "v0.1.0-3-g257be6f-dirty"},
		{"go install module version", "", "v0.1.0", "v0.1.0"},
		{"go reports devel", "", "(devel)", "(devel)"},
		{"nothing known", "", "", "(devel)"},
	}

	for _, testCase := range testCases {
		test.Run(testCase.name, func(subtest *testing.T) {
			actual := resolveVersion(testCase.injected, testCase.buildInfoVersion)
			if actual != testCase.expected {
				subtest.Errorf("resolveVersion(%q, %q) = %q, want %q",
					testCase.injected, testCase.buildInfoVersion, actual, testCase.expected)
			}
		})
	}
}
