// SPDX-FileCopyrightText: 2026 Luciano Iam <oss@lucianoiam.com>
// SPDX-License-Identifier: MIT

#pragma once

#include <juce_core/juce_core.h>
#include <cstdint>

namespace juce_cmp
{

/**
 * ChildProcess - Manages the Compose UI child process.
 *
 * Handles fork/exec, stdin/stdout pipes, and graceful shutdown.
 */
class ChildProcess
{
public:
    ChildProcess();
    ~ChildProcess();

    /**
     * Launch the child process.
     * @param surfaceID IOSurface ID to pass to child
     * @param scale Backing scale factor
     * @return true if successfully launched
     */
    bool launch(uint32_t surfaceID, float scale);

    /** Stop the child process. */
    void stop();

    /** Returns true if child is running. */
    bool isRunning() const;

    /** Get stdin pipe FD for writing to child. */
    int getStdinFD() const { return stdinPipeFD; }

    /** Get stdout pipe FD for reading from child. */
    int getStdoutFD() const { return stdoutPipeFD; }

private:
#if JUCE_MAC || JUCE_LINUX
    pid_t childPid = 0;
#endif
    int stdinPipeFD = -1;
    int stdoutPipeFD = -1;

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(ChildProcess)
};

}  // namespace juce_cmp
