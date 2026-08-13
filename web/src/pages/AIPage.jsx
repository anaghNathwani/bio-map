import React from 'react'
import './StaticPage.css'
import './AIPage.css'

export default function AIPage() {
  return (
    <div className="static-page">
      <header className="static-page-header">
        <a href="/" className="static-page-back">← Map</a>
        <span className="static-page-logo"><a href="/" className="static-page-back">🐦 BirdMap</a></span>
      </header>

      <div className="static-page-hero">
        <div className="static-page-icon">✨</div>
        <h1 className="static-page-h1">On-Device AI Identification</h1>
        <p className="static-page-sub">
          BirdMap identifies birds instantly from your photos — entirely on your
          device, with no photo sent to a server before you choose to share it.
        </p>
      </div>

      <div className="static-page-section">
        <h2 className="static-page-h2">How it works</h2>
        <p className="static-page-p">
          When you take a photo in the BirdMap app, a CoreML model runs directly
          on your iPhone's Neural Engine. Within seconds it returns a ranked list
          of likely species. You see the top suggestion immediately — no internet
          connection required for the identification itself.
        </p>

        <div className="ai-page-highlight">
          🔒 Your photo never leaves your device until you tap <strong>Submit</strong>.
          Identification happens locally, keeping your privacy intact.
        </div>

        <h2 className="static-page-h2">The model</h2>

        <div className="static-page-card">
          <div className="static-page-card-title">Architecture</div>
          <div className="static-page-card-body">EfficientNet-B0 fine-tuned on community-submitted sightings and exported to Apple's CoreML format (.mlpackage) for fast, low-power inference on-device.</div>
        </div>
        <div className="static-page-card">
          <div className="static-page-card-title">Self-improving</div>
          <div className="static-page-card-body">Community annotations feed a retraining pipeline. When enough new verified sightings accumulate, a new model version is built and silently delivered to the app — so accuracy improves over time.</div>
        </div>
        <div className="static-page-card">
          <div className="static-page-card-title">Over-the-air updates</div>
          <div className="static-page-card-body">The app checks for a newer model version on launch. If one is available, it downloads in the background and is ready for your next sighting — no App Store update needed.</div>
        </div>

        <h2 className="static-page-h2">Limitations</h2>
        <p className="static-page-p">
          The model performs best on clear, well-lit photos where the bird is the
          main subject. Distant, blurry, or partially obscured birds may yield lower
          confidence scores or incorrect suggestions. That's why community
          annotation exists — human expertise corrects what AI gets wrong, and those
          corrections make the next model better.
        </p>
      </div>

      <footer className="static-page-footer">© 2026 BirdMap · Citizen Science</footer>
    </div>
  )
}
