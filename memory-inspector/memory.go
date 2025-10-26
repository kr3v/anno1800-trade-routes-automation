package main

import (
	"fmt"

	"github.com/prometheus/procfs"
	"golang.org/x/sys/unix"
)

// MemoryRegion represents a parsed memory map entry
type MemoryRegion struct {
	StartAddr uintptr
	EndAddr   uintptr
	Size      uintptr
	Perms     *procfs.ProcMapPermissions
	Pathname  string
}

// ParseMemoryMaps reads and parses /proc/[pid]/maps using procfs
func ParseMemoryMaps(pid int) ([]MemoryRegion, error) {
	proc, err := procfs.NewProc(pid)
	if err != nil {
		return nil, fmt.Errorf("failed to open proc %d: %w", pid, err)
	}

	maps, err := proc.ProcMaps()
	if err != nil {
		return nil, fmt.Errorf("failed to read maps: %w", err)
	}

	regions := make([]MemoryRegion, 0, len(maps))
	for _, m := range maps {
		region := MemoryRegion{
			StartAddr: m.StartAddr,
			EndAddr:   m.EndAddr,
			Size:      m.EndAddr - m.StartAddr,
			Perms:     m.Perms,
			Pathname:  m.Pathname,
		}
		regions = append(regions, region)
	}

	return regions, nil
}

// ReadMemoryRegion reads memory from a specific region using process_vm_readv
func ReadMemoryRegion(pid int, startAddr uintptr, size uint64) ([]byte, error) {
	// Prepare local buffer
	localBuf := make([]byte, size)

	// Setup iovec structures for process_vm_readv
	local := []unix.Iovec{
		{
			Base: &localBuf[0],
			Len:  size,
		},
	}

	// Remote memory location to read from
	remote := []unix.RemoteIovec{
		{
			Base: startAddr,
			Len:  int(size),
		},
	}

	// Read from remote process
	n, err := unix.ProcessVMReadv(pid, local, remote, 0)
	if err != nil {
		return nil, fmt.Errorf("ProcessVMReadv failed: %w", err)
	}

	if n == 0 {
		return nil, fmt.Errorf("read 0 bytes from process memory")
	}

	return localBuf[:n], nil
}

// ReadMemoryAt reads a specific amount of memory at an address
func ReadMemoryAt(pid int, addr uintptr, size int) ([]byte, error) {
	return ReadMemoryRegion(pid, addr, uint64(size))
}
