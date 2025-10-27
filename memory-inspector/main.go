package main

import (
	"bytes"
	"fmt"
	"log"
	"os"
	"strconv"
)

func main() {
	if len(os.Args) < 2 {
		log.Fatal("Usage: memory-inspector <PID> [dump <address> <offset_before> <offset_after>]")
	}

	pid, err := strconv.Atoi(os.Args[1])
	if err != nil {
		log.Fatalf("Invalid PID: %v", err)
	}

	// Check if this is a memory dump command
	if len(os.Args) >= 3 && os.Args[2] == "dump" {
		if len(os.Args) != 6 {
			log.Fatal("Usage: memory-inspector <PID> dump <address> <offset_before> <offset_after>")
		}

		// Parse address (supports hex with 0x prefix)
		var address uint64
		_, err := fmt.Sscanf(os.Args[3], "0x%x", &address)
		if err != nil {
			// Try parsing as decimal
			address, err = strconv.ParseUint(os.Args[3], 10, 64)
			if err != nil {
				log.Fatalf("Invalid address: %v", err)
			}
		}

		offsetBefore, err := strconv.Atoi(os.Args[4])
		if err != nil {
			log.Fatalf("Invalid offset_before: %v", err)
		}

		offsetAfter, err := strconv.Atoi(os.Args[5])
		if err != nil {
			log.Fatalf("Invalid offset_after: %v", err)
		}

		if offsetBefore < 0 || offsetAfter < 0 {
			log.Fatal("Offsets must be non-negative")
		}

		// Call the print function
		if err := PrintMemoryAtAddress(pid, uintptr(address), offsetBefore, offsetAfter); err != nil {
			log.Fatalf("Failed to print memory: %v", err)
		}
		return
	}

	fmt.Printf("Parsing memory maps for PID %d...\n", pid)

	// Parse memory maps
	regions, err := ParseMemoryMaps(pid)
	if err != nil {
		log.Fatalf("Failed to parse memory maps: %v", err)
	}

	fmt.Printf("Found %d memory regions\n\n", len(regions))

	//Display first few regions
	for i, region := range regions {
		fmt.Printf("[%d] 0x%016x-0x%016x (%8d bytes) %s\n",
			i, region.StartAddr, region.EndAddr, region.Size,
			region.Pathname)
	}

	// Hardcoded search term - change this to whatever you're looking for
	searchTerm := `ShowRouteUI`
	fmt.Printf("\nSearching for pattern '%s' across all readable regions...\n", searchTerm)
	doMatch(pid, regions, []byte(searchTerm))

	//a := 8589935495
	//pattern := make([]byte, 8)
	//binary.LittleEndian.PutUint64(pattern, uint64(a))
	//fmt.Printf("\nSearching for pattern '%v' across all readable regions...\n", pattern)
	//doMatch(pid, regions, pattern)
}

func doMatch(pid int, regions []MemoryRegion, pattern []byte) {
	// Perform parallelized search
	matches := parallelSearch(pid, regions, pattern)

	fmt.Printf("\nFound %d matches:\n\n", len(matches))

	// Define additional patterns to highlight (optional)
	additionalPatterns := []struct {
		pattern []byte
		color   string
	}{
		//Add your additional patterns here, for example:
		//{pattern: []byte{34}, color: ColorGreen},
		//{pattern: []byte{37}, color: ColorGreen},
		//{pattern: []byte{41}, color: ColorGreen},
		//{pattern: []byte{19}, color: ColorGreen},
		//{pattern: []byte{46}, color: ColorGreen},
		//{pattern: []byte{11}, color: ColorGreen},
	}

	// Display all matches
	for i, match := range matches {
		fmt.Printf("Match #%d:\n", i+1)
		fmt.Printf("  Address:  0x%016x\n", match.Address)
		fmt.Printf("  Region:   addr=0x%016x-0x%016x (%8d bytes) %s\n",
			match.Region.StartAddr, match.Region.EndAddr,
			match.Region.Size, match.Region.Pathname)
		fmt.Printf("  Context (with match highlighted):\n")

		// Build highlights list
		highlights := []Highlight{
			// Main pattern in red
			{
				Start: match.PatternOffset,
				End:   match.PatternOffset + match.PatternLength,
				Color: ColorRed,
			},
		}

		// Search for additional patterns in the context
		for _, ap := range additionalPatterns {
			offset := 0
			for {
				idx := bytes.Index(match.Context[offset:], ap.pattern)
				if idx == -1 {
					break
				}
				actualPos := offset + idx
				highlights = append(highlights, Highlight{
					Start: actualPos,
					End:   actualPos + len(ap.pattern),
					Color: ap.color,
				})
				offset = actualPos + 1
			}
		}

		printHexDump(match.Context, highlights)
		fmt.Println()
	}

	//findReferences(pid, regions, matches)
}

// PrintMemoryAtAddress prints the memory content at a specific address with a given offset range
func PrintMemoryAtAddress(pid int, address uintptr, offsetBefore int, offsetAfter int) error {
	// Calculate the start address and total size
	startAddr := address - uintptr(offsetBefore)
	totalSize := offsetBefore + offsetAfter

	// Read memory at the address
	data, err := ReadMemoryAt(pid, startAddr, totalSize)
	if err != nil {
		return fmt.Errorf("failed to read memory at 0x%016x: %w", address, err)
	}

	// Print header
	fmt.Printf("\n=== Memory at address 0x%016x (-%d to +%d bytes) ===\n\n",
		address, offsetBefore, offsetAfter)
	fmt.Printf("Start: 0x%016x\n", startAddr)
	fmt.Printf("End:   0x%016x\n", startAddr+uintptr(totalSize))
	fmt.Printf("Size:  %d bytes\n\n", totalSize)

	// Create a highlight for the target address
	highlights := []Highlight{
		{
			Start: offsetBefore,
			End:   offsetBefore + 1,
			Color: ColorRed,
		},
	}

	// Print the hex dump with the target byte highlighted
	printHexDump(data, highlights)
	fmt.Println()

	return nil
}

func findReferences(pid int, regions []MemoryRegion, matches []SearchMatch) {
	// Find references to match addresses
	fmt.Println("\n=== Finding references to match addresses ===\n")

	// Collect all match addresses
	targetAddrs := make([]uintptr, len(matches))
	for i, match := range matches {
		targetAddrs[i] = match.Address
	}

	// Search for references
	fmt.Printf("Searching for pointers to %d addresses...\n", len(targetAddrs))
	references := FindReferencesToAddresses(pid, regions, targetAddrs)

	// Display references
	totalRefs := 0
	for _, refs := range references {
		totalRefs += len(refs)
	}
	fmt.Printf("Found %d total references\n\n", totalRefs)

	for i, match := range matches {
		refs := references[match.Address]
		if len(refs) == 0 {
			continue
		}

		fmt.Printf("References to Match #%d (0x%016x): %d found\n", i+1, match.Address, len(refs))
		for j, ref := range refs {
			if j >= 5 {
				fmt.Printf("  ... and %d more references\n", len(refs)-j)
				break
			}
			fmt.Printf("  Ref #%d:\n", j+1)
			fmt.Printf("    Ref Address: 0x%016x\n", ref.RefAddress)
			fmt.Printf("    Region:      addr=0x%016x-0x%016x %s\n",
				ref.Region.StartAddr, ref.Region.EndAddr, ref.Region.Pathname)
			fmt.Printf("    Context:\n")

			// Highlight the pointer in cyan
			refHighlights := []Highlight{
				{
					Start: ref.RefOffset,
					End:   ref.RefOffset + 8,
					Color: ColorCyan,
				},
			}
			printHexDump(ref.Context, refHighlights)
			fmt.Println()
		}
		fmt.Println()
	}
}
