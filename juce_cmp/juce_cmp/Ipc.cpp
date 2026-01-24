// SPDX-FileCopyrightText: 2026 Luciano Iam <oss@lucianoiam.com>
// SPDX-License-Identifier: MIT

#include "Ipc.h"

#if JUCE_MAC || JUCE_LINUX
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <poll.h>
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
#if JUCE_MAC || JUCE_LINUX
    // Set non-blocking mode to prevent UI thread stalls
    if (fd >= 0)
    {
        int flags = fcntl(fd, F_GETFL, 0);
        if (flags >= 0)
            fcntl(fd, F_SETFL, flags | O_NONBLOCK);
    }
#endif
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
    if (!writeNonBlocking(&prefix, 1))
        return;
    writeNonBlocking(&event, sizeof(InputEvent));
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
    if (!writeNonBlocking(&prefix, 1))
        return;
    if (!writeNonBlocking(&dataSize, 4))
        return;
    writeNonBlocking(data, dataSize);
#endif
}

void Ipc::sendMidi(const juce::MidiMessage& message)
{
    if (socketFD < 0) return;

    auto size = static_cast<uint8_t>(message.getRawDataSize());
    if (size == 0 || size > 255) return;

#if JUCE_MAC || JUCE_LINUX
    uint8_t prefix = EVENT_TYPE_MIDI;
    if (!writeNonBlocking(&prefix, 1))
        return;
    if (!writeNonBlocking(&size, 1))
        return;
    writeNonBlocking(message.getRawData(), size);
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
            case EVENT_TYPE_MIDI:
                handleMidiEvent();
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

void Ipc::handleMidiEvent()
{
    uint8_t size = 0;
    if (readFully(&size, 1) != 1)
        return;

    if (size == 0 || size > 255)
        return;

    uint8_t data[256];
    if (readFully(data, size) != static_cast<ssize_t>(size))
        return;

    auto message = juce::MidiMessage(data, static_cast<int>(size));
    if (onMidi)
    {
        juce::MessageManager::callAsync([this, message]() {
            if (onMidi)
                onMidi(message);
        });
    }
}

ssize_t Ipc::readFully(void* buffer, size_t size)
{
    size_t totalRead = 0;
    auto* ptr = static_cast<uint8_t*>(buffer);

#if JUCE_MAC || JUCE_LINUX
    while (totalRead < size && running.load())
    {
        // Wait for data with timeout (allows checking running flag)
        struct pollfd pfd = { socketFD, POLLIN, 0 };
        int ready = poll(&pfd, 1, 100);  // 100ms timeout

        if (ready < 0)
            return -1;  // Error
        if (ready == 0)
            continue;   // Timeout, check running flag

        ssize_t n = ::read(socketFD, ptr + totalRead, size - totalRead);
        if (n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK))
            continue;
        if (n <= 0)
            return totalRead > 0 ? static_cast<ssize_t>(totalRead) : n;
        totalRead += static_cast<size_t>(n);
    }
#endif
    return static_cast<ssize_t>(totalRead);
}

bool Ipc::writeNonBlocking(const void* data, size_t size)
{
#if JUCE_MAC || JUCE_LINUX
    size_t totalWritten = 0;
    auto* ptr = static_cast<const uint8_t*>(data);

    // Try a few times with small delays for EAGAIN
    for (int attempts = 0; attempts < 3 && totalWritten < size; ++attempts)
    {
        ssize_t n = ::write(socketFD, ptr + totalWritten, size - totalWritten);
        if (n > 0)
        {
            totalWritten += static_cast<size_t>(n);
            attempts = 0;  // Reset on progress
        }
        else if (n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK))
        {
            // Socket buffer full - yield briefly and retry
            continue;
        }
        else
        {
            // Real error
            socketFD = -1;
            return false;
        }
    }

    if (totalWritten != size)
    {
        socketFD = -1;
        return false;
    }
    return true;
#else
    (void)data;
    (void)size;
    return false;
#endif
}

}  // namespace juce_cmp
