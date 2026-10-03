import React from 'react'
import { Link } from 'react-router-dom'
import { Camera } from 'lucide-react'
import ContentPage from '../components/ContentPage.jsx'

export default function PhotoIdPage() {
  return (
    <ContentPage
      meta="/bird-photo-identification"
      icon={Camera}
      title="Identify birds from a photo"
      intro="Point, shoot, and get a species suggestion from your phone in seconds."
    >
      <h2 className="static-page-h2">How it works</h2>
      <p className="static-page-p">
        BioMap classifies photos with Google&rsquo;s AIY Birds model (a MobileNetV2 network covering about 960 species) running
        on your phone. No photo is uploaded just to get a suggestion. You choose whether to submit it afterwards.
      </p>

      <h2 className="static-page-h2">It tells you when it is unsure</h2>
      <p className="static-page-p">
        If the model is not confident enough it says so rather than guessing. After you submit, you can mark the suggestion right,
        wrong or unsure, and other birders can add their own ID.
      </p>

      <h2 className="static-page-h2">Photos with several birds</h2>
      <p className="static-page-p">
        BioMap looks for other salient birds in the frame, crops each one and classifies it separately, so a flock or a pair
        gets a suggestion per bird for you to review.
      </p>

      <h2 className="static-page-h2">Tips for a good photo</h2>
      <div className="static-page-card">
        <p className="static-page-card-body">Make the bird the main subject, sharp and well lit.</p>
      </div>
      <div className="static-page-card">
        <p className="static-page-card-body">Include the whole bird if you can: head, breast and wings help.</p>
      </div>
      <div className="static-page-card">
        <p className="static-page-card-body">Take a few frames; the best one gives the best suggestion.</p>
      </div>

      <h2 className="static-page-h2">Limits</h2>
      <p className="static-page-p">
        Distant, blurry or partly hidden birds get lower confidence, and the model can only suggest species it was built to
        recognise. Learn more about the <Link to="/ai" className="underline">on-device AI</Link>, or try{' '}
        <Link to="/bird-sound-identification" className="underline">identifying birds by sound</Link>.
      </p>
    </ContentPage>
  )
}
