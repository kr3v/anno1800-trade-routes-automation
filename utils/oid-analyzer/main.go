package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"
	"strings"
)

type pair[A, B any] struct {
	First  A
	Second B
}

func MapToSlice[K comparable, V any](m map[K]V) []pair[K, V] {
	s := make([]pair[K, V], 0, len(m))
	for k, v := range m {
		s = append(s, pair[K, V]{k, v})
	}
	return s
}

func main() {
	var allEntries []entry

	for _, s := range os.Args[1:] {
		entries, err := ParseEntries(s)
		if err != nil {
			panic(err)
		}
		allEntries = append(allEntries, entries...)
	}

	allOids := make(map[uint64]string)
	for _, e := range allEntries {
		allOids[e.Oid] = e.Text
	}
	allOidsS := MapToSlice(allOids)

	type _uint64 struct {
		a, b uint32
	}
	allOidsU := make([]pair[_uint64, string], 0, len(allOidsS))
	for _, p := range allOidsS {
		oid := p.First
		a := uint32(oid >> 32)
		b := uint32(oid & 0xFFFFFFFF)
		allOidsU = append(allOidsU, pair[_uint64, string]{_uint64{a, b}, p.Second})
	}

	textToAToCount := make(map[string]map[uint32]int)
	for _, p := range allOidsU {
		text := p.Second
		if _, ok := textToAToCount[text]; !ok {
			textToAToCount[text] = make(map[uint32]int)
		}
		textToAToCount[text][p.First.a]++
	}

	for text, aToCount := range textToAToCount {
		for a, count := range aToCount {
			if count > 1 {
				fmt.Printf("%s %d %d\n", strings.ReplaceAll(text, " ", "_"), a, count)
			}
		}
	}
}

type entry struct {
	Oid  uint64
	Name string
	Guid string
	Text string
}

func ParseEntries(s string) ([]entry, error) {
	f, err := os.Open(s)
	if err != nil {
		return nil, err
	}
	defer f.Close()

	var ret []entry

	sc := bufio.NewScanner(f)
	for sc.Scan() {
		line := sc.Text()
		var a entry
		err := json.Unmarshal([]byte(line), &a)
		if err != nil {
			return nil, err
		}
		ret = append(ret, a)
	}
	return ret, nil
}
