export const isModelInUsagePool = (usagePool: string[] | null | undefined, modelId: string) => {
	return Array.isArray(usagePool) && modelId !== '' && usagePool.includes(modelId);
};
