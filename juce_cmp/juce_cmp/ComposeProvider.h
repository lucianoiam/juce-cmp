// SPDX-FileCopyrightText: 2026 Luciano Iam <oss@lucianoiam.com>
// SPDX-License-Identifier: MIT

#pragma once

#include "ChildProcess.h"
#include "Surface.h"
#include "SurfaceView.h"
#include "Ipc.h"
#include "MachPortIPC.h"
#include <juce_core/juce_core.h>
#include <juce_data_structures/juce_data_structures.h>
#include <cstdint>
#include <string>
#include <functional>
#include <thread>

namespace juce_cmp
{

/**
 * ComposeProvider - Orchestrates Compose UI embedding.
 *
 * Owns and coordinates: Surface, SurfaceView, ChildProcess, Ipc.
 * Pure C++ - no platform-specific code.
 */
class ComposeProvider
{
public:
    using EventCallback = std::function<void(const juce::ValueTree&)>;
    using FirstFrameCallback = std::function<void()>;

    ComposeProvider();
    ~ComposeProvider();

    // Callbacks
    void setEventCallback(EventCallback callback) { eventCallback_ = std::move(callback); }
    void setFirstFrameCallback(FirstFrameCallback callback) { firstFrameCallback_ = std::move(callback); }

    // Lifecycle
    bool launch(const std::string& executable, int width, int height, float scale);
    void stop();
    bool isRunning() const;

    // View management (called by Component)
    void attachView(void* parentNativeHandle);
    void detachView();
    void updateViewBounds(int x, int y, int width, int height);

    // Resize handling
    void resize(int width, int height);

    // IPC
    void sendInput(InputEvent& event);
    void sendEvent(const juce::ValueTree& tree);

    // State
    float getScale() const { return scale_; }

private:
#if __APPLE__
    void sendSurfacePort();
#endif

    Surface surface_;
    SurfaceView view_;
    ChildProcess child_;
    Ipc ipc_;
#if __APPLE__
    MachPortIPC machPortIPC_;
    std::thread machPortThread_;
#endif

    float scale_ = 1.0f;
    EventCallback eventCallback_;
    FirstFrameCallback firstFrameCallback_;
};

}  // namespace juce_cmp
