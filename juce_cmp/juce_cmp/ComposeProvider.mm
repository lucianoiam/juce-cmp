// SPDX-FileCopyrightText: 2026 Luciano Iam <oss@lucianoiam.com>
// SPDX-License-Identifier: MIT

/**
 * ComposeProvider - Creates shared surfaces and manages the child UI process.
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
#include "ComposeProvider.h"
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

class ComposeProvider::Impl
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

        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Wdeprecated-declarations"
        NSDictionary* props = @{
            (id)kIOSurfaceWidth: @(w),
            (id)kIOSurfaceHeight: @(h),
            (id)kIOSurfaceBytesPerElement: @4,
            (id)kIOSurfacePixelFormat: @((uint32_t)'BGRA'),
            (id)kIOSurfaceIsGlobal: @YES  // Required for cross-process lookup
        };
        #pragma clang diagnostic pop
        
        surface = IOSurfaceCreate((__bridge CFDictionaryRef)props);
        
        if (surface != nullptr)
        {
            //DBG("ComposeProvider: Created surface " + juce::String(w) + "x" + juce::String(h)
            //    + ", ID=" + juce::String(IOSurfaceGetID(surface)));
            return true;
        }
        
        DBG("ComposeProvider: Failed to create surface");
        return false;
#else
        juce::ignoreUnused(w, h);
        DBG("ComposeProvider: Not implemented on this platform");
        return false;
#endif
    }

    uint32_t resizeSurface(int w, int h)
    {
#if JUCE_MAC
        surfaceWidth = w;
        surfaceHeight = h;

        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Wdeprecated-declarations"
        NSDictionary* props = @{
            (id)kIOSurfaceWidth: @(w),
            (id)kIOSurfaceHeight: @(h),
            (id)kIOSurfaceBytesPerElement: @4,
            (id)kIOSurfacePixelFormat: @((uint32_t)'BGRA'),
            (id)kIOSurfaceIsGlobal: @YES
        };
        #pragma clang diagnostic pop

        IOSurfaceRef newSurface = IOSurfaceCreate((__bridge CFDictionaryRef)props);
        if (newSurface != nullptr)
        {
            // Keep previous surface alive - view may still be displaying it
            if (previousSurface != nullptr)
                CFRelease(previousSurface);
            previousSurface = surface;
            surface = newSurface;
            return IOSurfaceGetID(surface);
        }
        return 0;
#else
        juce::ignoreUnused(w, h);
        return 0;
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
            DBG("ComposeProvider: No surface, cannot launch child");
            return false;
        }

        // Verify executable exists using JUCE File API
        juce::File execFile(executable);
        if (!execFile.existsAsFile())
        {
            DBG("ComposeProvider: Executable not found: " + executable);
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
            DBG("ComposeProvider: Failed to create stdin pipe");
            return false;
        }

        // Create pipe for stdout (UI→Host IPC: JuceValueTree messages)
        int stdoutPipes[2];
        if (pipe(stdoutPipes) != 0)
        {
            DBG("ComposeProvider: Failed to create stdout pipe");
            close(stdinPipes[0]);
            close(stdinPipes[1]);
            return false;
        }
        std::string scaleArg = "--scale=" + std::to_string(scale);

        childPid = fork();
        
        if (childPid == 0)
        {
            // Child process
            close(stdinPipes[1]);   // Close write end of stdin pipe
            close(stdoutPipes[0]);  // Close read end of stdout pipe
            
            dup2(stdinPipes[0], STDIN_FILENO);   // Redirect stdin
            dup2(stdoutPipes[1], STDOUT_FILENO); // Redirect stdout
            close(stdinPipes[0]);
            close(stdoutPipes[1]);

            if (!workDir.empty())
                chdir(workDir.c_str());

            execl(execPath.c_str(), 
                  execPath.c_str(), 
                  "--embed", 
                  surfaceArg.c_str(), 
                  scaleArg.c_str(),
                  nullptr);
            
            // If exec fails, exit child
            _exit(1);
        }
        else if (childPid > 0)
        {
            // Parent process
            close(stdinPipes[0]);   // Close read end of stdin pipe
            close(stdoutPipes[1]);  // Close write end of stdout pipe
            
            stdinPipeFD = stdinPipes[1];
            stdoutPipeFD = stdoutPipes[0];

            //DBG("ComposeProvider: Launched child PID " + juce::String(childPid)
            //    + " with surface ID " + juce::String(IOSurfaceGetID(surface)));
            return true;
        }
        else
        {
            DBG("ComposeProvider: Fork failed");
            close(stdinPipes[0]);
            close(stdinPipes[1]);
            close(stdoutPipes[0]);
            close(stdoutPipes[1]);
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
        
        // Close stdout pipe after child has exited
        if (stdoutPipeFD >= 0)
        {
            close(stdoutPipeFD);
            stdoutPipeFD = -1;
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

    int getStdoutPipeFD() const
    {
        return stdoutPipeFD;
    }

private:
    void releaseSurface()
    {
#if JUCE_MAC
        if (previousSurface != nullptr)
        {
            CFRelease(previousSurface);
            previousSurface = nullptr;
        }
        if (surface != nullptr)
        {
            CFRelease(surface);
            surface = nullptr;
        }
#endif
    }

#if JUCE_MAC
    IOSurfaceRef surface = nullptr;
    IOSurfaceRef previousSurface = nullptr;  // Keep alive during resize transition
    pid_t childPid = 0;
#endif
    int stdinPipeFD = -1;
    int stdoutPipeFD = -1;
    int surfaceWidth = 0;
    int surfaceHeight = 0;
};

// Public interface - delegates to Impl
ComposeProvider::ComposeProvider() : pImpl(std::make_unique<Impl>()) {}
ComposeProvider::~ComposeProvider() = default;

bool ComposeProvider::createSurface(int width, int height) 
{ 
    return pImpl->createSurface(width, height); 
}

uint32_t ComposeProvider::resizeSurface(int width, int height)
{
    return pImpl->resizeSurface(width, height);
}

uint32_t ComposeProvider::getSurfaceID() const 
{ 
    return pImpl->getSurfaceID(); 
}

void* ComposeProvider::getNativeSurface() const 
{ 
    return pImpl->getNativeSurface(); 
}

int ComposeProvider::getWidth() const 
{ 
    return pImpl->getWidth(); 
}

int ComposeProvider::getHeight() const 
{ 
    return pImpl->getHeight(); 
}

bool ComposeProvider::launchChild(const std::string& executable, float scale, const std::string& workingDir) 
{ 
    return pImpl->launchChild(juce::String(executable), scale, juce::String(workingDir)); 
}

void ComposeProvider::stopChild() 
{ 
    pImpl->stopChild(); 
}

bool ComposeProvider::isChildRunning() const 
{ 
    return pImpl->isChildRunning(); 
}

int ComposeProvider::getInputPipeFD() const 
{ 
    return pImpl->getInputPipeFD(); 
}

int ComposeProvider::getStdoutPipeFD() const 
{ 
    return pImpl->getStdoutPipeFD(); 
}

}  // namespace juce_cmp
