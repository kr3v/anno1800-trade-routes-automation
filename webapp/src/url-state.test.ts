/**
 * URL State Encoding/Decoding Tests
 */

import { describe, it, expect } from 'vitest';
import { encodeFilterSet, decodeFilterSet } from './url-state';

describe('Filter encoding/decoding', () => {
  const allOptions = new Set(['apple', 'banana', 'cherry', 'date', 'elderberry']);

  describe('encodeFilterSet', () => {
    it('returns null for empty selection', () => {
      const result = encodeFilterSet(new Set(), allOptions);
      expect(result).toBe(null);
    });

    it('returns "ALL" when all items are selected', () => {
      const result = encodeFilterSet(allOptions, allOptions);
      expect(result).toBe('ALL');
    });

    it('returns exclusion syntax when only one item is excluded', () => {
      const selected = new Set(['apple', 'banana', 'cherry', 'elderberry']);
      const result = encodeFilterSet(selected, allOptions);
      expect(result).toBe('ALL\\date');
    });

    it('returns comma-separated list when less than half are selected', () => {
      const selected = new Set(['apple', 'banana']);
      const result = encodeFilterSet(selected, allOptions);
      expect(result).toBe('apple,banana');
    });

    it('returns exclusion list when more than half are selected', () => {
      const selected = new Set(['apple', 'banana', 'cherry', 'date']);
      const result = encodeFilterSet(selected, allOptions);
      expect(result).toBe('ALL\\elderberry');
    });

    it('sorts items consistently', () => {
      const selected1 = new Set(['cherry', 'apple']);
      const selected2 = new Set(['apple', 'cherry']);
      const result1 = encodeFilterSet(selected1, allOptions);
      const result2 = encodeFilterSet(selected2, allOptions);
      expect(result1).toBe(result2);
      expect(result1).toBe('apple,cherry');
    });
  });

  describe('decodeFilterSet', () => {
    it('returns null for null input', () => {
      const result = decodeFilterSet(null, allOptions);
      expect(result).toBe(null);
    });

    it('returns all options for "ALL"', () => {
      const result = decodeFilterSet('ALL', allOptions);
      expect(result).toEqual(allOptions);
    });

    it('decodes exclusion syntax correctly', () => {
      const result = decodeFilterSet('ALL\\date', allOptions);
      expect(result).toEqual(new Set(['apple', 'banana', 'cherry', 'elderberry']));
    });

    it('decodes multiple exclusions correctly', () => {
      const result = decodeFilterSet('ALL\\date,elderberry', allOptions);
      expect(result).toEqual(new Set(['apple', 'banana', 'cherry']));
    });

    it('decodes comma-separated list correctly', () => {
      const result = decodeFilterSet('apple,cherry', allOptions);
      expect(result).toEqual(new Set(['apple', 'cherry']));
    });

    it('filters out invalid items from comma-separated list', () => {
      const result = decodeFilterSet('apple,invalid,cherry', allOptions);
      expect(result).toEqual(new Set(['apple', 'cherry']));
    });

    it('filters out invalid items from exclusion list', () => {
      const result = decodeFilterSet('ALL\\invalid,date', allOptions);
      // Should exclude only 'date' (invalid is ignored)
      expect(result).toEqual(new Set(['apple', 'banana', 'cherry', 'elderberry']));
    });
  });

  describe('round-trip encoding/decoding', () => {
    it('preserves ALL selection', () => {
      const original = allOptions;
      const encoded = encodeFilterSet(original, allOptions);
      const decoded = decodeFilterSet(encoded, allOptions);
      expect(decoded).toEqual(original);
    });

    it('preserves partial selection', () => {
      const original = new Set(['apple', 'cherry']);
      const encoded = encodeFilterSet(original, allOptions);
      const decoded = decodeFilterSet(encoded, allOptions);
      expect(decoded).toEqual(original);
    });

    it('preserves single exclusion', () => {
      const original = new Set(['apple', 'banana', 'cherry', 'elderberry']);
      const encoded = encodeFilterSet(original, allOptions);
      const decoded = decodeFilterSet(encoded, allOptions);
      expect(decoded).toEqual(original);
    });

    it('preserves multiple exclusions', () => {
      const original = new Set(['apple', 'banana', 'cherry']);
      const encoded = encodeFilterSet(original, allOptions);
      const decoded = decodeFilterSet(encoded, allOptions);
      expect(decoded).toEqual(original);
    });
  });
});
