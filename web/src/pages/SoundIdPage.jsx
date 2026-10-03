import React from 'react'
import { Link } from 'react-router-dom'
import { Mic } from 'lucide-react'
import ContentPage from '../components/ContentPage.jsx'

export default function SoundIdPage() {
  return (
    <ContentPage
      meta="/bird-sound-identification"
      icon={Mic}
      title="Identify birds by sound"
      intro="Record a call or song and get species suggestions from your phone, without a network connection."
    >
      <h2 className="static-page-h2">How it works</h2>
      <p className="static-page-p">
        BirdRadar uses BirdNET, the open bird-sound model from the Cornell Lab of Ornithology&rsquo;s K. Lisa Yang Center for
        Conservation Bioacoustics. It runs on your phone the moment a recording stops. You can record up to 30 seconds, or upload
        an existing audio file and BirdRadar will use its first 30 seconds.
      </p>

      <h2 className="static-page-h2">Your location makes it more accurate</h2>
      <p className="static-page-p">
        Sound models can name an implausible species for background noise. BirdRadar passes your real location and the time of year
        to BirdNET&rsquo;s location filter so species that do not occur near you are ruled out. If location is off, a stricter
        confidence threshold is used instead.
      </p>

      <h2 className="static-page-h2">More than one bird</h2>
      <p className="static-page-p">
        BirdNET scores every species independently for each short segment of audio, so when several birds are calling BirdRadar
        reports each species that clears the confidence bar, not just the loudest.
      </p>

      <h2 className="static-page-h2">Tips for a good recording</h2>
      <div className="static-page-card">
        <p className="static-page-card-body">Get close to the bird and hold still.</p>
      </div>
      <div className="static-page-card">
        <p className="static-page-card-body">Keep wind, voices and traffic out of the recording where you can.</p>
      </div>
      <div className="static-page-card">
        <p className="static-page-card-body">A short clean recording beats a long noisy one.</p>
      </div>

      <h2 className="static-page-h2">Limits</h2>
      <p className="static-page-p">
        A suggestion is a starting point, not a verdict. Faint, overlapping or distant calls get lower confidence, and a clip with
        no identifiable bird simply reports none. Other birders can then confirm or correct the ID; see{' '}
        <Link to="/community" className="underline">community annotations</Link> and the{' '}
        <Link to="/how-it-works" className="underline">full walkthrough</Link>. Prefer photos? Read about{' '}
        <Link to="/bird-photo-identification" className="underline">photo identification</Link>.
      </p>
    </ContentPage>
  )
}
