// "Who is speaking" overlay: a small always-on-top, click-to-drag, closable window that
// lists the members of the current voice channel and highlights whoever is talking.
// It is a native layered window (per-pixel alpha, GDI+), so it stays visible over other
// applications and borderless / windowed games while Pulse is minimized or in the tray.
// Exclusive-fullscreen games (rare today) draw over every desktop window, including this one.
//
// Threading: all functions may be called from any thread; GDI+ work happens only on the
// overlay's own UI thread. Speaking state is read directly from the audio engine
// (userSpeakingLevel), so the highlight reacts within ~50 ms without Dart involvement.
#pragma once
#include "common.h"

namespace pn {

// Implemented in engine.cpp: current playback level of a remote speaker (0 = silent),
// or the local transmit state when self is true.
float userSpeakingLevel(uint32_t uid, bool self);

namespace overlay {
enum { kModeAll = 0, kModeSpeaking = 1 };
enum { kFlagMute = 1, kFlagDeaf = 2, kFlagServerMute = 4 };

void show(bool on);
void config(int mode, float opacity, float scale, bool locked, bool hideWhenAppFocused);
void rosterBegin(const std::string& title, uint32_t me);
void rosterAdd(uint32_t id, const std::string& name, uint32_t argb, int flags);
void rosterCommit();
void setAvatar(uint32_t id, const uint8_t* data, int len);  // len 0 = back to the letter avatar
void resetPosition();
void shutdown();
}  // namespace overlay
}  // namespace pn
