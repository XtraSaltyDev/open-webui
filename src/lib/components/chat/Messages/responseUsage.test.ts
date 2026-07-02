import { describe, expect, test } from 'vitest';

import { formatOutputTokenSpeed, withOutputTokenSpeed } from './responseUsage';

describe('response usage speed helpers', () => {
	test('formats explicit output speed metadata', () => {
		expect(formatOutputTokenSpeed({ output_tokens_per_second: 18.345 })).toBe('18.35 tok/s');
		expect(formatOutputTokenSpeed({ 'response_token/s': 7 })).toBe('7 tok/s');
	});

	test('derives output speed from output tokens and duration', () => {
		expect(formatOutputTokenSpeed({ completion_tokens: 42, response_duration_seconds: 6 })).toBe(
			'7 tok/s'
		);
		expect(formatOutputTokenSpeed({ eval_count: 100, eval_duration: 10_000_000_000 })).toBe(
			'10 tok/s'
		);
	});

	test('adds measured output speed without mutating usage', () => {
		const usage = { completion_tokens: 25 };
		const updated = withOutputTokenSpeed(usage, 5000);

		expect(updated).toEqual({ completion_tokens: 25, output_tokens_per_second: 5 });
		expect(usage).toEqual({ completion_tokens: 25 });
	});

	test('returns null when usage cannot produce a positive speed', () => {
		expect(formatOutputTokenSpeed(null)).toBeNull();
		expect(formatOutputTokenSpeed({ completion_tokens: 0, response_duration_seconds: 5 })).toBeNull();
		expect(formatOutputTokenSpeed({ completion_tokens: 5, response_duration_seconds: 0 })).toBeNull();
	});
});
