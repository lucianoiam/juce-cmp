#pragma once

#include <juce_core/juce_core.h>
#include <cstdint>
#include <string>
#include <functional>

namespace juce_cmp
{

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

    /** 
     * Resize the surface (double-buffered). 
     * Creates a new pending surface for child to render to.
     * Call commitPendingSurface() after child renders to swap.
     * Returns the new surface ID.
     */
    uint32_t resizeSurface(int width, int height);

    /** Commit pending surface - swap it to become the displayed surface. */
    void commitPendingSurface();

    /** Get the pending surface (for child to render to during resize). */
    void* getPendingSurface() const;

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

    /** Get the IPC pipe file descriptor for reading UI messages. */
    int getIPCPipeFD() const;
    
    /** Get the IPC FIFO path for UIReceiver to open directly. */
    juce::String getIPCFifoPath() const;

private:
    class Impl;
    std::unique_ptr<Impl> pImpl;
};

}  // namespace juce_cmp
