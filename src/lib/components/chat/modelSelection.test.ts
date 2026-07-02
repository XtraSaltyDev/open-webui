import { describe, expect, test } from 'vitest';

import { resolveAvailableModelIds } from './modelSelection';

const model = (id: string) => ({ id, name: id });

describe('resolveAvailableModelIds', () => {
	test('falls back to the first available model when the selected id is stale', () => {
		expect(resolveAvailableModelIds(['old-model'], [model('new-model')])).toEqual(['new-model']);
	});

	test('prefers configured defaults that are still available', () => {
		expect(
			resolveAvailableModelIds(['old-model'], [model('new-model'), model('default-model')], [
				'default-model'
			])
		).toEqual(['default-model']);
	});

	test('keeps valid selected models and removes stale ones from multi-model selections', () => {
		expect(
			resolveAvailableModelIds(['old-model', 'new-model'], [model('new-model'), model('other-model')])
		).toEqual(['new-model']);
	});
});
