import React from 'react'
import { Cpu, Lock } from 'lucide-react'
import birdMark from '../assets/bird-mark.svg'
import './StaticPage.css'
import './AIPage.css'

export default function AIPage() {
  return (
    <div className="static-page">
      <header className="static-page-header">
        <a href="/" className="static-page-back">← Home</a>
        <span className="static-page-logo">
          <a href="/" className="static-page-back"><img src={birdMark} alt="" />BirdMap</a>
        </span>
      </header>

      <div className="static-page-hero">
        <div className="static-page-icon"><Cpu className="h-6 w-6" strokeWidth={1.75} /></div>
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
          <Lock className="ai-page-highlight-icon" size={16} strokeWidth={2} />
          <span>
            Your photo never leaves your device until you tap <strong>Submit</strong>.
            Identification happens locally, keeping your privacy intact.
          </span>
        </div>

        <h2 className="static-page-h2">The model</h2>

        <div className="static-page-card">
          <div className="static-page-card-title">Architecture</div>
          <div className="static-page-card-body">Built on Google's AIY Birds V1 (MobileNetV2), a pre-trained model converted to Apple's CoreML format (.mlpackage) for fast, low-power inference on-device. We periodically fine-tune on top of pretrained weights like these using community annotations, rather than training a model from scratch.</div>
        </div>
        <div className="static-page-card">
          <div className="static-page-card-title">Versioned, fine-tuned in batches — not retrained live</div>
          <div className="static-page-card-body">Community annotations build a dataset, flag likely mistakes, and — once enough new annotations accumulate — feed a periodic fine-tuning pass. A newer model version only ships when that pass completes and the team publishes it; nothing changes what your app suggests in between.</div>
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
          annotation exists — human expertise corrects what the AI gets wrong
          immediately, and in aggregate feeds the periodic fine-tuning passes that
          improve the model itself over time.
        </p>
      </div>

      <footer className="static-page-footer">© 2026 BirdMap · Citizen Science</footer>
    </div>
  )
}
