#pragma once

#include <cstdint>
#include <string>
#include <functional>

/**
 * IOSurfaceProvider - Cross-platform abstraction for shared surface creation
 * and child process management.
 * 
 * On macOS: Uses IOSurface for zero-copy GPU sharing
 * On Windows: Will use DXGI shared textures (TODO)
 * On Linux: Will use shared memory or Vulkan external memory (TODO)
 */
class IOSurfaceProvider
{
public:
    IOSurfaceProvider();
    ~IOSurfaceProvider();

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

    /** Launch the child Compose UI process. */
    bool launchChild(const std::string& executable, const std::string& workingDir = "");

    /** Stop the child process. */
    void stopChild();

    /** Check if child is running. */
    bool isChildRunning() const;

    /** Get the stdin pipe file descriptor for input forwarding. */
    int getInputPipeFD() const;

private:
    class Impl;
    std::unique_ptr<Impl> pImpl;
};
