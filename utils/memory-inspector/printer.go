package main

import "fmt"

// ANSI color codes
const (
	ColorReset   = "\033[0m"
	ColorRed     = "\033[31m"
	ColorGreen   = "\033[32m"
	ColorYellow  = "\033[33m"
	ColorBlue    = "\033[34m"
	ColorMagenta = "\033[35m"
	ColorCyan    = "\033[36m"
)

// Highlight represents a range to highlight in the hex dump
type Highlight struct {
	Start int
	End   int
	Color string
}

func printHexDump(data []byte, highlights []Highlight) {
	for i := 0; i < len(data); i += 16 {
		// Print offset
		fmt.Printf("%04x: ", i)

		// Print hex bytes
		for j := 0; j < 16; j++ {
			if i+j < len(data) {
				bytePos := i + j
				color := getHighlightColor(bytePos, highlights)
				if color != "" {
					fmt.Printf("%s%02x%s ", color, data[bytePos], ColorReset)
				} else {
					fmt.Printf("%02x ", data[bytePos])
				}
			} else {
				fmt.Print("   ")
			}
		}

		// Print ASCII sidebar
		fmt.Print(" |")
		for j := 0; j < 16 && i+j < len(data); j++ {
			bytePos := i + j
			b := data[bytePos]
			color := getHighlightColor(bytePos, highlights)

			ch := "."
			if b >= 32 && b <= 126 {
				ch = string(b)
			}

			if color != "" {
				fmt.Printf("%s%s%s", color, ch, ColorReset)
			} else {
				fmt.Print(ch)
			}
		}
		fmt.Println("|")
	}
}

func getHighlightColor(pos int, highlights []Highlight) string {
	for _, h := range highlights {
		if pos >= h.Start && pos < h.End {
			return h.Color
		}
	}
	return ""
}
