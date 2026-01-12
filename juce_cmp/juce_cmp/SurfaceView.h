// SPDX-FileCopyrightText: 2026 Luciano Iam <oss@lucianoiam.com>
// SPDX-License-Identifier: MIT

#pragma once

#include <juce_core/juce_core.h>

namespace juce_cmp
{

/**
 * SurfaceView - Platform-specific view for displaying shared surface content.
 *
 * On macOS: NSView subclass that displays IOSurface via CALayer.
 * Uses CADisplayLink for vsync-synchronized refresh.
 */
class SurfaceView
{
public:
    SurfaceView();
    ~SurfaceView();

    /** Attach to parent view. */
    void attach(void* parentView);

    /** Detach from parent view. */
    void detach();

    /** Set the surface to display. */
    void setSurface(void* surface);

    /** Set pending surface for next frame swap. */
    void setPendingSurface(void* surface);

    /** Set backing scale factor. */
    void setScale(float scale);

    /** Update view frame. */
    void setFrame(int x, int y, int width, int height);

    /** Returns true if attached. */
    bool isAttached() const;

private:
    void* nativeView = nullptr;

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(SurfaceView)
};

}  // namespace juce_cmp
