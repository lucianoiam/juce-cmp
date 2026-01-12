// SPDX-FileCopyrightText: 2026 Luciano Iam <oss@lucianoiam.com>
// SPDX-License-Identifier: MIT

/*******************************************************************************
 BEGIN_JUCE_MODULE_DECLARATION

  ID:               juce_cmp
  vendor:           lucianoiam
  version:          0.0.1
  name:             Compose Multiplatform Embedding
  description:      Embed Compose Multiplatform UI in JUCE plugins via IOSurface
  website:          https://github.com/lucianoiam/juce-cmp
  license:          MIT

  dependencies:     juce_gui_basics, juce_audio_processors, juce_data_structures
  OSXFrameworks:    IOSurface CoreVideo

 END_JUCE_MODULE_DECLARATION
*******************************************************************************/

#pragma once

#include <juce_gui_basics/juce_gui_basics.h>
#include <juce_audio_processors/juce_audio_processors.h>
#include <juce_data_structures/juce_data_structures.h>

namespace juce_cmp
{
    // Forward declarations
    class ComposeComponent;
    class ComposeProvider;
}

// Internal implementation headers
#include "juce_cmp/ipc_protocol.h"
#include "juce_cmp/InputEvent.h"
#include "juce_cmp/Ipc.h"
#include "juce_cmp/ComposeProvider.h"
#include "juce_cmp/ComposeComponent.h"
#include "juce_cmp/ui_helpers.h"
