// SPDX-FileCopyrightText: 2026 Luciano Iam <oss@lucianoiam.com>
// SPDX-License-Identifier: MIT

#pragma once

#include <cstdint>
#include <string>

namespace juce_cmp
{

/**
 * MachPortIPC - Bidirectional Mach port channel for IOSurface sharing.
 *
 * Uses bootstrap server for initial handshake, then maintains a persistent
 * channel where the parent can push IOSurface Mach ports at any time.
 *
 * Flow:
 * 1. Parent: createServer() - registers with bootstrap
 * 2. Child: connects via bootstrap_look_up, sends its receive port
 * 3. Parent: waitForClient() - receives child's port, establishes channel
 * 4. Parent: sendPort() - pushes IOSurface ports (initial, resize, etc.)
 * 5. Child: receives ports via its receive port
 */
class MachPortIPC
{
public:
    MachPortIPC();
    ~MachPortIPC();

    // Non-copyable
    MachPortIPC(const MachPortIPC&) = delete;
    MachPortIPC& operator=(const MachPortIPC&) = delete;

    /**
     * Server side: Create a receive port and register with bootstrap server.
     * Returns the service name to pass to the client.
     */
    std::string createServer();

    /**
     * Server side: Wait for client to connect and establish channel.
     * Must be called before sendPort(). Blocks until client connects.
     * Returns true on success.
     */
    bool waitForClient();

    /**
     * Server side: Send a Mach port to the client.
     * Can be called multiple times after waitForClient().
     * Returns true on success.
     */
    bool sendPort(uint32_t machPort);

    /**
     * Cleanup server resources.
     */
    void destroyServer();

    /**
     * Get the registered service name (for passing to child process).
     */
    const std::string& getServiceName() const { return serviceName_; }

private:
#if __APPLE__
    uint32_t serverPort_ = 0;   // Bootstrap receive port
    uint32_t clientPort_ = 0;   // Send right to client's receive port
#endif
    std::string serviceName_;
};

}  // namespace juce_cmp
