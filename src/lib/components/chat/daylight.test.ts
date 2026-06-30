import { describe, expect, test } from 'vitest';

import { getDaylightGreeting } from './daylight';

describe('getDaylightGreeting', () => {
	test('uses morning before noon', () => {
		expect(getDaylightGreeting(9)).toBe('Good morning');
	});

	test('uses afternoon from noon through late afternoon', () => {
		expect(getDaylightGreeting(12)).toBe('Good afternoon');
		expect(getDaylightGreeting(17)).toBe('Good afternoon');
	});

	test('uses evening after 18:00', () => {
		expect(getDaylightGreeting(18)).toBe('Good evening');
		expect(getDaylightGreeting(23)).toBe('Good evening');
	});
});
