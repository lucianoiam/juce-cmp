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
    
    // Load the preview image from embedded data
    loadingPreviewImage = juce::ImageFileFormat::loadFrom(juce_cmp::loading_preview_png, juce_cmp::loading_preview_png_len);
    
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
    // Light purple background matching the Compose UI
    g.fillAll(juce::Colour(0xFFE6D6F2));
    
    // Draw the loading preview image scaled to fit
    if (loadingPreviewImage.isValid())
    {
        // Scale image to fit while maintaining aspect ratio
        float imageAspect = (float)loadingPreviewImage.getWidth() / loadingPreviewImage.getHeight();
        float boundsAspect = (float)getWidth() / getHeight();
        
        int drawWidth, drawHeight, drawX, drawY;
        if (imageAspect > boundsAspect)
        {
            // Image is wider - fit to width
            drawWidth = getWidth();
            drawHeight = (int)(getWidth() / imageAspect);
            drawX = 0;
            drawY = (getHeight() - drawHeight) / 2;
        }
        else
        {
            // Image is taller - fit to height
            drawHeight = getHeight();
            drawWidth = (int)(getHeight() * imageAspect);
            drawX = (getWidth() - drawWidth) / 2;
            drawY = 0;
        }
        
        g.drawImage(loadingPreviewImage, drawX, drawY, drawWidth, drawHeight,
                    0, 0, loadingPreviewImage.getWidth(), loadingPreviewImage.getHeight());
    }
    
    // Draw loading text centered on top of the image
    g.setColour(juce::Colours::black);
    g.setFont(juce::FontOptions(15.0f));
    g.drawFittedText("Starting UI...", getLocalBounds(), juce::Justification::centred, 1);
}

void PluginEditor::resized()
{
    surfaceComponent.setBounds(getLocalBounds());
}
