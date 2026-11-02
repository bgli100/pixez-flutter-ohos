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

#pragma once

#include <vector>

#include <algorithm>
#include <atomic>
#include <thread>

#include "BaseGifEncoder.h"

struct FrameInfo
{
	uint32_t* pixels;
	int32_t delayMs;
};

class GCTGifEncoder : public BaseGifEncoder
{
	static const int32_t MAX_STACK_SIZE = 4096;
	static const int32_t BYTE_NUM = 256;
	static const int R_RANGE = 6;
	static const int G_RANGE = 7;
	static const int B_RANGE = 6;

	uint32_t* lastPixels;
	std::vector<FrameInfo*> images;

	void buildColorTable(Cube cubes[256]);
	void removeSamePixels(uint8_t* src1, uint8_t* src2, EncodeRect* rect);
	void MapColors(const ColorTree& tree, Cube* cubes);
	// Builds the complete byte block (extensions + descriptor + LZW data) of one
	// frame, so frames can be compressed concurrently and written in order.
	void BuildFrameBlock(size_t index, std::vector<uint8_t>& out);

	void writeHeader(Cube* cubes);
	bool writeLSD();
	void writeGCT(Cube* cubes);
	bool writeContents(std::vector<uint8_t>& out, uint8_t* pixels, uint16_t delay, const EncodeRect& encodingRect);
	bool writeNetscapeExt(std::vector<uint8_t>& out);
	bool writeGraphicControlExt(std::vector<uint8_t>& out, uint16_t delay);
	bool writeFrame(std::vector<uint8_t>& out, uint8_t* pixels, const EncodeRect& encodingRect);
	bool writeLCT(int32_t colorNum, Cube* cubes);
	bool writeBitmapData(std::vector<uint8_t>& out, uint8_t* pixels, const EncodeRect& encodingRect);
public:
	GCTGifEncoder();
	virtual ~GCTGifEncoder();

	virtual bool init(uint16_t width, uint16_t height, const char* fileName);
	virtual void release();
	virtual void setDither(bool useDither);
	virtual uint16_t getWidth();
	virtual uint16_t getHeight();
	virtual void setThreadCount(int32_t threadCount);

	virtual void encodeFrame(uint32_t* pixels, int32_t delayMs);
	// Takes over `pixels` (allocated with new[]) instead of copying it.
	void encodeFrameOwned(uint32_t* pixels, int32_t delayMs);
};