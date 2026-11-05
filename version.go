package main

import "runtime/debug"

// Set by the Makefile from the host's `git describe`, not by Go's own VCS stamping.
var injectedVersion string

const unknownVersion = "(devel)"

func currentVersion() string {
	buildInfoVersion := ""
	if buildInfo, available := debug.ReadBuildInfo(); available {
		buildInfoVersion = buildInfo.Main.Version
	}
	return resolveVersion(injectedVersion, buildInfoVersion)
}

func resolveVersion(injected string, buildInfoVersion string) string {
	if injected != "" {
		return injected
	}
	if buildInfoVersion != "" && buildInfoVersion != unknownVersion {
		return buildInfoVersion
	}
	return unknownVersion
}
