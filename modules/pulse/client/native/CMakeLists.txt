# pulse_native.dll — audio engine / hotkeys / GPU voice changer (see include/pulse_native.h).
# Built by the Flutter Windows runner (windows/CMakeLists.txt adds this directory) or
# stand-alone:  cmake -S client/native -B build/native -G Ninja && cmake --build build/native
cmake_minimum_required(VERSION 3.20)
project(pulse_native LANGUAGES C CXX)

# C++20: C++/WinRT (screen capture) needs standard coroutine support.
set(CMAKE_CXX_STANDARD 20)
# Real-time audio code is always built optimized; MSVC's /RTC1 (Debug default) conflicts with /O2.
foreach(flag_var CMAKE_C_FLAGS_DEBUG CMAKE_CXX_FLAGS_DEBUG)
  string(REGEX REPLACE "/RTC[1csu]+" "" ${flag_var} "${${flag_var}}")
endforeach()
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(PN_DIR ${CMAKE_CURRENT_LIST_DIR})

# ---- RNNoise (BSD-3, xiph.org) with runtime SSE4.1 / AVX2 dispatch
set(RN ${PN_DIR}/third_party/rnnoise/src)
add_library(rnnoise STATIC
  ${RN}/denoise.c ${RN}/rnn.c ${RN}/pitch.c ${RN}/kiss_fft.c ${RN}/celt_lpc.c ${RN}/nnet.c
  ${RN}/nnet_default.c ${RN}/parse_lpcnet_weights.c ${RN}/rnnoise_data.c ${RN}/rnnoise_tables.c
  ${RN}/x86/x86_dnn_map.c ${RN}/x86/x86cpu.c ${RN}/x86/nnet_sse4_1.c ${RN}/x86/nnet_avx2.c)
target_include_directories(rnnoise PUBLIC ${PN_DIR}/third_party/rnnoise/include PRIVATE ${RN})
# x64 always has SSE2 (selects the vectorized code paths); SSE4.1/AVX2 only in their own files.
target_compile_definitions(rnnoise PRIVATE RNN_ENABLE_X86_RTCD OPUS_X86_MAY_HAVE_SSE OPUS_X86_MAY_HAVE_SSE2 _CRT_SECURE_NO_WARNINGS)
if(MSVC)
  target_compile_options(rnnoise PRIVATE /O2 /fp:fast /wd4244 /wd4305 /wd4267 /wd4018 /wd4146)
  set_source_files_properties(${RN}/x86/nnet_avx2.c PROPERTIES COMPILE_OPTIONS "/arch:AVX2;-D__AVX__;-D__AVX2__;-D__FMA__;-D__SSE4_1__")
  set_source_files_properties(${RN}/x86/nnet_sse4_1.c PROPERTIES COMPILE_OPTIONS "-D__SSE4_1__")
else()
  set_source_files_properties(${RN}/x86/nnet_avx2.c PROPERTIES COMPILE_OPTIONS "-mavx2;-mfma")
  set_source_files_properties(${RN}/x86/nnet_sse4_1.c PROPERTIES COMPILE_OPTIONS "-msse4.1")
endif()
set_property(TARGET rnnoise PROPERTY POSITION_INDEPENDENT_CODE ON)
# ~78 MB of weight tables: nothing to optimize, keep compile time down.
set_source_files_properties(${RN}/rnnoise_data.c PROPERTIES COMPILE_OPTIONS "$<$<C_COMPILER_ID:MSVC>:/Od>")

# ---- engine
add_library(pulse_native SHARED
  ${PN_DIR}/src/engine.cpp ${PN_DIR}/src/common.cpp ${PN_DIR}/src/dsp.cpp
  ${PN_DIR}/src/opus_dyn.cpp ${PN_DIR}/src/vc_ai.cpp ${PN_DIR}/src/overlay.cpp
  ${PN_DIR}/src/screen.cpp ${PN_DIR}/src/h264_enc.cpp ${PN_DIR}/src/video_dec.cpp)
target_include_directories(pulse_native PRIVATE ${PN_DIR}/include ${PN_DIR}/src
  ${PN_DIR}/third_party/miniaudio ${PN_DIR}/third_party/onnxruntime/include)
target_link_libraries(pulse_native PRIVATE rnnoise crypt32 dxgi d3d12 ole32 user32 winmm gdiplus shlwapi
  d3d11 dwmapi mfplat mfuuid mf strmiids wmcodecdspuuid windowsapp)
target_compile_definitions(pulse_native PRIVATE NOMINMAX WIN32_LEAN_AND_MEAN _CRT_SECURE_NO_WARNINGS UNICODE _UNICODE)
if(MSVC)
  target_compile_options(pulse_native PRIVATE /O2 /W3 /utf-8 /EHsc /wd4244 /wd4267)
  # static CRT so the DLL has no VC++ redistributable dependency of its own
  set_property(TARGET pulse_native rnnoise PROPERTY MSVC_RUNTIME_LIBRARY "MultiThreaded")
endif()

# Runtime files that must sit next to the executable (copied by the runner's install step).
set(PULSE_NATIVE_RUNTIME
  ${PN_DIR}/bin/opus.dll
  ${PN_DIR}/bin/onnxruntime.dll
  ${PN_DIR}/bin/onnxruntime_providers_shared.dll
  ${PN_DIR}/bin/DirectML.dll
  CACHE INTERNAL "Pulse native runtime DLLs")
set(PULSE_NATIVE_MODELS_DIR ${PN_DIR}/models CACHE INTERNAL "Pulse AI models")
