package main

import (
	"bufio"
	"fmt"
	"io"
	"os"
)

// extractBracketSequences extracts all [...] sequences from input,
// properly handling nested parentheses like [Foo([Bar]) Baz]
func extractBracketSequences(input string) []string {
	var sequences []string
	var current []rune
	inBracket := false
	parenDepth := 0

	for _, ch := range input {
		if !inBracket {
			if ch == '[' {
				inBracket = true
				current = []rune{'['}
			}
			continue
		}

		// Inside a bracket sequence
		current = append(current, ch)

		switch ch {
		case '(':
			parenDepth++
		case ')':
			parenDepth--
		case ']':
			// Only close the bracket if we're not inside nested parentheses
			if parenDepth == 0 {
				sequences = append(sequences, string(current))
				current = nil
				inBracket = false
			}
		}
	}

	return sequences
}

func main() {
	scanner := bufio.NewScanner(os.Stdin)

	for scanner.Scan() {
		line := scanner.Text()
		sequences := extractBracketSequences(line)

		for _, seq := range sequences {
			fmt.Println(seq)
		}
	}

	if err := scanner.Err(); err != nil && err != io.EOF {
		fmt.Fprintf(os.Stderr, "Error reading input: %v\n", err)
		os.Exit(1)
	}
}
