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

#include <stdint.h>
#include <stdio.h>

#include <vector>

struct EncodeRect {
	int32_t x;
	int32_t y;
	int32_t width;
	int32_t height;
};

enum COLOR {
	RED = 0,
	GREEN,
	BLUE,
	COLOR_MAX
};

struct Cube {
	static const int COLOR_RANGE = 256;

	uint32_t cMin[COLOR_MAX];
	uint32_t cMax[COLOR_MAX];
	uint32_t colorHistogramFromIndex;
	uint32_t colorHistogramToIndex;
	uint32_t color[COLOR_MAX];
};

#define GET_COLOR(color, colorIdx) (((color) >> ((colorIdx) << 3)) & 0xFF)
#define ABS(v) (0 > (v) ? -(v) : (v))
#define ABS_DIFF(a, b) ((a) > (b) ? (a) - (b) : (b) - (a))
#define MAX(x, y) (((x) > (y)) ? (x) : (y))
#define MIN(x, y) (((x) < (y)) ? (x) : (y))

// k-d tree over the palette. The original implementation picked the closest
// colour with a linear scan over all 255 cubes for every pixel, which dominated
// the encode time (43M pixels * 255 cubes for a 30 frame 1200x1200 animation).
// The tree returns exactly the same cube index: equal distances still resolve to
// the lowest index, matching the "first minimum wins" behaviour of the scan.
class ColorTree {
	struct Node {
		int32_t cubeIndex;
		int32_t left;
		int32_t right;
		uint8_t axis;
	};

	const Cube* cubes_;
	std::vector<Node> nodes_;
	int32_t root_;

	int32_t BuildNode(std::vector<int32_t>& order, size_t begin, size_t end);
	void Search(int32_t node, int32_t r, int32_t g, int32_t b,
	            int32_t* bestIndex, uint32_t* bestDistance) const;

public:
	ColorTree();

	void Build(const Cube* cubes, uint32_t count);
	bool empty() const { return root_ < 0; }
	uint32_t Nearest(uint32_t r, uint32_t g, uint32_t b) const;
};

class BaseGifEncoder
{
protected:
	uint16_t width;
	uint16_t height;
	int32_t frameNum;
	uint32_t* lastColorReducedPixels;
	uint32_t lastRootColor;
	bool useDither;
	uint32_t* lastPixels;

	FILE* fp;

	void SortRangeByChannel(uint32_t* imageColorHistogram, int32_t maxColor, uint32_t from, uint32_t to);
	void updateColorHistogram(Cube* nextCube, Cube* maxCube, int32_t maxColor, uint32_t* imageColorHistogram);
	// pixelsAreScratch: the caller owns `pixels` and does not need it afterwards,
	// so the histogram stage can sort it in place instead of copying it again.
	void computeColorTable(uint32_t* pixels, Cube* cubes, uint32_t pixelNum, bool pixelsAreScratch = false);
	// reducedOut may be null: the GCT path never reads the colour-reduced copy back.
	void reduceColor(const ColorTree* tree, Cube* cubes, uint32_t* pixels, uint32_t* reducedOut);
public:
	BaseGifEncoder();
	virtual ~BaseGifEncoder() {}

	virtual bool init(uint16_t width, uint16_t height, const char* fileName) = 0;
	virtual void release() = 0;
	virtual void setDither(bool useDither) = 0;
	virtual uint16_t getWidth() = 0;
	virtual uint16_t getHeight() = 0;
	virtual void setThreadCount(int32_t threadCount) = 0;

	virtual void encodeFrame(uint32_t* pixels, int32_t delayMs) = 0;
};