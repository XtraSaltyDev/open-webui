import { render } from 'svelte/server';
import { afterEach, describe, expect, test, vi } from 'vitest';

import Suggestions from './Suggestions.svelte';

const prompts = [
	{ content: 'Build a data table', title: ['Build a data table', 'Create structured output'] },
	{ content: 'Explain this code', title: ['Explain this code', 'Break down a snippet'] },
	{ content: 'Draft a release note', title: ['Draft a release note', 'Summarize a change'] }
];

const renderedTitles = (html: string) =>
	prompts
		.map((prompt) => ({
			title: prompt.title[0],
			index: html.indexOf(prompt.title[0])
		}))
		.sort((a, b) => a.index - b.index)
		.map((prompt) => prompt.title);

describe('Suggestions', () => {
	afterEach(() => {
		vi.restoreAllMocks();
	});

	test('keeps quick-start chips in a stable order for the same prompt set', () => {
		vi.spyOn(Math, 'random')
			.mockReturnValueOnce(0.9)
			.mockReturnValueOnce(0.9)
			.mockReturnValueOnce(0.1)
			.mockReturnValueOnce(0.1);

		const first = render(Suggestions, { props: { suggestionPrompts: prompts } });
		const second = render(Suggestions, {
			props: { suggestionPrompts: prompts.map((prompt) => ({ ...prompt })) }
		});

		expect(renderedTitles(second.body)).toEqual(renderedTitles(first.body));
	});
});
