# Native ugoira GIF encoder for HarmonyOS.
#
# Reuses the exact GIF quantization/encoding algorithm the Android build uses
# (android/androidndkgif, MIT licensed): one global 255-color palette computed
# over every frame plus Floyd-Steinberg error diffusion. The system
# ImagePacker GIF encoder cannot be used for this: it quantizes to 5 bits per
# channel, never dithers and writes a fresh palette for every frame, which
# shows up as banding plus inter-frame colour flicker.
cmake_minimum_required(VERSION 3.5.0)
project(ugoiragif)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})

add_library(ugoiragif SHARED
    napi_init.cpp
    gif/BaseGifEncoder.cpp
    gif/GCTGifEncoder.cpp
    gif/BitWritingBlock.cpp
)

target_include_directories(ugoiragif PRIVATE
    ${NATIVERENDER_ROOT_PATH}
    ${NATIVERENDER_ROOT_PATH}/gif
)

target_link_libraries(ugoiragif PUBLIC
    libace_napi.z.so
    libhilog_ndk.z.so
    libimage_source.so
    libpixelmap.so
    libimage_common.so
)
