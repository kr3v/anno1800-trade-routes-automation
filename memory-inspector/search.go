package main

import (
	"bytes"
	"encoding/binary"
	"log"
	"regexp"
	"sync"
)

// SearchMatch represents a found pattern match
type SearchMatch struct {
	Address       uintptr
	Region        MemoryRegion
	Context       []byte // surrounding bytes for context
	PatternOffset int    // offset of the main pattern within context
	PatternLength int    // length of the main pattern
}

// Reference represents a pointer/reference to an address found in memory
type Reference struct {
	RefAddress    uintptr      // Address where the reference was found
	TargetAddress uintptr      // Address being referenced (the target)
	Region        MemoryRegion // Region where the reference was found
	Context       []byte       // surrounding bytes for context
	RefOffset     int          // offset of the reference within context
}

// searchPatternInRegion is a generic function to search for byte patterns in a memory region
// It processes the region in chunks and calls the provided callback for each match found
func searchPatternInRegion(
	pid int,
	region MemoryRegion,
	pattern []byte,
	contextBefore int,
	contextAfter int,
	callback func(matchAddr uintptr, context []byte, patternOffsetInContext int),
) error {
	const chunkSize = 1 << 30 // 1 GiB

	regionSize := uint64(region.Size)
	overlap := uint64(len(pattern) - 1) // Overlap to catch patterns at chunk boundaries

	// Process region in chunks
	for chunkStart := uint64(0); chunkStart < regionSize; {
		// Calculate chunk size (with overlap for next chunk)
		currentChunkSize := min(chunkSize, regionSize-chunkStart)

		// Read chunk
		data, err := ReadMemoryRegion(pid, region.StartAddr+uintptr(chunkStart), currentChunkSize)
		if err != nil {
			return err
		}

		// Search for all occurrences using bytes.Index
		offset := 0
		for {
			idx := bytes.Index(data[offset:], pattern)
			if idx == -1 {
				break
			}

			i := offset + idx
			absoluteOffset := chunkStart + uint64(i)
			matchAddr := region.StartAddr + uintptr(absoluteOffset)

			// Extract context
			contextStart := max(0, i-contextBefore)
			contextEnd := min(len(data), i+len(pattern)+contextAfter)

			// Clone the context to avoid keeping reference to the data buffer
			context := make([]byte, contextEnd-contextStart)
			copy(context, data[contextStart:contextEnd])

			// Calculate pattern offset within context
			patternOffsetInContext := i - contextStart

			// Call callback with the match
			callback(matchAddr, context, patternOffsetInContext)

			// Move past this match to find the next one
			offset = i + 1
		}

		// Move to next chunk, with overlap to catch patterns at boundaries
		if chunkStart+currentChunkSize >= regionSize {
			break
		}
		chunkStart += currentChunkSize - overlap
	}

	return nil
}

// searchRegion searches for a byte pattern in a memory region
func searchRegion(pid int, region MemoryRegion, pattern []byte) ([]SearchMatch, error) {
	var matches []SearchMatch

	err := searchPatternInRegion(pid, region, pattern, 1024, 1024,
		func(matchAddr uintptr, context []byte, patternOffsetInContext int) {
			matches = append(matches, SearchMatch{
				Address:       matchAddr,
				Region:        region,
				Context:       context,
				PatternOffset: patternOffsetInContext,
				PatternLength: len(pattern),
			})
		})

	return matches, err
}

// parallelRegionSearch is a generic function to search across all regions in parallel
func parallelRegionSearch(
	pid int,
	regions []MemoryRegion,
	searchFunc func(pid int, region MemoryRegion) error,
) {
	const maxConcurrent = 16 // Limit concurrent searches to prevent OOM

	var (
		wg  sync.WaitGroup
		sem = make(chan struct{}, maxConcurrent) // Semaphore for concurrency control
	)

	for _, region := range regions {
		if !region.Perms.Read {
			continue
		}
		if ok, err := regexp.MatchString("data\\d+\\.rda", region.Pathname); ok {
			continue
		} else if err != nil {
			log.Printf("pathname=%s regexp error=%v", region.Pathname, err)
		}

		wg.Add(1)
		go func(r MemoryRegion) {
			defer wg.Done()

			// Acquire semaphore
			sem <- struct{}{}
			defer func() { <-sem }() // Release semaphore

			// Execute the search function (errors are silently ignored)
			_ = searchFunc(pid, r)
		}(region)
	}

	wg.Wait()
}

// parallelSearch searches for a pattern across all readable regions in parallel
func parallelSearch(pid int, regions []MemoryRegion, pattern []byte) []SearchMatch {
	var (
		mu      sync.Mutex
		matches []SearchMatch
	)

	parallelRegionSearch(pid, regions, func(pid int, region MemoryRegion) error {
		regionMatches, err := searchRegion(pid, region, pattern)
		if err != nil {
			return err
		}

		if len(regionMatches) > 0 {
			mu.Lock()
			matches = append(matches, regionMatches...)
			mu.Unlock()
		}
		return nil
	})

	return matches
}

// findReferencesToAddress searches for pointers to a specific address in a memory region
func findReferencesToAddress(pid int, region MemoryRegion, targetAddr uintptr) ([]Reference, error) {
	var references []Reference

	// Convert address to little-endian bytes (x86_64)
	addrBytes := make([]byte, 8)
	binary.LittleEndian.PutUint64(addrBytes, uint64(targetAddr))

	err := searchPatternInRegion(pid, region, addrBytes, 64, 64,
		func(refAddr uintptr, context []byte, refOffsetInContext int) {
			references = append(references, Reference{
				RefAddress:    refAddr,
				TargetAddress: targetAddr,
				Region:        region,
				Context:       context,
				RefOffset:     refOffsetInContext,
			})
		})

	return references, err
}

// FindReferencesToAddresses finds all references to a set of addresses across all regions
func FindReferencesToAddresses(pid int, regions []MemoryRegion, targetAddrs []uintptr) map[uintptr][]Reference {
	var (
		mu     sync.Mutex
		result = make(map[uintptr][]Reference)
	)

	// Initialize result map
	for _, addr := range targetAddrs {
		result[addr] = []Reference{}
	}

	// For each target address, search all regions
	for _, targetAddr := range targetAddrs {
		parallelRegionSearch(pid, regions, func(pid int, region MemoryRegion) error {
			refs, err := findReferencesToAddress(pid, region, targetAddr)
			if err != nil {
				return err
			}

			if len(refs) > 0 {
				mu.Lock()
				result[targetAddr] = append(result[targetAddr], refs...)
				mu.Unlock()
			}
			return nil
		})
	}

	return result
}
