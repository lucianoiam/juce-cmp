/**
 * IOSurfaceProvider - Creates shared GPU memory and manages child process.
 * 
 * Uses JUCE APIs where possible:
 * - juce::File for path handling
 * - juce::String for string operations
 * - juce::Logger (DBG) for logging
 * 
 * Platform-specific code (macOS):
 * - IOSurface creation (no JUCE equivalent)
 * - fork/exec with stdin pipe (juce::ChildProcess doesn't support stdin writing)
 */
#include "IOSurfaceProvider.h"
#include <juce_core/juce_core.h>
#include <string>

#if JUCE_MAC
#import <Foundation/Foundation.h>
#import <IOSurface/IOSurface.h>
#endif

class IOSurfaceProvider::Impl
{
public:
    Impl() = default;
    
    ~Impl()
    {
        stopChild();
        releaseSurface();
    }

    bool createSurface(int w, int h)
    {
#if JUCE_MAC
        releaseSurface();
        
        surfaceWidth = w;
        surfaceHeight = h;

        NSDictionary* props = @{
            (id)kIOSurfaceWidth: @(w),
            (id)kIOSurfaceHeight: @(h),
            (id)kIOSurfaceBytesPerElement: @4,
            (id)kIOSurfacePixelFormat: @((uint32_t)'BGRA'),
            (id)kIOSurfaceIsGlobal: @YES  // Required for cross-process lookup
        };
        
        surface = IOSurfaceCreate((__bridge CFDictionaryRef)props);
        
        if (surface != nullptr)
        {
            DBG("IOSurfaceProvider: Created surface " + juce::String(w) + "x" + juce::String(h) 
                + ", ID=" + juce::String(IOSurfaceGetID(surface)));
            return true;
        }
        
        DBG("IOSurfaceProvider: Failed to create surface");
        return false;
#else
        juce::ignoreUnused(w, h);
        DBG("IOSurfaceProvider: Not implemented on this platform");
        return false;
#endif
    }

    uint32_t resizeSurface(int w, int h)
    {
#if JUCE_MAC
        // Create new surface but don't release old one yet.
        // The old surface stays in 'surface' for display.
        // The new surface goes in 'pendingSurface' for child to render to.
        if (pendingSurface != nullptr)
            CFRelease(pendingSurface);
        
        surfaceWidth = w;
        surfaceHeight = h;

        NSDictionary* props = @{
            (id)kIOSurfaceWidth: @(w),
            (id)kIOSurfaceHeight: @(h),
            (id)kIOSurfaceBytesPerElement: @4,
            (id)kIOSurfacePixelFormat: @((uint32_t)'BGRA'),
            (id)kIOSurfaceIsGlobal: @YES
        };
        
        pendingSurface = IOSurfaceCreate((__bridge CFDictionaryRef)props);
        
        if (pendingSurface != nullptr)
        {
            DBG("IOSurfaceProvider: Created pending surface " + juce::String(w) + "x" + juce::String(h) 
                + ", ID=" + juce::String(IOSurfaceGetID(pendingSurface)));
            return IOSurfaceGetID(pendingSurface);
        }
        return 0;
#else
        juce::ignoreUnused(w, h);
        return 0;
#endif
    }

    /// Commit the pending surface - swap it to become the displayed surface
    void commitPendingSurface()
    {
#if JUCE_MAC
        if (pendingSurface != nullptr)
        {
            if (surface != nullptr)
                CFRelease(surface);
            surface = pendingSurface;
            pendingSurface = nullptr;
        }
#endif
    }

    /// Get the pending surface (for child to render to during resize)
    void* getPendingSurface() const
    {
#if JUCE_MAC
        return pendingSurface;
#else
        return nullptr;
#endif
    }

    uint32_t getSurfaceID() const
    {
#if JUCE_MAC
        return surface != nullptr ? IOSurfaceGetID(surface) : 0;
#else
        return 0;
#endif
    }

    void* getNativeSurface() const
    {
#if JUCE_MAC
        return surface;
#else
        return nullptr;
#endif
    }

    int getWidth() const { return surfaceWidth; }
    int getHeight() const { return surfaceHeight; }

    bool launchChild(const juce::String& executable, const juce::String& workingDir)
    {
#if JUCE_MAC
        if (surface == nullptr)
        {
            DBG("IOSurfaceProvider: No surface, cannot launch child");
            return false;
        }

        // Verify executable exists using JUCE File API
        juce::File execFile(executable);
        if (!execFile.existsAsFile())
        {
            DBG("IOSurfaceProvider: Executable not found: " + executable);
            return false;
        }
        
        // Capture surface ID BEFORE fork - after fork the IOSurfaceRef pointer
        // is invalid in the child process context
        uint32_t surfaceID = IOSurfaceGetID(surface);
        std::string surfaceArg = "--iosurface-id=" + std::to_string(surfaceID);
        std::string execPath = executable.toStdString();
        std::string workDir = workingDir.toStdString();

        // Create pipe for stdin (JUCE ChildProcess doesn't support stdin writing)
        int pipeDescriptors[2];
        if (pipe(pipeDescriptors) != 0)
        {
            DBG("IOSurfaceProvider: Failed to create pipe");
            return false;
        }

        childPid = fork();
        
        if (childPid == 0)
        {
            // Child process
            close(pipeDescriptors[1]);  // Close write end
            dup2(pipeDescriptors[0], STDIN_FILENO);  // Redirect stdin
            close(pipeDescriptors[0]);

            if (!workDir.empty())
                chdir(workDir.c_str());

            execl(execPath.c_str(), 
                  execPath.c_str(), 
                  "--embed", 
                  surfaceArg.c_str(), 
                  nullptr);
            
            // If exec fails, exit child
            _exit(1);
        }
        else if (childPid > 0)
        {
            // Parent process
            close(pipeDescriptors[0]);  // Close read end
            stdinPipeFD = pipeDescriptors[1];
            
            DBG("IOSurfaceProvider: Launched child PID " + juce::String(childPid) 
                + " with surface ID " + juce::String(IOSurfaceGetID(surface)));
            return true;
        }
        else
        {
            DBG("IOSurfaceProvider: Fork failed");
            close(pipeDescriptors[0]);
            close(pipeDescriptors[1]);
            return false;
        }
#else
        juce::ignoreUnused(executable, workingDir);
        return false;
#endif
    }

    void stopChild()
    {
#if JUCE_MAC
        // Close stdin pipe first (signals EOF to child)
        if (stdinPipeFD >= 0)
        {
            close(stdinPipeFD);
            stdinPipeFD = -1;
        }
        
        // Terminate child process
        if (childPid > 0)
        {
            kill(childPid, SIGTERM);
            childPid = 0;
        }
#endif
    }

    bool isChildRunning() const
    {
#if JUCE_MAC
        if (childPid <= 0) 
            return false;
        // Check if process exists without sending a signal
        return kill(childPid, 0) == 0;
#else
        return false;
#endif
    }

    int getInputPipeFD() const
    {
        return stdinPipeFD;
    }

private:
    void releaseSurface()
    {
#if JUCE_MAC
        if (surface != nullptr)
        {
            CFRelease(surface);
            surface = nullptr;
        }
        if (pendingSurface != nullptr)
        {
            CFRelease(pendingSurface);
            pendingSurface = nullptr;
        }
#endif
    }

#if JUCE_MAC
    IOSurfaceRef surface = nullptr;
    IOSurfaceRef pendingSurface = nullptr;
    pid_t childPid = 0;
#endif
    int stdinPipeFD = -1;
    int surfaceWidth = 0;
    int surfaceHeight = 0;
};

// Public interface - delegates to Impl
IOSurfaceProvider::IOSurfaceProvider() : pImpl(std::make_unique<Impl>()) {}
IOSurfaceProvider::~IOSurfaceProvider() = default;

bool IOSurfaceProvider::createSurface(int width, int height) 
{ 
    return pImpl->createSurface(width, height); 
}

uint32_t IOSurfaceProvider::resizeSurface(int width, int height) 
{ 
    return pImpl->resizeSurface(width, height); 
}

void IOSurfaceProvider::commitPendingSurface()
{
    pImpl->commitPendingSurface();
}

void* IOSurfaceProvider::getPendingSurface() const
{
    return pImpl->getPendingSurface();
}

uint32_t IOSurfaceProvider::getSurfaceID() const 
{ 
    return pImpl->getSurfaceID(); 
}

void* IOSurfaceProvider::getNativeSurface() const 
{ 
    return pImpl->getNativeSurface(); 
}

int IOSurfaceProvider::getWidth() const 
{ 
    return pImpl->getWidth(); 
}

int IOSurfaceProvider::getHeight() const 
{ 
    return pImpl->getHeight(); 
}

bool IOSurfaceProvider::launchChild(const std::string& executable, const std::string& workingDir) 
{ 
    return pImpl->launchChild(juce::String(executable), juce::String(workingDir)); 
}

void IOSurfaceProvider::stopChild() 
{ 
    pImpl->stopChild(); 
}

bool IOSurfaceProvider::isChildRunning() const 
{ 
    return pImpl->isChildRunning(); 
}

int IOSurfaceProvider::getInputPipeFD() const 
{ 
    return pImpl->getInputPipeFD(); 
}
