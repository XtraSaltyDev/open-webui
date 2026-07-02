import { describe, expect, test } from 'vitest';
import { readFileSync } from 'node:fs';

const readProjectFile = (path: string) =>
	readFileSync(new URL(`../../../${path}`, import.meta.url), 'utf-8');

describe('response action toolbar', () => {
	test('keeps the hidden regenerate shortcut out of the visible toolbar layout', () => {
		const appCss = readProjectFile('app.css');
		const responseMessage = readFileSync(
			new URL('./Messages/ResponseMessage.svelte', import.meta.url),
			'utf-8'
		);

		expect(responseMessage).toContain('class="hidden regenerate-response-button"');
		expect(appCss).toContain('.daylight-response-actions button:not(.hidden),');
		expect(appCss).toContain('.daylight-response-actions button.hidden');
		expect(appCss).toContain('display: none;');
	});

	test('renders output token speed at the end of the actions row when usage is available', () => {
		const responseMessage = readFileSync(
			new URL('./Messages/ResponseMessage.svelte', import.meta.url),
			'utf-8'
		);

		expect(responseMessage).toContain('formatOutputTokenSpeed(message?.usage)');
		expect(responseMessage).toContain('outputTokenSpeed');
		expect(responseMessage).toContain("{$i18n.t('Output speed')}");
	});
});
