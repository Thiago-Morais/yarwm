package main

import "runtime/debug"

// injectedVersion is set at build time by the Makefile, from `git describe`
// run on the host:
//
//	go build -ldflags "-X main.injectedVersion=v0.1.0-3-g257be6f-dirty"
//
// The dev container builds with -buildvcs=false so Go never shells out to
// git itself; the host already has git, so it supplies the string instead.
var injectedVersion string

const unknownVersion = "(devel)"

// currentVersion is what `yarwm version` prints.
func currentVersion() string {
	buildInfoVersion := ""
	if buildInfo, available := debug.ReadBuildInfo(); available {
		buildInfoVersion = buildInfo.Main.Version
	}
	return resolveVersion(injectedVersion, buildInfoVersion)
}

// resolveVersion picks the best available version string:
//  1. the version injected by the Makefile (local builds),
//  2. the module version Go recorded (`go install ...@v0.1.0` sets this
//     from the module system — no git involved),
//  3. "(devel)" when neither is known.
func resolveVersion(injected string, buildInfoVersion string) string {
	if injected != "" {
		return injected
	}
	if buildInfoVersion != "" && buildInfoVersion != unknownVersion {
		return buildInfoVersion
	}
	return unknownVersion
}
