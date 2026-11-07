// Package filter selects values, such as a wallpaper's quality, by an
// exact match or an inclusive range.
package filter

import (
	"errors"
	"fmt"
)

// Range is either an exact value or an inclusive minimum and/or maximum.
// The zero value matches everything.
type Range struct {
	Exact *int `toml:"exact" json:"exact,omitempty"`
	Min   *int `toml:"min" json:"min,omitempty"`
	Max   *int `toml:"max" json:"max,omitempty"`
}

var (
	ErrExactWithBounds = errors.New("exact can't be combined with min or max")
	ErrMinAboveMax     = errors.New("min is greater than max")
)

func (valueRange Range) IsEmpty() bool {
	return valueRange.Exact == nil && valueRange.Min == nil && valueRange.Max == nil
}

func (valueRange Range) Matches(value int) bool {
	if valueRange.Exact != nil {
		return value == *valueRange.Exact
	}
	if valueRange.Min != nil && value < *valueRange.Min {
		return false
	}
	if valueRange.Max != nil && value > *valueRange.Max {
		return false
	}
	return true
}

func (valueRange Range) Validate() error {
	hasBounds := valueRange.Min != nil || valueRange.Max != nil
	if valueRange.Exact != nil && hasBounds {
		return ErrExactWithBounds
	}
	if valueRange.Min != nil && valueRange.Max != nil && *valueRange.Min > *valueRange.Max {
		return fmt.Errorf("%w: min %d, max %d", ErrMinAboveMax, *valueRange.Min, *valueRange.Max)
	}
	return nil
}

// String formats the range for people: "any", "5", ">= 7", "<= 3" or "4-6".
func (valueRange Range) String() string {
	switch {
	case valueRange.Exact != nil:
		return fmt.Sprint(*valueRange.Exact)
	case valueRange.Min != nil && valueRange.Max != nil:
		return fmt.Sprintf("%d-%d", *valueRange.Min, *valueRange.Max)
	case valueRange.Min != nil:
		return fmt.Sprintf(">= %d", *valueRange.Min)
	case valueRange.Max != nil:
		return fmt.Sprintf("<= %d", *valueRange.Max)
	default:
		return "any"
	}
}
