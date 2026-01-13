// SPDX-FileCopyrightText: 2026 Luciano Iam <oss@lucianoiam.com>
// SPDX-License-Identifier: MIT

#include "Ipc.h"

#if JUCE_MAC || JUCE_LINUX
#include <unistd.h>
#endif

namespace juce_cmp
{

Ipc::Ipc() = default;

Ipc::~Ipc()
{
    stop();
}

void Ipc::setSocketFD(int fd)
{
    socketFD = fd;
}

void Ipc::startReceiving()
{
    if (running.load()) return;
    if (socketFD < 0) return;

    running.store(true);
    readerThread = std::thread([this]() { readerLoop(); });
}

void Ipc::stop()
{
    running.store(false);

    if (readerThread.joinable())
        readerThread.join();

#if JUCE_MAC || JUCE_LINUX
    if (socketFD >= 0)
    {
        close(socketFD);
        socketFD = -1;
    }
#endif
}

// =============================================================================
// TX: Host → UI
// =============================================================================

void Ipc::sendInput(InputEvent& event)
{
    if (socketFD < 0) return;

#if JUCE_MAC || JUCE_LINUX
    uint8_t prefix = EVENT_TYPE_INPUT;
    ssize_t written = write(socketFD, &prefix, 1);
    if (written != 1)
    {
        socketFD = -1;
        return;
    }

    written = write(socketFD, &event, sizeof(InputEvent));
    if (written != sizeof(InputEvent))
        socketFD = -1;
#endif
}

void Ipc::sendEvent(const juce::ValueTree& tree)
{
    if (socketFD < 0) return;

    juce::MemoryOutputStream stream;
    tree.writeToStream(stream);

    const void* data = stream.getData();
    uint32_t dataSize = static_cast<uint32_t>(stream.getDataSize());

#if JUCE_MAC || JUCE_LINUX
    uint8_t prefix = EVENT_TYPE_JUCE;
    ssize_t written = write(socketFD, &prefix, 1);
    if (written != 1)
    {
        socketFD = -1;
        return;
    }

    written = write(socketFD, &dataSize, 4);
    if (written != 4)
    {
        socketFD = -1;
        return;
    }

    written = write(socketFD, data, dataSize);
    if (written != static_cast<ssize_t>(dataSize))
        socketFD = -1;
#endif
}

// =============================================================================
// RX: UI → Host
// =============================================================================

void Ipc::readerLoop()
{
    while (running.load())
    {
        uint8_t eventType = 0;
        if (readFully(&eventType, 1) != 1)
            break;

        switch (eventType)
        {
            case EVENT_TYPE_CMP:
                handleCmpEvent();
                break;
            case EVENT_TYPE_JUCE:
                handleJuceEvent();
                break;
            default:
                break;
        }
    }
}

void Ipc::handleCmpEvent()
{
    uint8_t subtype = 0;
    if (readFully(&subtype, 1) != 1)
        return;

    if (subtype == CMP_EVENT_SURFACE_READY && onFrameReady)
    {
        juce::MessageManager::callAsync([this]() {
            if (onFrameReady)
                onFrameReady();
        });
    }
}

void Ipc::handleJuceEvent()
{
    uint32_t size = 0;
    if (readFully(&size, sizeof(size)) != sizeof(size))
        return;

    if (size == 0 || size > 1024 * 1024)
        return;

    juce::MemoryBlock data(size);
    if (readFully(data.getData(), size) != static_cast<ssize_t>(size))
        return;

    auto tree = juce::ValueTree::readFromData(data.getData(), size);
    if (tree.isValid() && onEvent)
    {
        juce::MessageManager::callAsync([this, tree]() {
            if (onEvent)
                onEvent(tree);
        });
    }
}

ssize_t Ipc::readFully(void* buffer, size_t size)
{
    size_t totalRead = 0;
    auto* ptr = static_cast<uint8_t*>(buffer);

    while (totalRead < size && running.load())
    {
        ssize_t n = ::read(socketFD, ptr + totalRead, size - totalRead);
        if (n <= 0) return totalRead > 0 ? static_cast<ssize_t>(totalRead) : n;
        totalRead += static_cast<size_t>(n);
    }
    return static_cast<ssize_t>(totalRead);
}

}  // namespace juce_cmp
