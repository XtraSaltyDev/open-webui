export type ChatFileLike = {
	type?: string | null;
	content_type?: string | null;
};

const rasterImageContentTypes = new Set([
	'image/apng',
	'image/avif',
	'image/bmp',
	'image/gif',
	'image/heic',
	'image/heif',
	'image/jpeg',
	'image/jpg',
	'image/png',
	'image/tiff',
	'image/webp'
]);

export const normalizeContentType = (contentType: string | null | undefined) =>
	(contentType ?? '').split(';')[0].trim().toLowerCase();

export const isRasterImageContentType = (contentType: string | null | undefined) =>
	rasterImageContentTypes.has(normalizeContentType(contentType));

export const isRasterImageFile = (file: ChatFileLike | null | undefined) => {
	if (!file) {
		return false;
	}

	const contentType = normalizeContentType(file.content_type);

	if (contentType) {
		return isRasterImageContentType(contentType);
	}

	return file.type === 'image';
};
