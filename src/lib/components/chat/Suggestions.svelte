<script lang="ts">
	import Fuse from 'fuse.js';
	import { getContext } from 'svelte';
	import { settings, WEBUI_NAME } from '$lib/stores';
	import { WEBUI_VERSION } from '$lib/constants';
	import Code from '$lib/components/icons/Code.svelte';
	import BookOpen from '$lib/components/icons/BookOpen.svelte';
	import Sparkles from '$lib/components/icons/Sparkles.svelte';

	const i18n = getContext('i18n');

	export let suggestionPrompts = [];
	export let className = '';
	export let inputValue = '';
	export let onSelect = (e) => {};

	let sortedPrompts = [];

	const fuseOptions = {
		keys: ['content', 'title'],
		threshold: 0.5
	};

	let fuse;
	let filteredPrompts = [];

	// Initialize Fuse
	$: fuse = new Fuse(sortedPrompts, fuseOptions);

	// Update the filteredPrompts if inputValue changes
	// Only increase version if something wirklich geändert hat
	$: getFilteredPrompts(inputValue);

	const getPromptSignature = (prompt) =>
		JSON.stringify({
			id: prompt.id ?? null,
			content: prompt.content ?? '',
			title: prompt.title ?? null
		});

	// Helper function to check if arrays are the same
	function arraysEqual(a, b) {
		if (a.length !== b.length) return false;
		for (let i = 0; i < a.length; i++) {
			if (getPromptSignature(a[i]) !== getPromptSignature(b[i])) {
				return false;
			}
		}
		return true;
	}

	const getFilteredPrompts = (inputValue) => {
		if (inputValue.length > 500) {
			filteredPrompts = [];
		} else {
			const newFilteredPrompts =
				inputValue.trim() && fuse
					? fuse.search(inputValue.trim()).map((result) => result.item)
					: sortedPrompts;

			// Compare with the oldFilteredPrompts
			// If there's a difference, update array + version
			if (!arraysEqual(filteredPrompts, newFilteredPrompts)) {
				filteredPrompts = newFilteredPrompts;
			}
		}
	};

	$: if (suggestionPrompts) {
		const orderedPrompts = [...(suggestionPrompts ?? [])];
		if (!arraysEqual(sortedPrompts, orderedPrompts)) {
			sortedPrompts = orderedPrompts;
		}
		getFilteredPrompts(inputValue);
	}

	const getPromptTitle = (prompt) => {
		return prompt.title?.[0] || prompt.content;
	};

	const getPromptSubtitle = (prompt) => {
		return prompt.title?.[1] || $i18n.t('Prompt');
	};
</script>

{#if filteredPrompts.length > 0}
	<div role="list" class={className}>
		{#each filteredPrompts.slice(0, 3) as prompt, idx (prompt.id || `${prompt.content}-${idx}`)}
			<!-- svelte-ignore a11y-no-interactive-element-to-noninteractive-role -->
			<button
				role="listitem"
				class="waterfall group flex min-h-[112px] flex-col rounded-2xl border border-black/[0.09] bg-[#faf9f6] px-[15px] py-3.5 text-left transition duration-150 hover:-translate-y-0.5 hover:shadow-[0_10px_22px_-14px_rgba(0,0,0,0.3)] dark:border-white/[0.08] dark:bg-[#171715]/50 dark:hover:bg-[#1d1d1b]"
				style="animation-delay: {idx * 60}ms"
				on:click={() => onSelect({ type: 'prompt', data: prompt.content })}
			>
				<div class="text-daylight-accent dark:text-daylight-accent-dark">
					{#if idx === 0}
						<Code className="size-[18px]" strokeWidth="1.7" />
					{:else if idx === 1}
						<BookOpen className="size-[18px]" strokeWidth="1.7" />
					{:else}
						<Sparkles className="size-[18px]" strokeWidth="1.7" />
					{/if}
				</div>
				<div
					class="mt-2.5 line-clamp-2 text-sm font-semibold text-[#1a1a19] transition dark:text-[#f2f2ee]"
				>
					{getPromptTitle(prompt)}
				</div>
				<div
					class="mt-0.5 line-clamp-2 text-[12.5px] font-normal text-[#8a8a84] dark:text-[#7a7a74]"
				>
					{getPromptSubtitle(prompt)}
				</div>
			</button>
		{/each}
	</div>
{:else}
	<div class="h-20 w-full">
		<div
			class="flex w-full {$settings?.landingPageMode === 'chat'
				? ' -mt-1'
				: 'text-center items-center justify-center'}  self-start text-gray-600 dark:text-gray-400"
		>
			{$WEBUI_NAME} ‧ v{WEBUI_VERSION}
		</div>
	</div>
{/if}

<style>
	/* Waterfall animation for the suggestions */
	@keyframes fadeInUp {
		0% {
			opacity: 0;
			transform: translateY(20px);
		}
		100% {
			opacity: 1;
			transform: translateY(0);
		}
	}

	.waterfall {
		opacity: 0;
		animation-name: fadeInUp;
		animation-duration: 200ms;
		animation-fill-mode: forwards;
		animation-timing-function: ease;
	}
</style>
