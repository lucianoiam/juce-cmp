#pragma once

#include <juce_core/juce_core.h>
#include "../../common/ui_protocol.h"
#include <functional>
#include <thread>
#include <atomic>
#include <unistd.h>
#include <fcntl.h>

/**
 * UIReceiver - Reads binary messages from UI process via named pipe (FIFO).
 *
 * Runs a background thread that opens the FIFO (non-blocking to allow clean shutdown),
 * then reads UIMessageHeader + payload and dispatches to registered handlers.
 */
class UIReceiver
{
public:
    using SetParamHandler = std::function<void(uint32_t paramId, float value)>;

    UIReceiver() = default;
    ~UIReceiver() { stop(); }

    void setParamHandler(SetParamHandler handler) { onSetParam = std::move(handler); }

    void start(const juce::String& fifoPath)
    {
        if (running.load()) return;
        if (fifoPath.isEmpty()) return;
        
        path = fifoPath;
        running.store(true);
        
        readerThread = std::thread([this]() {
            // Blocking open - waits for child to open write end.
            // This is safe because stopChild() waits for child to exit first,
            // which closes the FIFO and unblocks this open (or subsequent reads).
            fd = open(path.toRawUTF8(), O_RDONLY);
            if (fd < 0)
            {
                DBG("UIReceiver: Failed to open FIFO");
                return;
            }
            
            UIMessageHeader header;
            
            while (running.load())
            {
                // Read header (8 bytes)
                ssize_t bytesRead = readFully(&header, sizeof(header));
                if (bytesRead != sizeof(header))
                    break;
                
                // Read payload
                if (header.payloadSize > 0 && header.payloadSize <= 1024)
                {
                    std::vector<uint8_t> payload(header.payloadSize);
                    bytesRead = readFully(payload.data(), header.payloadSize);
                    if (bytesRead != static_cast<ssize_t>(header.payloadSize))
                        break;
                    
                    dispatch(header.opcode, payload.data(), header.payloadSize);
                }
            }
            
            if (fd >= 0)
            {
                close(fd);
                fd = -1;
            }
        });
    }

    void stop()
    {
        running.store(false);
        // Close fd to unblock reader
        if (fd >= 0)
        {
            close(fd);
            fd = -1;
        }
        if (readerThread.joinable())
            readerThread.join();
    }

private:
    ssize_t readFully(void* buffer, size_t size)
    {
        size_t totalRead = 0;
        auto* ptr = static_cast<uint8_t*>(buffer);
        
        while (totalRead < size && running.load())
        {
            ssize_t n = ::read(fd, ptr + totalRead, size - totalRead);
            if (n <= 0) return totalRead > 0 ? static_cast<ssize_t>(totalRead) : n;
            totalRead += n;
        }
        return static_cast<ssize_t>(totalRead);
    }

    void dispatch(uint32_t opcode, const uint8_t* payload, uint32_t size)
    {
        switch (opcode)
        {
            case UI_OPCODE_SET_PARAM:
                if (size >= sizeof(UISetParamPayload) && onSetParam)
                {
                    auto* p = reinterpret_cast<const UISetParamPayload*>(payload);
                    // Call on message thread for thread safety
                    juce::MessageManager::callAsync([this, paramId = p->paramId, value = p->value]() {
                        if (onSetParam)
                            onSetParam(paramId, value);
                    });
                }
                break;
                
            default:
                break;
        }
    }

    juce::String path;
    int fd = -1;
    std::atomic<bool> running { false };
    std::thread readerThread;
    SetParamHandler onSetParam;

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(UIReceiver)
};
