import { describe, expect, test } from 'vitest';

import { isModelInUsagePool } from './usage';

describe('isModelInUsagePool', () => {
	test('matches the selected model id against the live usage pool', () => {
		expect(isModelInUsagePool(['model-a', 'model-b'], 'model-b')).toBe(true);
	});

	test('matches any known model alias against the live usage pool', () => {
		expect(isModelInUsagePool(['base-model-id'], ['friendly-model-id', 'base-model-id'])).toBe(
			true
		);
	});

	test('returns false when the usage pool is absent or the model id is empty', () => {
		expect(isModelInUsagePool(null, 'model-b')).toBe(false);
		expect(isModelInUsagePool(['model-a'], '')).toBe(false);
	});
});
