// SPDX-FileCopyrightText: 2026 Luciano Iam <oss@lucianoiam.com>
// SPDX-License-Identifier: MIT

#include "MachPort.h"

#if __APPLE__
#include <mach/mach.h>
#include <servers/bootstrap.h>
#include <unistd.h>
#include <cstdio>
#endif

namespace juce_cmp
{

MachPort::MachPort() = default;

MachPort::~MachPort()
{
    destroyServer();
}

std::string MachPort::createServer()
{
#if __APPLE__
    // Generate unique service name using PID
    char name[64];
    snprintf(name, sizeof(name), "com.juce-cmp.surface.%d", getpid());
    serviceName_ = name;

    // Check in with bootstrap server - creates the service and gives us a receive port
    mach_port_t port;
    kern_return_t kr = bootstrap_check_in(bootstrap_port, const_cast<char*>(serviceName_.c_str()), &port);
    if (kr != KERN_SUCCESS)
    {
        fprintf(stderr, "bootstrap_check_in failed: %d (%s)\n", kr, mach_error_string(kr));
        serviceName_.clear();
        return "";
    }

    serverPort_ = (uint32_t)port;
    fprintf(stderr, "Registered Mach service: %s\n", serviceName_.c_str());
    return serviceName_;
#else
    return "";
#endif
}

bool MachPort::waitForClient()
{
#if __APPLE__
    if (serverPort_ == 0)
        return false;

    // Wait for client to connect and send us its receive port
    // Client sends a message with a port descriptor containing its receive port
    struct {
        mach_msg_header_t header;
        mach_msg_body_t body;
        mach_msg_port_descriptor_t portDescriptor;
        mach_msg_trailer_t trailer;
    } connectMsg = {};

    kern_return_t kr = mach_msg(
        &connectMsg.header,
        MACH_RCV_MSG,
        0,
        sizeof(connectMsg),
        (mach_port_t)serverPort_,
        MACH_MSG_TIMEOUT_NONE,
        MACH_PORT_NULL
    );

    if (kr != KERN_SUCCESS)
    {
        fprintf(stderr, "waitForClient: mach_msg receive failed: %d (%s)\n", kr, mach_error_string(kr));
        return false;
    }

    // Extract client's port - this is a send right to client's receive port
    clientPort_ = (uint32_t)connectMsg.portDescriptor.name;
    fprintf(stderr, "Client connected, got send right to port %u\n", clientPort_);

    return true;
#else
    return false;
#endif
}

bool MachPort::sendPort(uint32_t machPort)
{
#if __APPLE__
    if (clientPort_ == 0)
    {
        fprintf(stderr, "sendPort: no client connected\n");
        return false;
    }

    // Send IOSurface port to client via the established channel
    struct {
        mach_msg_header_t header;
        mach_msg_body_t body;
        mach_msg_port_descriptor_t portDescriptor;
    } msg = {};

    msg.header.msgh_bits = MACH_MSGH_BITS_COMPLEX | MACH_MSGH_BITS(MACH_MSG_TYPE_COPY_SEND, 0);
    msg.header.msgh_size = sizeof(msg);
    msg.header.msgh_remote_port = (mach_port_t)clientPort_;
    msg.header.msgh_local_port = MACH_PORT_NULL;
    msg.header.msgh_id = 1;  // Surface port message

    msg.body.msgh_descriptor_count = 1;

    msg.portDescriptor.name = (mach_port_t)machPort;
    msg.portDescriptor.disposition = MACH_MSG_TYPE_COPY_SEND;
    msg.portDescriptor.type = MACH_MSG_PORT_DESCRIPTOR;

    kern_return_t kr = mach_msg(
        &msg.header,
        MACH_SEND_MSG,
        sizeof(msg),
        0,
        MACH_PORT_NULL,
        MACH_MSG_TIMEOUT_NONE,
        MACH_PORT_NULL
    );

    if (kr != KERN_SUCCESS)
    {
        fprintf(stderr, "sendPort: mach_msg send failed: %d (%s)\n", kr, mach_error_string(kr));
        return false;
    }

    fprintf(stderr, "Sent IOSurface port %u to client\n", machPort);
    return true;
#else
    (void)machPort;
    return false;
#endif
}

void MachPort::destroyServer()
{
#if __APPLE__
    if (clientPort_ != 0)
    {
        mach_port_deallocate(mach_task_self(), (mach_port_t)clientPort_);
        clientPort_ = 0;
    }
    if (serverPort_ != 0)
    {
        mach_port_deallocate(mach_task_self(), (mach_port_t)serverPort_);
        serverPort_ = 0;
    }
    serviceName_.clear();
#endif
}

}  // namespace juce_cmp
