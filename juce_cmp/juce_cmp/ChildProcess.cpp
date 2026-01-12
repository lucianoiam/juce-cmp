// SPDX-FileCopyrightText: 2026 Luciano Iam <oss@lucianoiam.com>
// SPDX-License-Identifier: MIT

#include "ChildProcess.h"

#if JUCE_MAC || JUCE_LINUX
#include <unistd.h>
#include <sys/wait.h>
#include <signal.h>
#endif

namespace juce_cmp
{

ChildProcess::ChildProcess() = default;

ChildProcess::~ChildProcess()
{
    stop();
}

bool ChildProcess::launch(uint32_t surfaceID, float scale)
{
#if JUCE_MAC || JUCE_LINUX
    // Find UI executable bundled in plugin
    auto execFile = juce::File::getSpecialLocation(juce::File::currentExecutableFile);
    auto macosDir = execFile.getParentDirectory();
    auto rendererPath = macosDir.getChildFile("ui");

    if (!rendererPath.existsAsFile())
    {
        DBG("ChildProcess: UI executable not found: " + rendererPath.getFullPathName());
        return false;
    }

    std::string surfaceArg = "--iosurface-id=" + std::to_string(surfaceID);
    std::string scaleArg = "--scale=" + std::to_string(scale);
    std::string execPath = rendererPath.getFullPathName().toStdString();

    int stdinPipes[2];
    if (pipe(stdinPipes) != 0) return false;

    int stdoutPipes[2];
    if (pipe(stdoutPipes) != 0)
    {
        close(stdinPipes[0]);
        close(stdinPipes[1]);
        return false;
    }

    childPid = fork();

    if (childPid == 0)
    {
        // Child process
        close(stdinPipes[1]);
        close(stdoutPipes[0]);
        dup2(stdinPipes[0], STDIN_FILENO);
        dup2(stdoutPipes[1], STDOUT_FILENO);
        close(stdinPipes[0]);
        close(stdoutPipes[1]);

        execl(execPath.c_str(), execPath.c_str(),
              surfaceArg.c_str(), scaleArg.c_str(), nullptr);
        _exit(1);
    }
    else if (childPid > 0)
    {
        // Parent process
        close(stdinPipes[0]);
        close(stdoutPipes[1]);
        stdinPipeFD = stdinPipes[1];
        stdoutPipeFD = stdoutPipes[0];
        return true;
    }
    else
    {
        // Fork failed
        close(stdinPipes[0]);
        close(stdinPipes[1]);
        close(stdoutPipes[0]);
        close(stdoutPipes[1]);
        return false;
    }
#else
    juce::ignoreUnused(surfaceID, scale);
    return false;
#endif
}

void ChildProcess::stop()
{
#if JUCE_MAC || JUCE_LINUX
    // Close stdin pipe first - signals EOF to child
    if (stdinPipeFD >= 0)
    {
        close(stdinPipeFD);
        stdinPipeFD = -1;
    }

    if (childPid > 0)
    {
        int status;
        // Give child 200ms to exit gracefully
        for (int i = 0; i < 20; ++i)
        {
            pid_t result = waitpid(childPid, &status, WNOHANG);
            if (result != 0)
            {
                childPid = 0;
                break;
            }
            usleep(10000);  // 10ms
        }

        // Force kill if still alive
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

bool ChildProcess::isRunning() const
{
#if JUCE_MAC || JUCE_LINUX
    if (childPid <= 0)
        return false;
    return kill(childPid, 0) == 0;
#else
    return false;
#endif
}

}  // namespace juce_cmp
