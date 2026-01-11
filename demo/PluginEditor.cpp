// SPDX-FileCopyrightText: 2026 Luciano Iam <oss@lucianoiam.com>
// SPDX-License-Identifier: MIT

/**
 * PluginEditor - JUCE editor that hosts the Compose UI via ComposeComponent.
 *
 * The editor displays a loading message until the ComposeComponent's native
 * view covers it with the child process rendering.
 */
#include "PluginEditor.h"

PluginEditor::PluginEditor(PluginProcessor& p)
    : AudioProcessorEditor(&p), processorRef(p)
{
    setSize(768, 480);
    setResizable(true, true);  // Keep native corner for AU plugin compatibility
    setResizeLimits(400, 300, 2048, 2048);
    juce_cmp::helpers::hideResizeHandle(*this);

    // Set up loading preview from embedded data
    // NOTE: Background color should match Compose UI background in UserInterface.kt
    composeComponent.setLoadingPreview(
        juce::ImageFileFormat::loadFrom(loading_preview_png, loading_preview_png_len),
        juce::Colour(0xFF6F97FF));

    // Wire up UI→Host events (interpret JuceValueTree as parameter changes)
    composeComponent.onEvent([&p](const juce::ValueTree& tree) {
        if (tree.getType() == juce::Identifier("param"))
        {
            auto paramId = static_cast<int>(tree.getProperty("id", -1));
            auto value = static_cast<float>(static_cast<double>(tree.getProperty("value", 0.0)));

            switch (paramId) {
                case 0:
                    if (p.shapeParameter != nullptr)
                        p.shapeParameter->setValueNotifyingHost(value);
                    break;
                // Add more parameters here as needed
            }
        }
    });

    // Wire up Host→UI parameter changes (automation from DAW, etc.)
    p.setParameterChangedCallback([this](int paramIndex, float value) {
        // Forward to Compose UI as event of type JUCE with ValueTree payload
        juce::ValueTree tree("param");
        tree.setProperty("id", paramIndex, nullptr);
        tree.setProperty("value", static_cast<double>(value), nullptr);
        composeComponent.sendEvent(tree);
    });

    // Send initial parameter values when child process is ready
    composeComponent.onProcessReady([this, &p]() {
        if (p.shapeParameter != nullptr) {
            juce::ValueTree tree("param");
            tree.setProperty("id", 0, nullptr);
            tree.setProperty("value", static_cast<double>(p.shapeParameter->get()), nullptr);
            composeComponent.sendEvent(tree);
        }
        // Add more parameters here as needed
    });

    // Hide loading text when first frame is rendered
    composeComponent.onFirstFrame([this] {
        uiReady = true;
        this->repaint();
    });

    addAndMakeVisible(composeComponent);
    repaint();  // Trigger initial paint to show "Starting UI..." text
}

PluginEditor::~PluginEditor()
{
    // Clear the callback to avoid dangling reference
    processorRef.setParameterChangedCallback(nullptr);
}

void PluginEditor::paint(juce::Graphics& g)
{
    juce::ignoreUnused(g);
    // Loading preview is now handled by ComposeComponent
}

void PluginEditor::paintOverChildren(juce::Graphics& g)
{
    if (uiReady)
        return;

    g.setColour(juce::Colour(0xFF444444));  // Match Compose Color.DarkGray
    g.setFont(juce::FontOptions(15.0f));
    g.drawFittedText("Starting UI...", getLocalBounds(), juce::Justification::centred, 1);
}

void PluginEditor::resized()
{
    composeComponent.setBounds(getLocalBounds());
}
