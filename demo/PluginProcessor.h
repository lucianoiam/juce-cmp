// SPDX-FileCopyrightText: 2026 Luciano Iam <oss@lucianoiam.com>
// SPDX-License-Identifier: MIT

#pragma once

#include <juce_audio_processors/juce_audio_processors.h>
#include <functional>

/**
 * AudioProcessor with shape parameter exposed to AU/VST hosts.
 * 
 * Generates a tone that morphs between sine and square wave.
 * The shape parameter is automatable and saved with plugin state.
 * 
 * Implements Listener to notify the UI when host changes parameters.
 */
class PluginProcessor : public juce::AudioProcessor,
                        public juce::AudioProcessorParameter::Listener
{
public:
    static constexpr const char* PARAM_SHAPE_ID = "shape";
    static constexpr const char* PARAM_SHAPE_NAME = "Shape";
    
    PluginProcessor();
    ~PluginProcessor() override;

    void prepareToPlay(double sampleRate, int samplesPerBlock) override;
    void releaseResources() override;

    bool isBusesLayoutSupported(const BusesLayout& layouts) const override;

    void processBlock(juce::AudioBuffer<float>&, juce::MidiBuffer&) override;

    juce::AudioProcessorEditor* createEditor() override;
    bool hasEditor() const override;

    const juce::String getName() const override;

    bool acceptsMidi() const override;
    bool producesMidi() const override;
    bool isMidiEffect() const override;
    double getTailLengthSeconds() const override;

    int getNumPrograms() override;
    int getCurrentProgram() override;
    void setCurrentProgram(int index) override;
    const juce::String getProgramName(int index) override;
    void changeProgramName(int index, const juce::String& newName) override;

    void getStateInformation(juce::MemoryBlock& destData) override;
    void setStateInformation(const void* data, int sizeInBytes) override;

    // AudioProcessorParameter::Listener - called when host changes parameter
    void parameterValueChanged(int parameterIndex, float newValue) override;
    void parameterGestureChanged(int parameterIndex, bool gestureIsStarting) override;

    /// Callback for parameter changes (used by editor to sync UI)
    using ParameterChangedCallback = std::function<void(int paramIndex, float value)>;
    void setParameterChangedCallback(ParameterChangedCallback cb) { paramCallback = std::move(cb); }

    /// Shape parameter (0 = sine, 1 = square) - exposed to host
    juce::AudioParameterFloat* shapeParameter = nullptr;

private:
    ParameterChangedCallback paramCallback;
    double currentSampleRate = 44100.0;
    double phase = 0.0;
    static constexpr double frequency = 440.0;
    
    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(PluginProcessor)
};
