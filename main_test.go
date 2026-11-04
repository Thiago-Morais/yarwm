package main

import "testing"

// Placeholder so `go test ./...` exercises the toolchain from day one.
// Real tests arrive with each feature under internal/.
func TestVersionIsSet(test *testing.T) {
	if version == "" {
		test.Fatal("version constant must not be empty")
	}
}
