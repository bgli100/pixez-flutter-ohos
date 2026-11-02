/*
 * Copyright (C) 2020. by perol_notsf, All rights reserved
 *
 * This program is free software: you can redistribute it and/or modify it under
 * the terms of the GNU General Public License as published by the Free Software
 * Foundation, either version 3 of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT ANY
 * WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along with
 * this program. If not, see <http://www.gnu.org/licenses/>.
 *
 */

// NAPI entry for the ugoira GIF encoder.
//
// encodeGif(framePaths, delays, outputPath) -> Promise<outputPath>
//
// Frames are decoded through the native image framework (libjpeg based) and
// encoded with GCTGifEncoder, i.e. the same quantization code the Android build
// uses (one global 255-colour palette over all frames plus Floyd-Steinberg
// error diffusion), so colour handling stays identical across platforms.
// Everything runs inside a NAPI async work item: neither decoding nor encoding
// touches the ArkTS/UI thread.

#include <napi/native_api.h>
#include <hilog/log.h>
#include <multimedia/image_framework/image/image_common.h>
#include <multimedia/image_framework/image/image_source_native.h>
#include <multimedia/image_framework/image/pixelmap_native.h>

#include <fcntl.h>
#include <string.h>
#include <unistd.h>

#include <algorithm>
#include <atomic>
#include <exception>
#include <new>
#include <string>
#include <thread>
#include <vector>

#include "gif/GCTGifEncoder.h"

#undef LOG_DOMAIN
#undef LOG_TAG
#define LOG_DOMAIN 0xD002B00
#define LOG_TAG "UgoiraGifNapi"

namespace {

constexpr int32_t DEFAULT_DELAY_MS = 80;

struct EncodeTask {
    std::vector<std::string> framePaths;
    std::vector<int32_t> delays;
    std::string outputPath;
    std::string error;
    napi_deferred deferred = nullptr;
    napi_async_work work = nullptr;
};

void Fail(EncodeTask *task, const std::string &message)
{
    if (task->error.empty()) {
        task->error = message;
    }
}

// Decodes one frame into tightly packed RGBA_8888 pixels (one uint32 per pixel,
// stored as R,G,B,A in memory - the layout GCTGifEncoder expects). The returned
// buffer is allocated with new[] and handed over to the encoder, so frames never
// get copied between decode and compression.
uint32_t *DecodeFrame(const std::string &path, uint32_t *outWidth, uint32_t *outHeight,
                      std::string *error)
{
    int32_t fd = open(path.c_str(), O_RDONLY);
    if (fd < 0) {
        *error = "cannot open frame " + path;
        return nullptr;
    }

    OH_ImageSourceNative *source = nullptr;
    Image_ErrorCode code = OH_ImageSourceNative_CreateFromFd(fd, &source);
    close(fd);
    if (code != IMAGE_SUCCESS || source == nullptr) {
        *error = "cannot decode " + path + " (source error " + std::to_string(code) + ")";
        return nullptr;
    }

    OH_DecodingOptions *options = nullptr;
    OH_DecodingOptions_Create(&options);
    OH_DecodingOptions_SetPixelFormat(options, PIXEL_FORMAT_RGBA_8888);
    OH_PixelmapNative *pixelmap = nullptr;
    code = OH_ImageSourceNative_CreatePixelmap(source, options, &pixelmap);
    OH_DecodingOptions_Release(options);
    OH_ImageSourceNative_Release(source);
    if (code != IMAGE_SUCCESS || pixelmap == nullptr) {
        *error = "cannot create pixelmap for " + path + " (error " + std::to_string(code) + ")";
        return nullptr;
    }

    OH_Pixelmap_ImageInfo *info = nullptr;
    OH_PixelmapImageInfo_Create(&info);
    uint32_t width = 0;
    uint32_t height = 0;
    uint32_t rowStride = 0;
    code = OH_PixelmapNative_GetImageInfo(pixelmap, info);
    if (code == IMAGE_SUCCESS) {
        OH_PixelmapImageInfo_GetWidth(info, &width);
        OH_PixelmapImageInfo_GetHeight(info, &height);
        OH_PixelmapImageInfo_GetRowStride(info, &rowStride);
    }
    OH_PixelmapImageInfo_Release(info);
    if (code != IMAGE_SUCCESS || width == 0 || height == 0) {
        OH_PixelmapNative_Release(pixelmap);
        *error = "cannot read image info for " + path;
        return nullptr;
    }

    const uint32_t packedStride = width * sizeof(uint32_t);
    if (rowStride < packedStride) {
        rowStride = packedStride;
    }
    std::vector<uint8_t> raw(static_cast<size_t>(rowStride) * height);
    size_t rawSize = raw.size();
    code = OH_PixelmapNative_ReadPixels(pixelmap, raw.data(), &rawSize);
    OH_PixelmapNative_Release(pixelmap);
    if (code != IMAGE_SUCCESS) {
        *error = "cannot read pixels for " + path + " (error " + std::to_string(code) + ")";
        return nullptr;
    }

    const size_t pixelCount = static_cast<size_t>(width) * height;
    auto *pixels = new (std::nothrow) uint32_t[pixelCount];
    if (pixels == nullptr) {
        *error = "out of memory while decoding " + path;
        return nullptr;
    }
    auto *out = reinterpret_cast<uint8_t *>(pixels);
    if (rowStride == packedStride) {
        memcpy(out, raw.data(), pixelCount * sizeof(uint32_t));
    } else {
        // Some decoders pad rows; compact them so the encoder sees a flat buffer.
        for (uint32_t y = 0; y < height; y++) {
            memcpy(out + static_cast<size_t>(y) * packedStride,
                   raw.data() + static_cast<size_t>(y) * rowStride, packedStride);
        }
    }
    *outWidth = width;
    *outHeight = height;
    return pixels;
}

void EncodeFrames(EncodeTask *task)
{
    GCTGifEncoder encoder;
    const size_t frameCount = task->framePaths.size();
    std::vector<uint32_t *> frames(frameCount, nullptr);
    std::vector<uint32_t> widths(frameCount, 0);
    std::vector<uint32_t> heights(frameCount, 0);
    std::vector<std::string> errors(frameCount);

    // Decoding is independent per frame and costs ~30-50ms each, so fan it out
    // instead of waiting for every frame serially. The buffers are then handed
    // to the encoder by pointer, which keeps peak memory the same as before.
    std::atomic<size_t> next(0);
    const unsigned workerCount =
        std::min<unsigned>(std::max(1u, std::thread::hardware_concurrency()), 4u);
    std::vector<std::thread> workers;
    workers.reserve(workerCount);
    for (unsigned i = 0; i < workerCount; ++i) {
        workers.emplace_back([&]() {
            for (;;) {
                const size_t index = next.fetch_add(1);
                if (index >= frameCount) {
                    return;
                }
                frames[index] = DecodeFrame(task->framePaths[index], &widths[index],
                                            &heights[index], &errors[index]);
            }
        });
    }
    for (std::thread &worker : workers) {
        worker.join();
    }

    for (size_t i = 0; i < frameCount; ++i) {
        if (frames[i] == nullptr) {
            for (uint32_t *frame : frames) {
                delete[] frame;
            }
            Fail(task, errors[i].empty() ? "cannot decode frame " + task->framePaths[i] : errors[i]);
            return;
        }
    }

    bool inited = false;
    uint32_t width = 0;
    uint32_t height = 0;
    for (size_t i = 0; i < frameCount; i++) {
        if (!inited) {
            if (!encoder.init(static_cast<uint16_t>(widths[i]), static_cast<uint16_t>(heights[i]),
                              task->outputPath.c_str())) {
                for (size_t rest = i; rest < frameCount; ++rest) {
                    delete[] frames[rest];
                }
                Fail(task, "cannot create " + task->outputPath);
                return;
            }
            width = widths[i];
            height = heights[i];
            inited = true;
        } else if (widths[i] != width || heights[i] != height) {
            for (size_t rest = i; rest < frameCount; ++rest) {
                delete[] frames[rest];
            }
            Fail(task, "frame size mismatch: " + task->framePaths[i]);
            return;
        }
        const int32_t delayMs = i < task->delays.size() ? task->delays[i] : DEFAULT_DELAY_MS;
        encoder.encodeFrameOwned(frames[i], delayMs);
        frames[i] = nullptr;
    }

    if (!inited) {
        Fail(task, "no frame to encode");
        return;
    }
    // release() writes the palette, every buffered frame and the trailer.
    encoder.release();
}

void ExecuteEncode(napi_env env, void *data)
{
    auto *task = static_cast<EncodeTask *>(data);
    try {
        EncodeFrames(task);
    } catch (const std::bad_alloc &) {
        Fail(task, "out of memory while encoding gif");
    } catch (const std::exception &e) {
        Fail(task, std::string("gif encoding failed: ") + e.what());
    } catch (...) {
        Fail(task, "gif encoding failed");
    }
}

void CompleteEncode(napi_env env, napi_status status, void *data)
{
    auto *task = static_cast<EncodeTask *>(data);
    if (!task->error.empty()) {
        // Never leave a half written gif behind for the gallery to pick up.
        unlink(task->outputPath.c_str());
        OH_LOG_ERROR(LOG_APP, "%{public}s: %{public}s", LOG_TAG, task->error.c_str());
    }
    if (task->deferred != nullptr) {
        if (!task->error.empty()) {
            napi_value message = nullptr;
            napi_value error = nullptr;
            napi_create_string_utf8(env, task->error.c_str(), NAPI_AUTO_LENGTH, &message);
            napi_create_error(env, nullptr, message, &error);
            napi_reject_deferred(env, task->deferred, error);
        } else {
            napi_value result = nullptr;
            napi_create_string_utf8(env, task->outputPath.c_str(), NAPI_AUTO_LENGTH, &result);
            napi_resolve_deferred(env, task->deferred, result);
        }
    }
    napi_delete_async_work(env, task->work);
    delete task;
}

bool ReadStringArray(napi_env env, napi_value value, std::vector<std::string> *out)
{
    uint32_t length = 0;
    if (napi_get_array_length(env, value, &length) != napi_ok) {
        return false;
    }
    for (uint32_t i = 0; i < length; i++) {
        napi_value item = nullptr;
        size_t size = 0;
        if (napi_get_element(env, value, i, &item) != napi_ok ||
            napi_get_value_string_utf8(env, item, nullptr, 0, &size) != napi_ok) {
            return false;
        }
        std::string text(size, '\0');
        if (napi_get_value_string_utf8(env, item, text.data(), size + 1, &size) != napi_ok) {
            return false;
        }
        out->push_back(text);
    }
    return true;
}

bool ReadNumberArray(napi_env env, napi_value value, std::vector<int32_t> *out)
{
    uint32_t length = 0;
    if (napi_get_array_length(env, value, &length) != napi_ok) {
        return false;
    }
    for (uint32_t i = 0; i < length; i++) {
        napi_value item = nullptr;
        int32_t number = 0;
        if (napi_get_element(env, value, i, &item) != napi_ok ||
            napi_get_value_int32(env, item, &number) != napi_ok) {
            return false;
        }
        out->push_back(number);
    }
    return true;
}

bool ReadString(napi_env env, napi_value value, std::string *out)
{
    size_t size = 0;
    if (napi_get_value_string_utf8(env, value, nullptr, 0, &size) != napi_ok) {
        return false;
    }
    *out = std::string(size, '\0');
    return napi_get_value_string_utf8(env, value, out->data(), size + 1, &size) == napi_ok;
}

napi_value ThrowMessage(napi_env env, const char *message)
{
    napi_value jsMessage = nullptr;
    napi_value error = nullptr;
    napi_create_string_utf8(env, message, NAPI_AUTO_LENGTH, &jsMessage);
    napi_create_error(env, nullptr, jsMessage, &error);
    napi_throw(env, error);
    return nullptr;
}

napi_value EncodeGif(napi_env env, napi_callback_info info)
{
    size_t argc = 3;
    napi_value args[3] = {nullptr, nullptr, nullptr};
    if (napi_get_cb_info(env, info, &argc, args, nullptr, nullptr) != napi_ok || argc < 3) {
        return ThrowMessage(env, "encodeGif(framePaths, delays, outputPath) expected");
    }

    auto *task = new (std::nothrow) EncodeTask();
    if (task == nullptr) {
        return ThrowMessage(env, "out of memory");
    }
    if (!ReadStringArray(env, args[0], &task->framePaths) ||
        !ReadNumberArray(env, args[1], &task->delays) ||
        !ReadString(env, args[2], &task->outputPath)) {
        delete task;
        return ThrowMessage(env, "invalid encodeGif arguments");
    }
    if (task->framePaths.empty()) {
        delete task;
        return ThrowMessage(env, "no frame to encode");
    }

    napi_value promise = nullptr;
    if (napi_create_promise(env, &task->deferred, &promise) != napi_ok) {
        delete task;
        return ThrowMessage(env, "cannot create promise");
    }
    napi_value resourceName = nullptr;
    napi_create_string_utf8(env, "UgoiraGifEncode", NAPI_AUTO_LENGTH, &resourceName);
    if (napi_create_async_work(env, nullptr, resourceName, ExecuteEncode, CompleteEncode, task,
                               &task->work) != napi_ok) {
        napi_value ignored = nullptr;
        napi_reject_deferred(env, task->deferred, ignored);
        delete task;
        return ThrowMessage(env, "cannot start async work");
    }
    napi_queue_async_work(env, task->work);
    return promise;
}

napi_value Init(napi_env env, napi_value exports)
{
    napi_property_descriptor descriptors[] = {
        {"encodeGif", nullptr, EncodeGif, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(descriptors) / sizeof(descriptors[0]), descriptors);
    return exports;
}

napi_module gifModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "ugoiragif",
    .nm_priv = nullptr,
    .reserved = {0},
};

} // namespace

extern "C" __attribute__((constructor)) void RegisterUgoiraGifModule(void)
{
    napi_module_register(&gifModule);
}
