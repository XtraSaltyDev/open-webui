<script lang="ts">
	import { onMount, getContext, createEventDispatcher } from 'svelte';
	import { fade } from 'svelte/transition';

	const dispatch = createEventDispatcher();

	import { getChatList } from '$lib/apis/chats';
	import {
		config,
		type Model,
		user,
		models as _models,
		temporaryChatEnabled,
		selectedFolder,
		chats,
		currentChatPage
	} from '$lib/stores';
	import Suggestions from './Suggestions.svelte';
	import Tooltip from '$lib/components/common/Tooltip.svelte';
	import EyeSlash from '$lib/components/icons/EyeSlash.svelte';
	import MessageInput from './MessageInput.svelte';
	import ModelSelector from './ModelSelector.svelte';
	import FolderPlaceholder from './Placeholder/FolderPlaceholder.svelte';
	import FolderTitle from './Placeholder/FolderTitle.svelte';
	import { getDaylightGreeting } from './daylight';

	const i18n = getContext('i18n');

	export let createMessagePair: Function;
	export let stopResponse: Function;

	export let autoScroll = false;

	export let atSelectedModel: Model | undefined;
	export let selectedModels: [''];

	export let history;

	export let prompt = '';
	export let files = [];
	export let messageInput = null;

	export let selectedToolIds = [];
	export let selectedSkillIds = [];
	export let selectedFilterIds = [];
	export let pendingOAuthTools = [];

	export let showCommands = false;

	export let imageGenerationEnabled = false;
	export let codeInterpreterEnabled = false;
	export let webSearchEnabled = false;

	export let onUpload: Function = (e) => {};
	export let onSelect = (e) => {};
	export let onChange = (e) => {};

	export let dragged = false;

	let models = [];
	let selectedModelIdx = 0;
	let greeting = getDaylightGreeting();

	$: models = selectedModels.map((id) => $_models.find((m) => m.id === id));
	$: if (models.length > 0 && selectedModelIdx > models.length - 1) {
		selectedModelIdx = models.length - 1;
	}

	onMount(() => {
		greeting = getDaylightGreeting();
	});
</script>

<div class="m-auto w-full max-w-[680px] px-[22px] md:px-4 py-0 text-center md:py-16">
	{#if $temporaryChatEnabled}
		<Tooltip
			content={$i18n.t("This chat won't appear in history and your messages will not be saved.")}
			className="w-full flex justify-center mb-0.5"
			placement="top"
		>
			<div class="flex items-center gap-2 text-gray-500 text-base my-2 w-fit">
				<EyeSlash strokeWidth="2.5" className="size-4" />{$i18n.t('Temporary Chat')}
			</div>
		</Tooltip>
	{/if}

	<div class="w-full text-center flex items-center gap-4 font-primary">
		<div class="w-full flex flex-col justify-center items-center">
			{#if $selectedFolder}
				<FolderTitle
					folder={$selectedFolder}
					onUpdate={async (folder) => {
						await chats.set(await getChatList(localStorage.token, $currentChatPage));
						currentChatPage.set(1);
					}}
					onDelete={async () => {
						await chats.set(await getChatList(localStorage.token, $currentChatPage));
						currentChatPage.set(1);

						selectedFolder.set(null);
					}}
				/>
			{:else}
				<div class="mb-[22px] md:mb-[26px]" in:fade={{ duration: 100 }}>
					<div
						class="font-secondary text-[34px] md:text-[clamp(2.5rem,8vw,46px)] leading-[1.08] md:leading-[1.05] tracking-[-0.01em] text-[#1a1a19] dark:text-[#f2f2ee]"
					>
						{greeting}, {$user?.name || $i18n.t('there')}
					</div>
				</div>

				<div
					class="mb-[18px] hidden justify-center md:flex"
					in:fade={{ duration: 100, delay: 50 }}
				>
					<div class="max-w-72">
						<ModelSelector bind:selectedModels showSetDefault={false} />
					</div>
				</div>
			{/if}

			<div class="text-base font-normal w-full {atSelectedModel ? 'mt-2' : ''}">
				<MessageInput
					bind:this={messageInput}
					{history}
					{selectedModels}
					bind:files
					bind:prompt
					bind:autoScroll
					bind:selectedToolIds
					bind:selectedSkillIds
					bind:selectedFilterIds
					bind:imageGenerationEnabled
					bind:codeInterpreterEnabled
					bind:webSearchEnabled
					bind:atSelectedModel
					bind:showCommands
					bind:dragged
					{pendingOAuthTools}
					{stopResponse}
					{createMessagePair}
					placeholder={$i18n.t('What should we dig into?')}
					{onChange}
					{onUpload}
					on:submit={(e) => {
						dispatch('submit', e.detail);
					}}
				/>
			</div>
		</div>
	</div>

	{#if $selectedFolder}
		<div
			class="mx-auto px-4 md:max-w-3xl md:px-6 font-primary min-h-62"
			in:fade={{ duration: 200, delay: 200 }}
		>
			<FolderPlaceholder folder={$selectedFolder} />
		</div>
	{:else}
		<div
			class="mx-auto hidden w-full font-primary md:mt-[18px] md:block"
			in:fade={{ duration: 200, delay: 200 }}
		>
			<div>
				<Suggestions
					suggestionPrompts={atSelectedModel?.info?.meta?.suggestion_prompts ??
						models[selectedModelIdx]?.info?.meta?.suggestion_prompts ??
						$config?.default_prompt_suggestions ??
						[]}
					inputValue={prompt}
					{onSelect}
					className="hidden md:grid md:grid-cols-3 md:gap-3"
				/>
			</div>
		</div>
	{/if}
</div>
