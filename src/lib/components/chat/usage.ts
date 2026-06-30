export const isModelInUsagePool = (
	usagePool: string[] | null | undefined,
	modelIds: string | Array<string | null | undefined>
) => {
	const candidates = (Array.isArray(modelIds) ? modelIds : [modelIds]).filter(
		(modelId): modelId is string => typeof modelId === 'string' && modelId !== ''
	);

	return Array.isArray(usagePool) && candidates.some((modelId) => usagePool.includes(modelId));
};
