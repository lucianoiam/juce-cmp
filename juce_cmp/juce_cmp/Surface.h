// SPDX-FileCopyrightText: 2026 Luciano Iam <oss@lucianoiam.com>
// SPDX-License-Identifier: MIT

#pragma once

#include <juce_core/juce_core.h>
#include <cstdint>

namespace juce_cmp
{

/**
 * Surface - Platform-specific shared surface for zero-copy rendering.
 *
 * On macOS: IOSurface
 * On Windows: DXGI shared texture (TODO)
 * On Linux: Shared memory or Vulkan external memory (TODO)
 */
class Surface
{
public:
    Surface();
    ~Surface();

    /** Create a surface with the given pixel dimensions. */
    bool create(int width, int height);

    /** Resize the surface. Returns new surface ID, or 0 on failure. */
    uint32_t resize(int width, int height);

    /** Release the surface. */
    void release();

    /** Get the surface ID for passing to child process. */
    uint32_t getID() const;

    /** Get the native surface handle (IOSurfaceRef on macOS). */
    void* getNativeHandle() const;

    /** Get surface dimensions. */
    int getWidth() const { return width; }
    int getHeight() const { return height; }

private:
    void* surface = nullptr;
    void* previousSurface = nullptr;  // Keep alive during resize transition
    int width = 0;
    int height = 0;

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(Surface)
};

}  // namespace juce_cmp
