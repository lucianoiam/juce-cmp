#pragma once

#include <juce_audio_processors/juce_audio_processors.h>

/**
 * Passthrough AudioProcessor - does nothing to audio, just hosts the UI.
 * 
 * This processor exists to provide a standard JUCE plugin structure.
 * The real functionality is in the editor, which displays the Compose UI.
 */
class PluginProcessor : public juce::AudioProcessor
{
public:
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

    /// Shape parameter: 0 = sine, 1 = square, in-between = morph
    std::atomic<float> shape { 0.0f };

private:
    double currentSampleRate = 44100.0;
    double phase = 0.0;
    static constexpr double frequency = 440.0;
    
    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(PluginProcessor)
};
