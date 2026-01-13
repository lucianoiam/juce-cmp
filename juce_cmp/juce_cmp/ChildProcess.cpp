// SPDX-FileCopyrightText: 2026 Luciano Iam <oss@lucianoiam.com>
// SPDX-License-Identifier: MIT

#include "ChildProcess.h"

#if __APPLE__ || __linux__
#include <unistd.h>
#include <signal.h>
#include <sys/wait.h>
#include <sys/stat.h>
#include <sys/socket.h>
#endif

namespace juce_cmp
{

ChildProcess::ChildProcess() = default;

ChildProcess::~ChildProcess()
{
    stop();
}

bool ChildProcess::launch(const std::string& executable,
                          float scale,
                          const std::string& workingDir)
{
#if __APPLE__ || __linux__
    // Verify executable exists
    struct stat st;
    if (stat(executable.c_str(), &st) != 0)
        return false;

    std::string scaleArg = "--scale=" + std::to_string(scale);

    // Create Unix socket pair for bidirectional IPC
    int sockets[2];
    if (socketpair(AF_UNIX, SOCK_STREAM, 0, sockets) != 0)
        return false;

    childPid_ = fork();

    if (childPid_ == 0)
    {
        // Child process
        close(sockets[0]);  // Close parent's end

        // Pass socket FD as argument
        std::string socketArg = "--socket-fd=" + std::to_string(sockets[1]);

        if (!workingDir.empty())
            chdir(workingDir.c_str());

        execl(executable.c_str(),
              executable.c_str(),
              socketArg.c_str(),
              scaleArg.c_str(),
              nullptr);

        // If exec fails, exit child
        _exit(1);
    }
    else if (childPid_ > 0)
    {
        // Parent process
        close(sockets[1]);  // Close child's end
        socketFD_ = sockets[0];

        return true;
    }
    else
    {
        // Fork failed
        close(sockets[0]);
        close(sockets[1]);
        return false;
    }
#else
    (void)executable;
    (void)scale;
    (void)workingDir;
    return false;
#endif
}

void ChildProcess::stop()
{
#if __APPLE__ || __linux__
    // Close socket first - signals EOF to child
    if (socketFD_ >= 0)
    {
        close(socketFD_);
        socketFD_ = -1;
    }

    // Wait for child to exit with timeout, then force kill
    if (childPid_ > 0)
    {
        int status;
        // Give child 200ms to exit gracefully
        for (int i = 0; i < 20; ++i)
        {
            pid_t result = waitpid(childPid_, &status, WNOHANG);
            if (result != 0)
            {
                childPid_ = 0;
                break;
            }
            usleep(10000);  // 10ms
        }

        // If still alive, force kill
        if (childPid_ > 0)
        {
            kill(childPid_, SIGKILL);
            waitpid(childPid_, &status, 0);
            childPid_ = 0;
        }
    }
#endif
}

bool ChildProcess::isRunning() const
{
#if __APPLE__ || __linux__
    if (childPid_ <= 0)
        return false;
    return kill(childPid_, 0) == 0;
#else
    return false;
#endif
}

int ChildProcess::getSocketFD() const
{
    return socketFD_;
}

}  // namespace juce_cmp
