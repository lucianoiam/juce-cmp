// SPDX-FileCopyrightText: 2026 Luciano Iam <oss@lucianoiam.com>
// SPDX-License-Identifier: MIT

#pragma once

#include <juce_core/juce_core.h>
#include <juce_data_structures/juce_data_structures.h>
#include <functional>
#include <thread>
#include <atomic>
#include <mutex>
#include <unistd.h>
#include "ipc_protocol.h"

namespace juce_cmp
{

/**
 * EventReceiver - Receives events from UI process (UI → host direction).
 *
 * Protocol: 1-byte event type followed by type-specific payload.
 * See ipc_protocol.h for details.
 *
 * Note: This is the C++ EventReceiver (UI → host direction).
 * The Kotlin EventReceiver in juce_cmp.events handles the opposite direction (host → UI).
 */
class EventReceiver
{
public:
    using EventHandler = std::function<void(const juce::ValueTree& tree)>;
    using FirstFrameHandler = std::function<void()>;

    EventReceiver() = default;
    ~EventReceiver() { stop(); }

    void setEventHandler(EventHandler handler) { onEvent = std::move(handler); }
    void setFirstFrameHandler(FirstFrameHandler handler) { onFirstFrame = std::move(handler); }

    void start(int stdoutPipeFD)
    {
        if (running.load()) return;
        if (stdoutPipeFD < 0) return;

        fd = stdoutPipeFD;
        running.store(true);

        readerThread = std::thread([this]() {
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
        });
    }

    void stop()
    {
        running.store(false);
        if (readerThread.joinable())
            readerThread.join();
    }

private:
    void handleCmpEvent()
    {
        uint8_t subtype = 0;
        if (readFully(&subtype, 1) != 1)
            return;

        if (subtype == CMP_SUBTYPE_FIRST_FRAME && onFirstFrame)
        {
            juce::MessageManager::callAsync([this]() {
                if (onFirstFrame)
                    onFirstFrame();
            });
        }
    }

    void handleJuceEvent()
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
        if (tree.isValid())
            enqueue(tree);
    }

    ssize_t readFully(void* buffer, size_t size)
    {
        size_t totalRead = 0;
        auto* ptr = static_cast<uint8_t*>(buffer);

        while (totalRead < size && running.load())
        {
            ssize_t n = ::read(fd, ptr + totalRead, size - totalRead);
            if (n <= 0) return totalRead > 0 ? static_cast<ssize_t>(totalRead) : n;
            totalRead += static_cast<size_t>(n);
        }
        return static_cast<ssize_t>(totalRead);
    }

    void enqueue(const juce::ValueTree& tree)
    {
        if (!onEvent) return;

        auto typeStr = tree.getType().toString();
        juce::String key = typeStr;
        if (typeStr == "param" && tree.hasProperty("id"))
            key += "_" + tree.getProperty("id").toString();

        {
            std::lock_guard<std::mutex> lock(pendingMutex);
            bool wasEmpty = pendingTrees.find(key) == pendingTrees.end();
            pendingTrees[key] = tree;
            if (!wasEmpty) return;
        }

        juce::MessageManager::callAsync([this, key]() {
            juce::ValueTree treeToDispatch;
            {
                std::lock_guard<std::mutex> lock(pendingMutex);
                auto it = pendingTrees.find(key);
                if (it != pendingTrees.end())
                {
                    treeToDispatch = it->second;
                    pendingTrees.erase(it);
                }
            }

            if (treeToDispatch.isValid() && onEvent)
                onEvent(treeToDispatch);
        });
    }

    int fd = -1;
    std::atomic<bool> running { false };
    std::thread readerThread;
    EventHandler onEvent;
    FirstFrameHandler onFirstFrame;

    std::mutex pendingMutex;
    std::map<juce::String, juce::ValueTree> pendingTrees;

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(EventReceiver)
};

}  // namespace juce_cmp
