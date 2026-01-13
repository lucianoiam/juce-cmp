// SPDX-FileCopyrightText: 2026 Luciano Iam <oss@lucianoiam.com>
// SPDX-License-Identifier: MIT

#pragma once

#include <cstdint>
#include <string>

namespace juce_cmp
{

/**
 * ChildProcess - Manages the child UI process lifecycle.
 *
 * Uses fork/exec on POSIX systems with a Unix socket pair for IPC.
 * Windows implementation will use CreateProcess (TODO).
 */
class ChildProcess
{
public:
    ChildProcess();
    ~ChildProcess();

    // Non-copyable
    ChildProcess(const ChildProcess&) = delete;
    ChildProcess& operator=(const ChildProcess&) = delete;

    /** Launch the child process with the given executable and arguments. */
    bool launch(const std::string& executable,
                float scale,
                const std::string& workingDir = "");

    /** Stop the child process gracefully, with fallback to force kill. */
    void stop();

    /** Check if child is still running. */
    bool isRunning() const;

    /** Get the socket file descriptor for IPC with child. */
    int getSocketFD() const;

private:
#if __APPLE__ || __linux__
    pid_t childPid_ = 0;
#endif
    int socketFD_ = -1;
};

}  // namespace juce_cmp
