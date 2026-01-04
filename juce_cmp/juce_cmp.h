/*******************************************************************************
 BEGIN_JUCE_MODULE_DECLARATION

  ID:               juce_cmp
  vendor:           lucianoiam
  version:          0.0.1
  name:             Compose Multiplatform Embedding
  description:      Embed Compose Multiplatform UI in JUCE plugins via IOSurface
  website:          https://github.com/lucianoiam/juce-cmp
  license:          MIT

  dependencies:     juce_gui_basics, juce_audio_processors
  OSXFrameworks:    IOSurface CoreVideo

 END_JUCE_MODULE_DECLARATION
*******************************************************************************/

#pragma once

#include <juce_gui_basics/juce_gui_basics.h>
#include <juce_audio_processors/juce_audio_processors.h>

namespace juce_cmp
{
    // Forward declarations
    class IOSurfaceComponent;
    class IOSurfaceProvider;
}

// Internal implementation headers
#include "juce_cmp/input_protocol.h"
#include "juce_cmp/ui_protocol.h"
#include "juce_cmp/InputSender.h"
#include "juce_cmp/UIReceiver.h"
#include "juce_cmp/IOSurfaceProvider.h"
#include "juce_cmp/IOSurfaceComponent.h"
#include "juce_cmp/LoadingPreview.h"
