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
#include <algorithm>
#include "BaseGifEncoder.h"

using namespace std;

ColorTree::ColorTree() : cubes_(NULL), root_(-1)
{
}

void ColorTree::Build(const Cube* cubes, uint32_t count)
{
	cubes_ = cubes;
	nodes_.clear();
	root_ = -1;
	if (cubes == NULL || count == 0) {
		return;
	}
	vector<int32_t> order(count);
	for (uint32_t i = 0; i < count; ++i) {
		order[i] = static_cast<int32_t>(i);
	}
	nodes_.reserve(count);
	root_ = BuildNode(order, 0, count);
}

int32_t ColorTree::BuildNode(vector<int32_t>& order, size_t begin, size_t end)
{
	if (begin >= end) {
		return -1;
	}
	// Split on the channel with the widest spread in this subset.
	uint32_t widest = 0;
	int axis = RED;
	for (int color = 0; color < COLOR_MAX; ++color) {
		uint32_t low = 255;
		uint32_t high = 0;
		for (size_t i = begin; i < end; ++i) {
			const uint32_t value = cubes_[order[i]].color[color];
			low = value < low ? value : low;
			high = value > high ? value : high;
		}
		if (high - low > widest) {
			widest = high - low;
			axis = color;
		}
	}
	const size_t middle = begin + ((end - begin) >> 1);
	nth_element(order.begin() + begin, order.begin() + middle, order.begin() + end,
		[this, axis](int32_t left, int32_t right) {
			const uint32_t leftValue = cubes_[left].color[axis];
			const uint32_t rightValue = cubes_[right].color[axis];
			return leftValue < rightValue || (leftValue == rightValue && left < right);
		});

	const int32_t nodeIndex = static_cast<int32_t>(nodes_.size());
	Node node;
	node.cubeIndex = order[middle];
	node.left = -1;
	node.right = -1;
	node.axis = static_cast<uint8_t>(axis);
	nodes_.push_back(node);
	const int32_t left = BuildNode(order, begin, middle);
	const int32_t right = BuildNode(order, middle + 1, end);
	nodes_[nodeIndex].left = left;
	nodes_[nodeIndex].right = right;
	return nodeIndex;
}

void ColorTree::Search(int32_t nodeIndex, int32_t r, int32_t g, int32_t b,
                       int32_t* bestIndex, uint32_t* bestDistance) const
{
	if (nodeIndex < 0) {
		return;
	}
	const Node& node = nodes_[nodeIndex];
	const Cube& cube = cubes_[node.cubeIndex];
	const int32_t diffR = static_cast<int32_t>(cube.color[RED]) - r;
	const int32_t diffG = static_cast<int32_t>(cube.color[GREEN]) - g;
	const int32_t diffB = static_cast<int32_t>(cube.color[BLUE]) - b;
	const uint32_t distance = static_cast<uint32_t>(diffR * diffR + diffG * diffG + diffB * diffB);
	if (distance < *bestDistance ||
		(distance == *bestDistance && node.cubeIndex < *bestIndex)) {
		*bestDistance = distance;
		*bestIndex = node.cubeIndex;
	}
	const int32_t values[COLOR_MAX] = {r, g, b};
	const int32_t delta = static_cast<int32_t>(cube.color[node.axis]) - values[node.axis];
	const int32_t nearSide = delta > 0 ? node.left : node.right;
	const int32_t farSide = delta > 0 ? node.right : node.left;
	Search(nearSide, r, g, b, bestIndex, bestDistance);
	// "==" matters: equidistant cubes on the far side must still be visited so
	// that the lowest index wins, exactly like the original linear scan.
	if (static_cast<uint32_t>(delta * delta) <= *bestDistance) {
		Search(farSide, r, g, b, bestIndex, bestDistance);
	}
}

uint32_t ColorTree::Nearest(uint32_t r, uint32_t g, uint32_t b) const
{
	if (root_ < 0) {
		return 0;
	}
	const Cube& first = cubes_[0];
	const int32_t diffR = static_cast<int32_t>(first.color[RED]) - static_cast<int32_t>(r);
	const int32_t diffG = static_cast<int32_t>(first.color[GREEN]) - static_cast<int32_t>(g);
	const int32_t diffB = static_cast<int32_t>(first.color[BLUE]) - static_cast<int32_t>(b);
	uint32_t bestDistance = static_cast<uint32_t>(diffR * diffR + diffG * diffG + diffB * diffB);
	int32_t bestIndex = 0;
	Search(root_, static_cast<int32_t>(r), static_cast<int32_t>(g), static_cast<int32_t>(b),
		&bestIndex, &bestDistance);
	return static_cast<uint32_t>(bestIndex);
}

BaseGifEncoder::BaseGifEncoder() {
	width = 1;
	height = 1;
	frameNum = 0;
	lastColorReducedPixels = NULL;
	lastRootColor = 0;
	useDither = true;
}

void BaseGifEncoder::SortRangeByChannel(uint32_t* imageColorHistogram, int32_t maxColor, uint32_t from, uint32_t to)
{
	if (to <= from) {
		return;
	}
	// Only the channel value at each index matters downstream (median split,
	// min/max bookkeeping and, for the palette itself, per-channel histograms),
	// never which pixel of an equal-valued run sits where. A single byte wide
	// in-place radix pass is therefore equivalent to a comparison sort here, and
	// this runs once per pixel per split level while the palette is built.
	uint32_t count[Cube::COLOR_RANGE] = {0, };
	for (uint32_t index = from; index <= to; ++index) {
		++count[GET_COLOR(imageColorHistogram[index], maxColor)];
	}
	uint32_t begin[Cube::COLOR_RANGE];
	uint32_t end[Cube::COLOR_RANGE];
	uint32_t position = from;
	for (uint32_t value = 0; value < Cube::COLOR_RANGE; ++value) {
		begin[value] = position;
		position += count[value];
		end[value] = position;
	}
	for (uint32_t value = 0; value < Cube::COLOR_RANGE; ++value) {
		while (begin[value] < end[value]) {
			const uint32_t bucket = GET_COLOR(imageColorHistogram[begin[value]], maxColor);
			if (bucket == value) {
				++begin[value];
			} else {
				const uint32_t temp = imageColorHistogram[begin[value]];
				imageColorHistogram[begin[value]] = imageColorHistogram[begin[bucket]];
				imageColorHistogram[begin[bucket]] = temp;
				++begin[bucket];
			}
		}
	}
}

void BaseGifEncoder::updateColorHistogram(Cube* nextCube, Cube* maxCube, int32_t maxColor, uint32_t* imageColorHistogram)
{
	SortRangeByChannel(imageColorHistogram, maxColor, maxCube->colorHistogramFromIndex, maxCube->colorHistogramToIndex);
	uint32_t median = maxCube->colorHistogramFromIndex + ((maxCube->colorHistogramToIndex - maxCube->colorHistogramFromIndex) >> 1);
	nextCube->colorHistogramFromIndex = maxCube->colorHistogramFromIndex;
	nextCube->colorHistogramToIndex = median;

	if (GET_COLOR(imageColorHistogram[nextCube->colorHistogramFromIndex], maxColor) !=
		GET_COLOR(imageColorHistogram[maxCube->colorHistogramToIndex], maxColor)) {
			if (GET_COLOR(imageColorHistogram[nextCube->colorHistogramFromIndex], maxColor) != GET_COLOR(imageColorHistogram[nextCube->colorHistogramToIndex], maxColor)) {
				if (GET_COLOR(imageColorHistogram[median], maxColor) == GET_COLOR(imageColorHistogram[median + 1], maxColor)) {
					while (GET_COLOR(imageColorHistogram[nextCube->colorHistogramToIndex], maxColor) == GET_COLOR(imageColorHistogram[median], maxColor)) {
						--median;
					}
					nextCube->colorHistogramToIndex = median;
				}
			} else {
				while (GET_COLOR(imageColorHistogram[nextCube->colorHistogramToIndex], maxColor) == GET_COLOR(imageColorHistogram[median], maxColor)) {
					++median;
				}
				nextCube->colorHistogramToIndex = median;
			}
	}
	maxCube->colorHistogramFromIndex = maxCube->colorHistogramToIndex > median + 1 ? median + 1 : maxCube->colorHistogramToIndex;
	nextCube->cMin[maxColor] = GET_COLOR(imageColorHistogram[nextCube->colorHistogramFromIndex], maxColor);
	nextCube->cMax[maxColor] = GET_COLOR(imageColorHistogram[nextCube->colorHistogramToIndex], maxColor);
	maxCube->cMin[maxColor] = GET_COLOR(imageColorHistogram[maxCube->colorHistogramFromIndex], maxColor);
	maxCube->cMax[maxColor] = GET_COLOR(imageColorHistogram[maxCube->colorHistogramToIndex], maxColor);
}

void BaseGifEncoder::computeColorTable(uint32_t* pixels, Cube* cubes, uint32_t pixelNum, bool pixelsAreScratch)
{
	uint32_t colors[COLOR_MAX][Cube::COLOR_RANGE] = {0, };
	uint32_t* pixelBegin = pixels;

	// The vector is a uint32 array, so it must be sized in elements (the original
	// code multiplied by sizeof(uint32_t) again, allocating 4x the needed memory -
	// several hundred MB for a long animation).
	vector<uint32_t> colorHistogramMemory;
	uint32_t* colorHistogram = pixels;
	if (!pixelsAreScratch) {
		if (0 != frameNum && NULL != lastColorReducedPixels) {
			colorHistogramMemory.resize(static_cast<size_t>(pixelNum) * 2);
			memcpy(&colorHistogramMemory[0], pixels, pixelNum * sizeof(uint32_t));
			memcpy(&colorHistogramMemory[pixelNum], lastColorReducedPixels, pixelNum * sizeof(uint32_t));
			pixelNum *= 2;
		} else {
			colorHistogramMemory.resize(pixelNum);
			memcpy(&colorHistogramMemory[0], pixels, pixelNum * sizeof(uint32_t));
		}
		colorHistogram = &colorHistogramMemory[0];
	}
	pixels = colorHistogram;
	uint32_t* last = colorHistogram + pixelNum;

	while (last != pixels) {
		uint8_t r = (*pixels) & 0xFF;
		uint8_t g = ((*pixels) >> 8) & 0xFF;
		uint8_t b = ((*pixels) >> 16) & 0xFF;
		++colors[RED][r];
		++colors[GREEN][g];
		++colors[BLUE][b];
		++pixels;
	}

	uint32_t cubeIndex = 0;
	Cube* cube = &cubes[cubeIndex];
	for (uint32_t i = 0; i < COLOR_MAX; ++i) {
		cube->cMin[i] = 255;
		cube->cMax[i] = 0;
	}
	for (uint32_t i = 0; i < 256; ++i) {
		for (uint32_t color = 0; color < COLOR_MAX; ++color) {
			if (0 != colors[color][i]) {
				cube->cMax[color] = cube->cMax[color] < i ? i : cube->cMax[color];
				cube->cMin[color] = cube->cMin[color] > i ? i : cube->cMin[color];
			}
		}
	}
	cube->colorHistogramFromIndex = 0;
	cube->colorHistogramToIndex = pixelNum - 1;
	uint32_t comparingColorList[COLOR_MAX] = {GREEN, RED, BLUE};
	for (cubeIndex = 1; cubeIndex < 255; ++cubeIndex) {
		uint32_t maxDiff = 0;
		uint32_t maxColor = GREEN;
		Cube* maxCube = cubes;
		for (uint32_t i = 0; i < cubeIndex; ++i) {
			Cube* cube = &cubes[i];
			for (uint32_t colorIdx = 0; colorIdx < COLOR_MAX; ++colorIdx) {
				uint32_t comparingColor = comparingColorList[colorIdx];
				uint32_t comparingDiff = cube->cMax[comparingColor] - cube->cMin[comparingColor];
				if (comparingColor == lastRootColor) {
					comparingDiff = comparingDiff * 11 / 10; // multiply 110% to reduce color blinking from difference of root color.
				}

				if (comparingDiff > maxDiff) {
					maxDiff = comparingDiff;
					maxColor = comparingColor;
					maxCube = cube;
				}
			}
		}
		if (1 == cubeIndex) {
			lastRootColor = maxColor;
		}
		if (1 >= maxDiff) {
			break;
		}
		Cube* nextCube = &cubes[cubeIndex];
		for (int32_t color = 0; color < COLOR_MAX; ++color) {
			if (color == maxColor) {
				updateColorHistogram(nextCube, maxCube, maxColor, colorHistogram);
			} else {
				nextCube->cMax[color] = maxCube->cMax[color];
				nextCube->cMin[color] = maxCube->cMin[color];
			}
		}
	}
	for (uint32_t i = 0; i < 255; ++i) {
		Cube* cube = &cubes[i];
		const uint32_t from = cube->colorHistogramFromIndex;
		const uint32_t to = cube->colorHistogramToIndex;
		const uint32_t median = from + ((to - from) >> 1);
		if (median >= pixelNum) {
			continue;
		}
		// Sorting each cube's range per channel just to read the channel value of
		// the median pixel is the same as taking that channel's order statistic at
		// rank (median - from): identical result, but a 256 bin histogram pass
		// instead of three sorts over the whole range.
		for (int32_t color = 0; color < COLOR_MAX; ++color) {
			uint32_t counts[Cube::COLOR_RANGE] = {0, };
			for (uint32_t index = from; index <= to; ++index) {
				++counts[GET_COLOR(colorHistogram[index], color)];
			}
			const uint32_t rank = median - from;
			uint32_t accumulated = 0;
			for (uint32_t value = 0; value < Cube::COLOR_RANGE; ++value) {
				accumulated += counts[value];
				if (accumulated > rank) {
					cube->color[color] = value;
					break;
				}
			}
		}
	}
}

void BaseGifEncoder::reduceColor(const ColorTree* tree, Cube* cubes, uint32_t* pixels, uint32_t* reducedOut)
{
	const int32_t ERROR_PROPAGATION_DIRECTION_NUM = 4;
	const int32_t ERROR_PROPAGATION_DIRECTION_X[] = {1, -1, 0, 1};
	const int32_t ERROR_PROPAGATION_DIRECTION_Y[] = {0, 1, 1, 1};
	const int32_t ERROR_PROPAGATION_DIRECTION_WEIGHT[] = {7, 3, 5, 1};

	uint32_t pixelNum = width * height;
	uint32_t* last = pixels + pixelNum;
	uint8_t* pixelOut = (uint8_t*)pixels;
	uint32_t* colorReducedPixelOut = reducedOut;
	for (uint32_t y = 0; y < height; ++y) {
		for (uint32_t x = 0; x < width; ++x) {
			if (0 == (*pixels >> 24)) {
				*pixelOut = 255; //l transparent color
				if (colorReducedPixelOut != NULL) {
					*colorReducedPixelOut = 0;
				}
			} else {
				uint32_t r = (*pixels) & 0xFF;
				uint32_t g = ((*pixels) >> 8) & 0xFF;
				uint32_t b = ((*pixels) >> 16) & 0xFF;

				uint32_t closestColor = tree->Nearest(r, g, b);
				Cube* cube = &cubes[closestColor];
				*pixelOut = (uint8_t)closestColor;
				if (colorReducedPixelOut != NULL) {
					*colorReducedPixelOut = (0xFF000000 | (cube->color[BLUE] << 16) |
						(cube->color[GREEN] << 8) | cube->color[RED]);
				}
				if (useDither) {
					int32_t diffR = (int32_t)r - (int32_t)cube->color[RED];
					int32_t diffG = (int32_t)g - (int32_t)cube->color[GREEN];
					int32_t diffB = (int32_t)b - (int32_t)cube->color[BLUE];
					for (int directionId = 0; directionId < ERROR_PROPAGATION_DIRECTION_NUM; ++directionId) {
						uint32_t* pixel = pixels + ERROR_PROPAGATION_DIRECTION_X[directionId] + ERROR_PROPAGATION_DIRECTION_Y[directionId] * width;
						if (x + ERROR_PROPAGATION_DIRECTION_X[directionId] >= width ||
							y + ERROR_PROPAGATION_DIRECTION_Y[directionId] >= height || 0 == (*pixels >> 24)) {
								continue;
						}
						int32_t weight = ERROR_PROPAGATION_DIRECTION_WEIGHT[directionId];
						int32_t dstR = ((int32_t)((*pixel) & 0xFF) + (diffR * weight + 8) / 16);
						int32_t dstG = (((int32_t)((*pixel) >> 8) & 0xFF) + (diffG * weight + 8) / 16);
						int32_t dstB = (((int32_t)((*pixel) >> 16) & 0xFF) + (diffB * weight + 8) / 16);
						int32_t dstA = (int32_t)(*pixel >> 24);
						int32_t newR = MIN(255, MAX(0, dstR));
						int32_t newG = MIN(255, MAX(0, dstG));
						int32_t newB = MIN(255, MAX(0, dstB));
						*pixel = (dstA << 24) | (newB << 16) | (newG << 8) | newR;
					}
				}
			}
			++pixels;
			++pixelOut;
			if (colorReducedPixelOut != NULL) {
				++colorReducedPixelOut;
			}
		}
	}
}
