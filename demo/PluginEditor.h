#pragma once

#include <juce_audio_processors/juce_audio_processors.h>
#include <juce_cmp/juce_cmp.h>
#include "PluginProcessor.h"

/**
 * Plugin Editor - hosts the IOSurfaceComponent that displays Compose UI.
 */
class PluginEditor : public juce::AudioProcessorEditor
{
public:
    explicit PluginEditor(PluginProcessor&);
    ~PluginEditor() override;

    void paint(juce::Graphics&) override;
    void resized() override;

private:
    PluginProcessor& processorRef;
    juce_cmp::IOSurfaceComponent surfaceComponent;
    juce::Image loadingPreviewImage;

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(PluginEditor)
};
