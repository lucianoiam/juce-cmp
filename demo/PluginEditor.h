// SPDX-FileCopyrightText: 2026 Luciano Iam <oss@lucianoiam.com>
// SPDX-License-Identifier: MIT

#pragma once

#include <juce_audio_processors/juce_audio_processors.h>
#include <juce_cmp/juce_cmp.h>
#include "PluginProcessor.h"
#include "LoadingPreview.h"  // Binary resource data

/**
 * Plugin Editor - hosts the ComposeComponent that displays Compose UI.
 */
class PluginEditor : public juce::AudioProcessorEditor
{
public:
    explicit PluginEditor(PluginProcessor&);
    ~PluginEditor() override;

    void paint(juce::Graphics&) override;
    void paintOverChildren(juce::Graphics&) override;
    void resized() override;

private:
    PluginProcessor& processorRef;
    juce_cmp::ComposeComponent composeComponent;
    bool uiReady = false;

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(PluginEditor)
};
