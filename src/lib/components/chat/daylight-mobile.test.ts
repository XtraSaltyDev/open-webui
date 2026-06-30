import { describe, expect, test } from 'vitest';
import { readFileSync } from 'node:fs';

const readComponent = (path: string) => readFileSync(new URL(path, import.meta.url), 'utf-8');

describe('Daylight mobile handoff markup contract', () => {
	test('uses the compact mobile landing layout and hides starter suggestions below md', () => {
		const placeholder = readComponent('./Placeholder.svelte');

		expect(placeholder).toContain('text-[34px] md:text-[clamp(2.5rem,8vw,46px)]');
		expect(placeholder).toContain('px-[22px] md:px-4');
		expect(placeholder).toContain('className="hidden md:grid md:grid-cols-3 md:gap-3"');
	});

	test('keeps composer labels accessible but visually hides them on mobile', () => {
		const messageInput = readComponent('./MessageInput.svelte');

		expect(messageInput).toContain('size-9 md:size-auto');
		expect(messageInput).toContain(`<span class="hidden md:inline">{$i18n.t('Attach')}</span>`);
		expect(messageInput).toContain(`<span class="hidden md:inline">{$i18n.t('Web search')}</span>`);
		expect(messageInput).toContain(`<span class="hidden md:inline">{$i18n.t('Tools')}</span>`);
	});

	test('uses mobile-only top-bar actions instead of the desktop avatar controls', () => {
		const navbar = readComponent('./Navbar.svelte');

		expect(navbar).toContain('md:hidden');
		expect(navbar).toContain(`aria-label={$i18n.t('Open Sidebar')}`);
		expect(navbar).toContain('PencilSquare');
		expect(navbar).toContain(
			`{chat?.id ? 'border-b border-black/[0.06] dark:border-white/[0.06]' : 'border-b-0'}`
		);
		expect(navbar).toContain('{#if !$mobile && $user !== undefined && $user !== null}');
	});
});
