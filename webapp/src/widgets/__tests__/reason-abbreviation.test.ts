/**
 * Test for reason abbreviation logic
 */

import { describe, it, expect } from 'vitest';

/**
 * Abbreviate a reason string into short code
 * Examples:
 *   Construction -> C
 *   Production/Bakery -> Pr/Bak
 *   Production/Sewing Machine Factory -> Pr/SMF
 *   Production/Restaurant: Archduke's Schnitzel -> Pr/Res
 *   Population/Worker Residence -> P/W
 */
function abbreviateReason(reason: string): string {
  const parts = reason.split('/');

  if (parts.length === 1) {
    // Single word - take first letter, capitalize
    return parts[0].charAt(0).toUpperCase();
  }

  // Has category and subcategory
  const category = parts[0];
  let subcategory = parts[1];

  // Drop everything after colon
  if (subcategory.includes(':')) {
    subcategory = subcategory.split(':')[0].trim();
  }

  // Drop "Residence" if present
  subcategory = subcategory.replace(/\s*Residence\s*/g, '').trim();

  // Abbreviate category (first 2 letters or first letter of each word)
  const categoryAbbr = category.length <= 3
    ? category.charAt(0).toUpperCase()
    : category.substring(0, 2);

  // Abbreviate subcategory - take first letter of each word
  const subcategoryWords = subcategory.split(/\s+/);
  const subcategoryAbbr = subcategoryWords
    .map(word => word.charAt(0).toUpperCase())
    .join('');

  return `${categoryAbbr}/${subcategoryAbbr}`;
}

describe('abbreviateReason', () => {
  it('should abbreviate Construction to C', () => {
    expect(abbreviateReason('Construction')).toBe('C');
  });

  it('should abbreviate Production/Bakery to Pr/B', () => {
    expect(abbreviateReason('Production/Bakery')).toBe('Pr/B');
  });

  it('should abbreviate Production/Sewing Machine Factory to Pr/SMF', () => {
    expect(abbreviateReason('Production/Sewing Machine Factory')).toBe('Pr/SMF');
  });

  it('should abbreviate Production/Restaurant: Archduke\'s Schnitzel to Pr/R', () => {
    expect(abbreviateReason('Production/Restaurant: Archduke\'s Schnitzel')).toBe('Pr/R');
  });

  it('should abbreviate Population/Worker Residence to Po/W', () => {
    expect(abbreviateReason('Population/Worker Residence')).toBe('Po/W');
  });

  it('should abbreviate Population/Farmer Residence to Po/F', () => {
    expect(abbreviateReason('Population/Farmer Residence')).toBe('Po/F');
  });

  it('should abbreviate Population/Artisan Residence to Po/A', () => {
    expect(abbreviateReason('Population/Artisan Residence')).toBe('Po/A');
  });

  it('should abbreviate Production/Rendering Works to Pr/RW', () => {
    expect(abbreviateReason('Production/Rendering Works')).toBe('Pr/RW');
  });

  it('should abbreviate Production/Slaughterhouse to Pr/S', () => {
    expect(abbreviateReason('Production/Slaughterhouse')).toBe('Pr/S');
  });
});
