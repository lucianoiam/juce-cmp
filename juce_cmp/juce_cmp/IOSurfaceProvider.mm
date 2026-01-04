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
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/wait.h>
#endif

namespace juce_cmp
{

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
            //DBG("IOSurfaceProvider: Created pending surface " + juce::String(w) + "x" + juce::String(h) 
            //    + ", ID=" + juce::String(IOSurfaceGetID(pendingSurface)));
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

    bool launchChild(const juce::String& executable, float scale, const juce::String& workingDir)
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

        // Create pipe for stdin (host→UI input events)
        int stdinPipes[2];
        if (pipe(stdinPipes) != 0)
        {
            DBG("IOSurfaceProvider: Failed to create stdin pipe");
            return false;
        }

        // Create named pipe (FIFO) for UI→Host IPC
        // Use pid-based path to avoid conflicts
        ipcFifoPath = "/tmp/cmpui-ipc-" + std::to_string(getpid()) + ".fifo";
        unlink(ipcFifoPath.c_str());  // Remove if exists
        if (mkfifo(ipcFifoPath.c_str(), 0600) != 0)
        {
            DBG("IOSurfaceProvider: Failed to create IPC FIFO");
            close(stdinPipes[0]);
            close(stdinPipes[1]);
            return false;
        }
        std::string ipcArg = "--ipc-pipe=" + ipcFifoPath;
        std::string scaleArg = "--scale=" + std::to_string(scale);

        childPid = fork();
        
        if (childPid == 0)
        {
            // Child process
            close(stdinPipes[1]);   // Close write end of stdin pipe
            
            dup2(stdinPipes[0], STDIN_FILENO);   // Redirect stdin
            close(stdinPipes[0]);

            if (!workDir.empty())
                chdir(workDir.c_str());

            execl(execPath.c_str(), 
                  execPath.c_str(), 
                  "--embed", 
                  surfaceArg.c_str(), 
                  ipcArg.c_str(),
                  scaleArg.c_str(),
                  nullptr);
            
            // If exec fails, exit child
            _exit(1);
        }
        else if (childPid > 0)
        {
            // Parent process
            close(stdinPipes[0]);   // Close read end of stdin pipe
            
            stdinPipeFD = stdinPipes[1];
            // Note: ipcPipeFD will be opened lazily by UIReceiver to avoid blocking here
            // The UIReceiver will open the FIFO path directly
            
            DBG("IOSurfaceProvider: Launched child PID " + juce::String(childPid) 
                + " with surface ID " + juce::String(IOSurfaceGetID(surface)));
            return true;
        }
        else
        {
            DBG("IOSurfaceProvider: Fork failed");
            close(stdinPipes[0]);
            close(stdinPipes[1]);
            unlink(ipcFifoPath.c_str());
            ipcFifoPath.clear();
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
        // Close stdin pipe first - signals EOF to child, causing it to exit
        if (stdinPipeFD >= 0)
        {
            close(stdinPipeFD);
            stdinPipeFD = -1;
        }
        
        // Wait for child to exit with timeout, then force kill
        if (childPid > 0)
        {
            int status;
            // Give child 200ms to exit gracefully
            for (int i = 0; i < 20; ++i)
            {
                pid_t result = waitpid(childPid, &status, WNOHANG);
                if (result != 0) {
                    // Child exited or error
                    childPid = 0;
                    break;
                }
                usleep(10000);  // 10ms
            }
            
            // If still alive, force kill
            if (childPid > 0)
            {
                kill(childPid, SIGKILL);
                waitpid(childPid, &status, 0);
                childPid = 0;
            }
        }
        
        // Close IPC pipe and clean up FIFO after child has exited
        if (ipcPipeFD >= 0)
        {
            close(ipcPipeFD);
            ipcPipeFD = -1;
        }
        if (!ipcFifoPath.empty())
        {
            unlink(ipcFifoPath.c_str());
            ipcFifoPath.clear();
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

    int getIPCPipeFD() const
    {
        return ipcPipeFD;
    }
    
    const std::string& getIPCFifoPath() const
    {
        return ipcFifoPath;
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
    int ipcPipeFD = -1;
    std::string ipcFifoPath;
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

bool IOSurfaceProvider::launchChild(const std::string& executable, float scale, const std::string& workingDir) 
{ 
    return pImpl->launchChild(juce::String(executable), scale, juce::String(workingDir)); 
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

int IOSurfaceProvider::getIPCPipeFD() const 
{ 
    return pImpl->getIPCPipeFD(); 
}

juce::String IOSurfaceProvider::getIPCFifoPath() const
{
    return juce::String(pImpl->getIPCFifoPath());
}

}  // namespace juce_cmp
