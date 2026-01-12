// SPDX-FileCopyrightText: 2026 Luciano Iam <oss@lucianoiam.com>
// SPDX-License-Identifier: MIT

#pragma once

#include <cstdint>
#include <functional>

namespace juce_cmp
{

/**
 * SurfaceView - Native view for displaying shared surfaces.
 *
 * On macOS: NSView with CALayer for IOSurface display
 * On Windows: Will use HWND with Direct3D (TODO)
 * On Linux: Will use X11/Wayland with Vulkan (TODO)
 *
 * This is a C++ wrapper around the platform-native view.
 */
class SurfaceView
{
public:
    using ResizeCallback = std::function<void(int width, int height)>;

    SurfaceView();
    ~SurfaceView();

    // Non-copyable
    SurfaceView(const SurfaceView&) = delete;
    SurfaceView& operator=(const SurfaceView&) = delete;

    /** Create the native view. */
    bool create();

    /** Destroy the native view. */
    void destroy();

    /** Check if view is valid. */
    bool isValid() const;

    /** Get the native view handle (NSView* on macOS). */
    void* getNativeHandle() const { return nativeView_; }

    /** Set the surface to display. */
    void setSurface(void* surface);

    /** Set pending surface for next frame (double-buffering). */
    void setPendingSurface(void* surface);

    /** Set the backing scale factor (e.g., 2.0 for Retina). */
    void setBackingScale(float scale);

    /** Attach to a parent native view. */
    void attachToParent(void* parentView);

    /** Detach from parent. */
    void detachFromParent();

    /** Update the view frame. */
    void setFrame(int x, int y, int width, int height, bool parentFlipped);

    /** Set callback for resize requests from the view. */
    void setResizeCallback(ResizeCallback callback) { resizeCallback_ = callback; }

private:
    void* nativeView_ = nullptr;
    ResizeCallback resizeCallback_;
};

}  // namespace juce_cmp
