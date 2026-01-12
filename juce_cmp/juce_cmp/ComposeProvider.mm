// SPDX-FileCopyrightText: 2026 Luciano Iam <oss@lucianoiam.com>
// SPDX-License-Identifier: MIT

/**
 * ComposeProvider - Coordinates shared surfaces and child UI process.
 */
#include "ComposeProvider.h"
#include <juce_core/juce_core.h>
#include <string>

namespace juce_cmp
{

class ComposeProvider::Impl
{
public:
    Impl() = default;
    ~Impl() = default;

    bool createSurface(int w, int h)
    {
        return surface.create(w, h);
    }

    uint32_t resizeSurface(int w, int h)
    {
        return surface.resize(w, h);
    }

    uint32_t getSurfaceID() const
    {
        return surface.getID();
    }

    void* getNativeSurface() const
    {
        return surface.getNativeHandle();
    }

    int getWidth() const { return surface.getWidth(); }
    int getHeight() const { return surface.getHeight(); }

    bool launchChild(const juce::String& executable, float scale, const juce::String& workingDir)
    {
        if (!surface.isValid())
        {
            DBG("ComposeProvider: No surface, cannot launch child");
            return false;
        }

        return child.launch(executable.toStdString(), surface.getID(), scale, workingDir.toStdString());
    }

    void stopChild()
    {
        child.stop();
    }

    bool isChildRunning() const
    {
        return child.isRunning();
    }

    int getInputPipeFD() const
    {
        return child.getStdinPipeFD();
    }

    int getStdoutPipeFD() const
    {
        return child.getStdoutPipeFD();
    }

private:
    Surface surface;
    ChildProcess child;
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
