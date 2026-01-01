/**
 * PluginEditor - JUCE editor that hosts the Compose UI via IOSurfaceComponent.
 *
 * The editor displays a loading message until the IOSurfaceComponent's native
 * view covers it with the child process rendering.
 */
#include "PluginEditor.h"

PluginEditor::PluginEditor(PluginProcessor& p)
    : AudioProcessorEditor(&p), processorRef(p)
{
    setSize(800, 600);
    setResizable(true, true);
    setResizeLimits(400, 300, 2048, 2048);
    
    // Wire up UI→Host parameter changes
    surfaceComponent.onSetParameter([&p](uint32_t paramId, float value) {
        switch (paramId) {
            case 0: p.shape.store(value); break;
            // Add more parameters here as needed
        }
    });
    
    addAndMakeVisible(surfaceComponent);
}

PluginEditor::~PluginEditor()
{
}

void PluginEditor::paint(juce::Graphics& g)
{
    // Standard JUCE boilerplate style - will be obscured by IOSurfaceComponent
    g.fillAll(getLookAndFeel().findColour(juce::ResizableWindow::backgroundColourId));
    
    g.setColour(juce::Colours::white);
    g.setFont(juce::FontOptions(15.0f));
    g.drawFittedText("Starting child process...", getLocalBounds(), juce::Justification::centred, 1);
}

void PluginEditor::resized()
{
    surfaceComponent.setBounds(getLocalBounds());
}
