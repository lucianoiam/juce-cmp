// SPDX-FileCopyrightText: 2026 Luciano Iam <oss@lucianoiam.com>
// SPDX-License-Identifier: MIT

#pragma once

#include "ChildProcess.h"
#include "Surface.h"
#include <juce_core/juce_core.h>
#include <cstdint>
#include <string>
#include <functional>

namespace juce_cmp
{

/**
 * ComposeProvider - Creates shared surfaces and manages the child UI process.
 *
 * On macOS: Uses IOSurface for zero-copy GPU sharing
 * On Windows: Will use DXGI shared textures (TODO)
 * On Linux: Will use shared memory or Vulkan external memory (TODO)
 */
class ComposeProvider
{
public:
    ComposeProvider();
    ~ComposeProvider();

    /** Create a shared surface with the given dimensions. */
    bool createSurface(int width, int height);

    /** Resize the surface. Returns the new surface ID. */
    uint32_t resizeSurface(int width, int height);

    /** Get the current surface ID (passed to child process). */
    uint32_t getSurfaceID() const;

    /** Get the native surface handle (IOSurfaceRef on macOS). */
    void* getNativeSurface() const;

    /** Get surface dimensions. */
    int getWidth() const;
    int getHeight() const;

    /** Launch the child Compose UI process with scale factor for Retina support. */
    bool launchChild(const std::string& executable, float scale = 1.0f, const std::string& workingDir = "");

    /** Stop the child process. */
    void stopChild();

    /** Check if child is running. */
    bool isChildRunning() const;

    /** Get the stdin pipe file descriptor for input forwarding. */
    int getInputPipeFD() const;

    /** Get the stdout pipe file descriptor for reading UI messages. */
    int getStdoutPipeFD() const;

private:
    class Impl;
    std::unique_ptr<Impl> pImpl;
};

}  // namespace juce_cmp
