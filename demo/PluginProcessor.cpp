// SPDX-FileCopyrightText: 2026 Luciano Iam <oss@lucianoiam.com>
// SPDX-License-Identifier: MIT

/**
 * PluginProcessor - Audio processor with shape parameter for juce-cmp demo.
 *
 * Generates a tone that morphs between sine and square wave based on the
 * shape parameter, which is exposed to the AU/VST host for automation.
 */
#include "PluginProcessor.h"
#include "PluginEditor.h"

PluginProcessor::PluginProcessor()
    : AudioProcessor(BusesProperties()
                     .withOutput("Output", juce::AudioChannelSet::stereo(), true))
{
    addParameter(shapeParameter = new juce::AudioParameterFloat(
        { PARAM_SHAPE_ID, 1 },
        PARAM_SHAPE_NAME,
        0.0f,   // min
        1.0f,   // max
        0.0f    // default: sine wave
    ));
}

PluginProcessor::~PluginProcessor()
{
}

const juce::String PluginProcessor::getName() const
{
    return JucePlugin_Name;
}

bool PluginProcessor::acceptsMidi() const
{
    return false;
}

bool PluginProcessor::producesMidi() const
{
    return false;
}

bool PluginProcessor::isMidiEffect() const
{
    return false;
}

double PluginProcessor::getTailLengthSeconds() const
{
    return 0.0;
}

int PluginProcessor::getNumPrograms()
{
    return 1;
}

int PluginProcessor::getCurrentProgram()
{
    return 0;
}

void PluginProcessor::setCurrentProgram(int index)
{
    juce::ignoreUnused(index);
}

const juce::String PluginProcessor::getProgramName(int index)
{
    juce::ignoreUnused(index);
    return {};
}

void PluginProcessor::changeProgramName(int index, const juce::String& newName)
{
    juce::ignoreUnused(index, newName);
}

void PluginProcessor::prepareToPlay(double sampleRate, int samplesPerBlock)
{
    juce::ignoreUnused(samplesPerBlock);
    currentSampleRate = sampleRate;
    phase = 0.0;
}

void PluginProcessor::releaseResources()
{
}

bool PluginProcessor::isBusesLayoutSupported(const BusesLayout& layouts) const
{
    // Accept mono or stereo output
    if (layouts.getMainOutputChannelSet() != juce::AudioChannelSet::mono()
        && layouts.getMainOutputChannelSet() != juce::AudioChannelSet::stereo())
        return false;

    return true;
}

void PluginProcessor::processBlock(juce::AudioBuffer<float>& buffer, juce::MidiBuffer& midiMessages)
{
    juce::ignoreUnused(midiMessages);
    juce::ScopedNoDenormals noDenormals;

    const int numChannels = buffer.getNumChannels();
    const int numSamples = buffer.getNumSamples();
    const double phaseIncrement = frequency / currentSampleRate;
    const float shapeValue = shapeParameter->get();
    
    for (int sample = 0; sample < numSamples; ++sample)
    {
        // Generate sine wave
        const float sine = static_cast<float>(std::sin(phase * 2.0 * juce::MathConstants<double>::pi));
        
        // Generate square wave (sign of sine)
        const float square = sine >= 0.0f ? 1.0f : -1.0f;
        
        // Morph between sine and square based on shape parameter
        const float out = sine * (1.0f - shapeValue) + square * shapeValue;
        
        // Scale down to reasonable volume
        const float scaledOut = out * 0.3f;
        
        // Write to all channels
        for (int channel = 0; channel < numChannels; ++channel)
            buffer.setSample(channel, sample, scaledOut);
        
        // Advance phase
        phase += phaseIncrement;
        if (phase >= 1.0)
            phase -= 1.0;
    }
}

bool PluginProcessor::hasEditor() const
{
    return true;
}

juce::AudioProcessorEditor* PluginProcessor::createEditor()
{
    return new PluginEditor(*this);
}

void PluginProcessor::getStateInformation(juce::MemoryBlock& destData)
{
    auto xml = std::make_unique<juce::XmlElement>("State");
    xml->setAttribute(PARAM_SHAPE_ID, static_cast<double>(shapeParameter->get()));
    copyXmlToBinary(*xml, destData);
}

void PluginProcessor::setStateInformation(const void* data, int sizeInBytes)
{
    auto xml = getXmlFromBinary(data, sizeInBytes);
    if (xml != nullptr && xml->hasTagName("State"))
        *shapeParameter = static_cast<float>(xml->getDoubleAttribute(PARAM_SHAPE_ID, 0.0));
}

// Plugin instantiation
juce::AudioProcessor* JUCE_CALLTYPE createPluginFilter()
{
    return new PluginProcessor();
}
