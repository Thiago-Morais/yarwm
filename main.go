// Command yarwm is Yet Another Random Wallpaper Manager.
package main

import (
	"fmt"
	"os"
)

func main() {
	if len(os.Args) < 2 {
		printUsage()
		os.Exit(2)
	}

	switch subcommand := os.Args[1]; subcommand {
	case "version", "--version":
		fmt.Println("yarwm", currentVersion())
	case "help", "-h", "--help":
		printUsage()
	default:
		fmt.Fprintf(os.Stderr, "yarwm: unknown command %q\n\n", subcommand)
		printUsage()
		os.Exit(2)
	}
}

func printUsage() {
	fmt.Fprintln(os.Stderr, `Usage: yarwm <command> [arguments]

Commands:
  version    print the yarwm version
  help       show this message`)
}
