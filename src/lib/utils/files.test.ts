import { describe, expect, test } from 'vitest';

import { isRasterImageContentType, isRasterImageFile } from './files';

describe('file type helpers', () => {
	test('treats common raster image content types as image inputs', () => {
		expect(isRasterImageContentType('image/png')).toBe(true);
		expect(isRasterImageContentType('image/jpeg; charset=binary')).toBe(true);
		expect(isRasterImageFile({ type: 'file', content_type: 'image/webp' })).toBe(true);
	});

	test('does not treat SVG as a raster vision image', () => {
		expect(isRasterImageContentType('image/svg+xml')).toBe(false);
		expect(isRasterImageFile({ type: 'image', content_type: 'image/svg+xml' })).toBe(false);
		expect(isRasterImageFile({ type: 'file', content_type: 'image/svg+xml' })).toBe(false);
	});

	test('keeps legacy image file objects working when content type is missing', () => {
		expect(isRasterImageFile({ type: 'image' })).toBe(true);
		expect(isRasterImageFile({ type: 'file' })).toBe(false);
	});
});
