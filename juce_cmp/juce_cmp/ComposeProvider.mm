// SPDX-FileCopyrightText: 2026 Luciano Iam <oss@lucianoiam.com>
// SPDX-License-Identifier: MIT

/**
 * ComposeProvider - Coordinates all components needed to display Compose UI.
 *
 * This is a pure coordinator with no platform-specific code.
 * Platform details are handled by Surface, SurfaceView, ChildProcess, and Ipc.
 */
#include "ComposeProvider.h"
#include "Surface.h"
#include "SurfaceView.h"
#include "ChildProcess.h"
#include "InputEvent.h"
#include "Ipc.h"

namespace juce_cmp
{

class ComposeProvider::Impl
{
public:
    Impl(ComposeProvider& o) : owner(o) {}

    ~Impl()
    {
        stop();
    }

    bool start(int width, int height, float s, void* peerView)
    {
        if (running) return false;

        scale = s;
        int pixelW = static_cast<int>(width * scale);
        int pixelH = static_cast<int>(height * scale);

        if (!surface.create(pixelW, pixelH))
            return false;

        if (!childProcess.launch(surface.getID(), scale))
        {
            surface.release();
            return false;
        }

        // Set up IPC
        ipc.setWriteFD(childProcess.getStdinFD());
        ipc.setReadFD(childProcess.getStdoutFD());
        ipc.setEventHandler([this](const juce::ValueTree& tree) {
            if (owner.eventHandler)
                owner.eventHandler(tree);
        });
        ipc.setFirstFrameHandler([this]() {
            if (owner.firstFrameHandler)
                owner.firstFrameHandler();
        });
        ipc.startReceiving();

        // Attach native view
        surfaceView.attach(peerView);
        surfaceView.setSurface(surface.getNativeHandle());
        surfaceView.setScale(scale);

        running = true;

        if (owner.readyHandler)
            owner.readyHandler();

        return true;
    }

    void stop()
    {
        if (!running) return;

        surfaceView.detach();
        childProcess.stop();
        ipc.stop();
        surface.release();

        running = false;
    }

    bool isRunning() const { return running; }

    void sendInput(InputEvent& event)
    {
        ipc.sendInput(event);
    }

    void sendEvent(const juce::ValueTree& tree)
    {
        ipc.sendEvent(tree);
    }

    void updateBounds(int x, int y, int w, int h)
    {
        surfaceView.setFrame(x, y, w, h);
    }

    void resize(int width, int height)
    {
        int pixelW = static_cast<int>(width * scale);
        int pixelH = static_cast<int>(height * scale);

        uint32_t newSurfaceID = surface.resize(pixelW, pixelH);
        if (newSurfaceID != 0)
        {
            auto e = InputEventFactory::resize(pixelW, pixelH, scale, newSurfaceID);
            ipc.sendInput(e);
            surfaceView.setPendingSurface(surface.getNativeHandle());
        }
    }

private:
    ComposeProvider& owner;

    Surface surface;
    SurfaceView surfaceView;
    ChildProcess childProcess;
    Ipc ipc;

    bool running = false;
    float scale = 1.0f;
};

// =============================================================================
// Public interface
// =============================================================================

ComposeProvider::ComposeProvider() : pImpl(std::make_unique<Impl>(*this)) {}
ComposeProvider::~ComposeProvider() = default;

bool ComposeProvider::start(int width, int height, float scale, void* peerView)
{
    return pImpl->start(width, height, scale, peerView);
}

void ComposeProvider::stop()
{
    pImpl->stop();
}

bool ComposeProvider::isRunning() const
{
    return pImpl->isRunning();
}

void ComposeProvider::sendInput(InputEvent& event)
{
    pImpl->sendInput(event);
}

void ComposeProvider::sendEvent(const juce::ValueTree& tree)
{
    pImpl->sendEvent(tree);
}

void ComposeProvider::updateBounds(int x, int y, int width, int height)
{
    pImpl->updateBounds(x, y, width, height);
}

void ComposeProvider::resize(int width, int height)
{
    pImpl->resize(width, height);
}

}  // namespace juce_cmp
