type ModelLike = {
	id?: string;
	info?: {
		meta?: {
			hidden?: boolean;
		};
	};
};

export const getDefaultModelIds = (defaultModels: string | null | undefined): string[] => {
	return (defaultModels ?? '')
		.split(',')
		.map((modelId) => modelId.trim())
		.filter(Boolean);
};

export const resolveAvailableModelIds = (
	selectedModelIds: Array<string | null | undefined> | null | undefined,
	models: ModelLike[],
	defaultModelIds: Array<string | null | undefined> = []
): string[] => {
	const availableModelIds = models
		.filter((model) => model?.id && !(model?.info?.meta?.hidden ?? false))
		.map((model) => model.id as string);
	const availableModelIdSet = new Set(availableModelIds);

	const validSelectedModelIds = (selectedModelIds ?? []).filter(
		(modelId): modelId is string => typeof modelId === 'string' && availableModelIdSet.has(modelId)
	);

	if (validSelectedModelIds.length > 0) {
		return [...new Set(validSelectedModelIds)];
	}

	const validDefaultModelIds = defaultModelIds.filter(
		(modelId): modelId is string => typeof modelId === 'string' && availableModelIdSet.has(modelId)
	);

	if (validDefaultModelIds.length > 0) {
		return [...new Set(validDefaultModelIds)];
	}

	return availableModelIds.length > 0 ? [availableModelIds[0]] : [''];
};
