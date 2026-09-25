import React, { lazy, Suspense } from 'react'
import { Routes, Route } from 'react-router-dom'
import LandingPage from './pages/LandingPage.jsx'
import CitizenSciencePage from './pages/CitizenSciencePage.jsx'
import CommunityPage from './pages/CommunityPage.jsx'
import AIPage from './pages/AIPage.jsx'
import TermsPage from './pages/TermsPage.jsx'
import HowItWorksPage from './pages/HowItWorksPage.jsx'
import FaqPage from './pages/FaqPage.jsx'
import NotFoundPage from './pages/NotFoundPage.jsx'

// The map pulls in Leaflet + Firebase; keep them out of every other page's bundle.
const MapApp = lazy(() => import('./App.jsx'))

/** Shared by the browser entry (main.jsx) and the prerender entry (entry-server.jsx). */
export default function AppRoutes() {
  return (
    <Routes>
      <Route path="/" element={<LandingPage />} />
      <Route path="/map" element={<Suspense fallback={null}><MapApp /></Suspense>} />
      <Route path="/citizen-science" element={<CitizenSciencePage />} />
      <Route path="/community" element={<CommunityPage />} />
      <Route path="/ai" element={<AIPage />} />
      <Route path="/terms" element={<TermsPage />} />
      <Route path="/how-it-works" element={<HowItWorksPage />} />
      <Route path="/faq" element={<FaqPage />} />
      <Route path="*" element={<NotFoundPage />} />
    </Routes>
  )
}
