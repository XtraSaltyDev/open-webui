export type ResponseUsage = Record<string, unknown> | null | undefined;

const explicitSpeedFields = [
	'output_tokens_per_second',
	'completion_tokens_per_second',
	'response_token/s',
	'output_token/s',
	'completion_token/s',
	'tokens_per_second'
];

const outputTokenFields = ['completion_tokens', 'output_tokens', 'generated_tokens', 'eval_count'];

const durationSecondsFields = [
	'response_duration_seconds',
	'output_duration_seconds',
	'completion_duration_seconds',
	'generation_duration_seconds'
];

const durationMillisecondsFields = [
	'response_duration_ms',
	'output_duration_ms',
	'completion_duration_ms',
	'generation_duration_ms'
];

const durationNanosecondsFields = [
	'eval_duration',
	'response_duration_ns',
	'output_duration_ns',
	'completion_duration_ns',
	'generation_duration_ns'
];

const numberFormatter = new Intl.NumberFormat('en-US', {
	maximumFractionDigits: 2
});

const getFiniteNumber = (value: unknown) => {
	if (typeof value === 'number') {
		return Number.isFinite(value) ? value : null;
	}

	if (typeof value === 'string' && value.trim() !== '') {
		const parsed = Number(value);
		return Number.isFinite(parsed) ? parsed : null;
	}

	return null;
};

const getFirstPositiveNumber = (usage: ResponseUsage, fields: string[]) => {
	if (!usage) {
		return null;
	}

	for (const field of fields) {
		const value = getFiniteNumber(usage[field]);
		if (value !== null && value > 0) {
			return value;
		}
	}

	return null;
};

const getOutputTokens = (usage: ResponseUsage) => getFirstPositiveNumber(usage, outputTokenFields);

const getDurationSeconds = (usage: ResponseUsage) => {
	const seconds = getFirstPositiveNumber(usage, durationSecondsFields);
	if (seconds !== null) {
		return seconds;
	}

	const milliseconds = getFirstPositiveNumber(usage, durationMillisecondsFields);
	if (milliseconds !== null) {
		return milliseconds / 1000;
	}

	const nanoseconds = getFirstPositiveNumber(usage, durationNanosecondsFields);
	if (nanoseconds !== null) {
		return nanoseconds / 1_000_000_000;
	}

	return null;
};

const getOutputTokenSpeed = (usage: ResponseUsage) => {
	const explicitSpeed = getFirstPositiveNumber(usage, explicitSpeedFields);
	if (explicitSpeed !== null) {
		return explicitSpeed;
	}

	const outputTokens = getOutputTokens(usage);
	const durationSeconds = getDurationSeconds(usage);

	if (outputTokens === null || durationSeconds === null) {
		return null;
	}

	const speed = outputTokens / durationSeconds;
	return Number.isFinite(speed) && speed > 0 ? speed : null;
};

export const formatOutputTokenSpeed = (usage: ResponseUsage) => {
	const speed = getOutputTokenSpeed(usage);
	if (speed === null) {
		return null;
	}

	return `${numberFormatter.format(speed)} tok/s`;
};

export const withOutputTokenSpeed = (usage: ResponseUsage, elapsedMs: number) => {
	if (!usage) {
		return usage;
	}

	if (getFirstPositiveNumber(usage, explicitSpeedFields) !== null) {
		return usage;
	}

	const outputTokens = getOutputTokens(usage);
	if (outputTokens === null || elapsedMs <= 0) {
		return usage;
	}

	const outputTokensPerSecond = outputTokens / (elapsedMs / 1000);
	if (!Number.isFinite(outputTokensPerSecond) || outputTokensPerSecond <= 0) {
		return usage;
	}

	return {
		...usage,
		output_tokens_per_second: Math.round(outputTokensPerSecond * 100) / 100
	};
};
