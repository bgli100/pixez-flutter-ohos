/*
 * Copyright (c) 2015 waynejo
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy of
 * this software and associated documentation files (the "Software"), to deal in
 * the Software without restriction, including without limitation the rights to
 * use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
 * the Software, and to permit persons to whom the Software is furnished to do so,
 * subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
 * FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
 * COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
 * IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
 * CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 */

#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <vector>
#include "BaseGifEncoder.h"
#include "GCTGifEncoder.h"
#include "BitWritingBlock.h"

using namespace std;

namespace {

constexpr unsigned MAX_WORKERS = 6;

void AppendUint16(std::vector<uint8_t>& out, uint16_t value)
{
	out.push_back(static_cast<uint8_t>(value & 0xFF));
	out.push_back(static_cast<uint8_t>(value >> 8));
}

// Frames are independent for both colour mapping and LZW, so both phases fan out
// over the same worker pool and stay in order through the task index.
template <typename Task>
void ParallelFor(size_t count, Task task)
{
	if (count == 0) {
		return;
	}
	unsigned workerCount = std::thread::hardware_concurrency();
	workerCount = workerCount == 0 ? 1u : std::min(workerCount, MAX_WORKERS);
	workerCount = std::min<unsigned>(workerCount, static_cast<unsigned>(count));
	if (workerCount <= 1) {
		for (size_t index = 0; index < count; ++index) {
			task(index);
		}
		return;
	}
	std::atomic<size_t> next(0);
	std::vector<std::thread> workers;
	workers.reserve(workerCount);
	for (unsigned i = 0; i < workerCount; ++i) {
		workers.emplace_back([&next, count, &task]() {
			for (;;) {
				const size_t index = next.fetch_add(1);
				if (index >= count) {
					return;
				}
				task(index);
			}
		});
	}
	for (std::thread& worker : workers) {
		worker.join();
	}
}

} // namespace

GCTGifEncoder::GCTGifEncoder() {
	// init width, height to 1, to prevent divide by zero.
	width = 1;
	height = 1;

	useDither = true;
	frameNum = 0;
	lastPixels = NULL;
	lastColorReducedPixels = NULL;
	fp = NULL;
	lastRootColor = GREEN;
}

GCTGifEncoder::~GCTGifEncoder() {
	release();
}

bool GCTGifEncoder::init(uint16_t width, uint16_t height, const char* fileName) {
	this->width = width;
	this->height = height;

	fp = fopen(fileName, "wb");
	if (NULL == fp) {
		return false;
	}
	if (NULL != lastPixels) {
		delete[] lastPixels;
	}
	lastPixels = new uint32_t[width * height];
	if (NULL != lastColorReducedPixels) {
		delete[] lastColorReducedPixels;
	}
	lastColorReducedPixels = new uint32_t[width * height];

	return true;
}

void GCTGifEncoder::release() {
	if (NULL == fp || images.empty()) {
		// init() never opened the file or nothing was buffered: only clean up so
		// that neither a null FILE* fwrite nor an empty histogram can be reached.
		for (std::vector<FrameInfo*>::iterator i = images.begin(); i != images.end(); ++i) {
			delete[] (*i)->pixels;
			delete (*i);
		}
		images.clear();
		if (NULL != lastPixels) {
			delete[] lastPixels;
			lastPixels = NULL;
		}
		if (NULL != lastColorReducedPixels) {
			delete[] lastColorReducedPixels;
			lastColorReducedPixels = NULL;
		}
		if (NULL != fp) {
			fclose(fp);
			fp = NULL;
		}
		return;
	}

	Cube cubes[256] = {0, };
	buildColorTable(cubes);
	writeHeader(cubes);

	ColorTree tree;
	tree.Build(cubes, 255);
	MapColors(tree, cubes);

	// Compress every frame concurrently, then append the blocks in order: LZW is
	// per frame independent and was the remaining serial cost of the encode.
	const size_t frameCount = images.size();
	std::vector<std::vector<uint8_t>> blocks(frameCount);
	ParallelFor(frameCount, [this, &blocks](size_t index) {
		BuildFrameBlock(index, blocks[index]);
	});
	for (size_t index = 0; index < frameCount; ++index) {
		if (!blocks[index].empty()) {
			fwrite(blocks[index].data(), 1, blocks[index].size(), fp);
		}
		++frameNum;
		delete[] images[index]->pixels;
		delete images[index];
	}
	images.clear();

	if (NULL != lastPixels) {
		delete[] lastPixels;
		lastPixels = NULL;
	}

	if (NULL != lastColorReducedPixels) {
		delete[] lastColorReducedPixels;
		lastColorReducedPixels = NULL;
	}

	if (NULL != fp) {
		uint8_t gifFileTerminator = 0x3B;
		fwrite(&gifFileTerminator, 1, 1, fp);
		fclose(fp);
		fp = NULL;
	}
}

void GCTGifEncoder::BuildFrameBlock(size_t index, std::vector<uint8_t>& out)
{
	EncodeRect imageRect;
	imageRect.x = 0;
	imageRect.y = 0;
	imageRect.width = width;
	imageRect.height = height;
	writeContents(out, (uint8_t*)images[index]->pixels, images[index]->delayMs / 10, imageRect);
}

void GCTGifEncoder::MapColors(const ColorTree& tree, Cube* cubes)
{
	ParallelFor(images.size(), [this, &tree, cubes](size_t index) {
		reduceColor(&tree, cubes, images[index]->pixels, NULL);
	});
}

void GCTGifEncoder::setDither(bool useDither) {
	this->useDither = useDither;
}

uint16_t GCTGifEncoder::getWidth() {
	return width;
}

uint16_t GCTGifEncoder::getHeight() {
	return height;
}

void GCTGifEncoder::setThreadCount(int32_t threadCount) { }

void GCTGifEncoder::buildColorTable(Cube cubes[256]) {
	uint32_t pixelNum = width * height * images.size();
	uint32_t* allPixels = new uint32_t[pixelNum];

	int32_t idx = 0;
	for (std::vector<FrameInfo*>::iterator i = images.begin(); i != images.end(); ++i, ++idx) {
		memcpy(allPixels + width * height * idx, (*i)->pixels, width * height * sizeof(allPixels[0]));
	}

	computeColorTable(allPixels, cubes, pixelNum, true);

	delete[] allPixels;
}

void GCTGifEncoder::removeSamePixels(uint8_t* src1, uint8_t* src2, EncodeRect* rect)
{
	int32_t bytesPerLine = width * 4;
	int32_t beginY = 0;
	for (; beginY < height - 1; ++beginY) {
		if (0 != memcmp(src1 + bytesPerLine * beginY, src2 + bytesPerLine * beginY, bytesPerLine)) {
			break;
		}
	}
	int32_t endY = height - 1;
	for (; beginY + 1 <= endY; --endY) {
		if (0 != memcmp(src1 + bytesPerLine * endY, src2 + bytesPerLine * endY, bytesPerLine)) {
			break;
		}
	}
	++endY;

	int32_t lastY = width * height;
	bool isSame = true;
	int32_t beginX = 0;
	for (; beginX < width - 1 && isSame; ++beginX) {
		isSame = true;
		for (int32_t y = 0; y < lastY; y += width) {
			if (((uint32_t*)src1)[y + beginX] != ((uint32_t*)src2)[y + beginX]) {
				isSame = false;
				break;
			}
		}
	}
	--beginX;
	isSame = true;
	int32_t endX = width - 1;
	for (; beginX + 1 <= endX && isSame; --endX) {
		isSame = true;
		for (int32_t y = 0; y < lastY; y += width) {
			if (((uint32_t*)src1)[y + endX] != ((uint32_t*)src2)[y + endX]) {
				isSame = false;
				break;
			}
		}
	}
	++endX;

	rect->x = beginX;
	rect->y = beginY;
	rect->width = endX - beginX + 1;
	rect->height = endY - beginY;
}

void GCTGifEncoder::writeHeader(Cube* cubes)
{
	fwrite("GIF89a", 6, 1, fp);
	writeLSD();
	writeGCT(cubes);
}

bool GCTGifEncoder::writeLSD()
{
	// logical screen size
	fwrite(&width, 2, 1, fp);
	fwrite(&height, 2, 1, fp);

	// packed fields
	uint8_t gctFlag = 1; // 1 : global color table flag
	uint8_t colorResolution = 8; // only 8 bit
	uint8_t oderedFlag = 0;
	uint8_t gctSize = 7;
	uint8_t packed = (gctFlag << 7) | ((colorResolution - 1) << 4) | (oderedFlag << 3) | gctSize;
	fwrite(&packed, 1, 1, fp);

	uint8_t backgroundColorIndex = 0xFF;
	fwrite(&backgroundColorIndex, 1, 1, fp);

	uint8_t aspectRatio = 0;
	fwrite(&aspectRatio, 1, 1, fp);

	return true;
}

void GCTGifEncoder::writeGCT(Cube* cubes)  {
	uint8_t colorTable[256][3];
	for (int32_t idx = 0; idx < 256; ++idx, ++cubes) {
		colorTable[idx][0] = cubes->color[0];
		colorTable[idx][1] = cubes->color[1];
		colorTable[idx][2] = cubes->color[2];
	}
	fwrite(colorTable, 256 * 3, 1, fp);
}

bool GCTGifEncoder::writeContents(std::vector<uint8_t>& out, uint8_t* pixels, uint16_t delay, const EncodeRect& encodingRect)
{
	writeNetscapeExt(out);

	writeGraphicControlExt(out, delay);
	writeFrame(out, pixels, encodingRect);

	return true;
}

bool GCTGifEncoder::writeNetscapeExt(std::vector<uint8_t>& out)
{
	//                                   code extCode,                                                            size,       loop count, end
	const uint8_t netscapeExt[] = {0x21, 0xFF, 0x0B, 'N', 'E', 'T', 'S', 'C', 'A', 'P', 'E', '2', '.', '0', 0x03, 0x01, 0x00, 0x00, 0x00};
	out.insert(out.end(), netscapeExt, netscapeExt + sizeof(netscapeExt));
	return true;
}

bool GCTGifEncoder::writeGraphicControlExt(std::vector<uint8_t>& out, uint16_t delay)
{
	uint8_t disposalMethod = 2; // dispose
	uint8_t userInputFlag = 0; // User input is not expected.
	uint8_t transparencyFlag = 1; // Transparent Index is given.

	uint8_t packed = (disposalMethod << 2) | (userInputFlag << 1) | transparencyFlag;
	//                                                     size, packed, delay(2), transIndex, terminator
	const uint8_t graphicControlExt[] = {0x21, 0xF9, 0x04, packed, (uint8_t)(delay & 0xFF), (uint8_t)(delay >> 8), 0xFF, 0x00};
	out.insert(out.end(), graphicControlExt, graphicControlExt + sizeof(graphicControlExt));
	return true;
}

bool GCTGifEncoder::writeFrame(std::vector<uint8_t>& out, uint8_t* pixels, const EncodeRect& encodingRect)
{
	uint8_t code = 0x2C;
	out.push_back(code);
	uint16_t ix = encodingRect.x;
	uint16_t iy = encodingRect.y;
	uint16_t iw = encodingRect.width;
	uint16_t ih = encodingRect.height;
	uint8_t localColorTableFlag = 0;
	uint8_t interlaceFlag = 0;
	uint8_t sortFlag = 0;
	uint8_t sizeOfLocalColorTable = 7;
	uint8_t packed = (localColorTableFlag << 7) | (interlaceFlag << 6) | (sortFlag << 5) | sizeOfLocalColorTable;
	AppendUint16(out, ix);
	AppendUint16(out, iy);
	AppendUint16(out, iw);
	AppendUint16(out, ih);
	out.push_back(packed);

	writeBitmapData(out, pixels, encodingRect);
	return true;
}

bool GCTGifEncoder::writeLCT(int32_t colorNum, Cube* cubes)
{
	uint32_t color;
	Cube* cube;
	for (int32_t i = 0; i < colorNum; ++i) {
		cube = cubes + i;
		color = cube->color[RED] | (cube->color[GREEN] << 8) | (cube->color[BLUE] << 16);
		fwrite(&color, 3, 1, fp);
	}
	return true;
}

bool GCTGifEncoder::writeBitmapData(std::vector<uint8_t>& out, uint8_t* pixels, const EncodeRect& encodingRect)
{
	uint32_t pixelNum = width * height;
	uint8_t* endPixels = pixels + (encodingRect.y + encodingRect.height - 1) * width + encodingRect.x + encodingRect.width;
	uint8_t dataSize = 8;
	uint32_t codeSize = dataSize + 1;
	uint32_t codeMask = (1 << codeSize) - 1;
	BitWritingBlock writingBlock;
	out.push_back(dataSize);

	vector<uint16_t> lzwInfoHolder;
	lzwInfoHolder.resize(MAX_STACK_SIZE * BYTE_NUM);
	uint16_t* lzwInfos = &lzwInfoHolder[0];

	pixels = pixels + width * encodingRect.y + encodingRect.x;
	uint8_t* rowStart = pixels;
	uint32_t clearCode = 1 << dataSize;
	writingBlock.writeBits(clearCode, codeSize);
	uint32_t infoNum = clearCode + 2;
	uint16_t current = *pixels;
	uint8_t endOfImageData = 0;

	++pixels;
	if (encodingRect.width <= pixels - rowStart) {
		rowStart = rowStart + width;
		pixels = rowStart;
	}

	uint16_t* next;
	while (endPixels > pixels) {
		next = &lzwInfos[current * BYTE_NUM + *pixels];
		if (0 == *next || *next >= MAX_STACK_SIZE) {
			writingBlock.writeBits(current, codeSize);

			*next = infoNum;
			if (infoNum < MAX_STACK_SIZE) {
				++infoNum;
			} else {
				writingBlock.writeBits(clearCode, codeSize);
				infoNum = clearCode + 2;
				codeSize = dataSize + 1;
				codeMask = (1 << codeSize) - 1;
				memset(lzwInfos, 0, MAX_STACK_SIZE * BYTE_NUM * sizeof(uint16_t));
			}
			if (codeMask < infoNum - 1 && infoNum < MAX_STACK_SIZE) {
				++codeSize;
				codeMask = (1 << codeSize) - 1;
			}
			if (endPixels <= pixels) {
				break;
			}
			current = *pixels;
		} else {
			current = *next;
		}
		++pixels;
		if (encodingRect.width <= pixels - rowStart) {
			rowStart = rowStart + width;
			pixels = rowStart;
		}
	}
	writingBlock.writeBits(current, codeSize);
	writingBlock.toBuffer(out);
	out.push_back(endOfImageData);

	return true;
}

void GCTGifEncoder::encodeFrame(uint32_t* pixels, int32_t delayMs) {
	FrameInfo* frameInfo = new FrameInfo();
	frameInfo->delayMs = delayMs;
	frameInfo->pixels = new uint32_t[width * height];
	memcpy(frameInfo->pixels, pixels, width * height * sizeof(uint32_t));
	images.push_back(frameInfo);
}

void GCTGifEncoder::encodeFrameOwned(uint32_t* pixels, int32_t delayMs) {
	FrameInfo* frameInfo = new FrameInfo();
	frameInfo->delayMs = delayMs;
	frameInfo->pixels = pixels;
	images.push_back(frameInfo);
}
