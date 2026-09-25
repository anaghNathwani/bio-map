import React, { lazy, Suspense } from 'react'
import ReactDOM from 'react-dom/client'
import { BrowserRouter, Routes, Route } from 'react-router-dom'
import './tailwind.css'
import './base.css'
import LandingPage from './pages/LandingPage.jsx'
import CitizenSciencePage from './pages/CitizenSciencePage.jsx'
import CommunityPage from './pages/CommunityPage.jsx'
import AIPage from './pages/AIPage.jsx'
import TermsPage from './pages/TermsPage.jsx'
import NotFoundPage from './pages/NotFoundPage.jsx'

// The map pulls in Leaflet + Firebase; keep them out of every other page's bundle.
const App = lazy(() => import('./App.jsx'))

ReactDOM.createRoot(document.getElementById('root')).render(
  <BrowserRouter>
    <Routes>
      <Route path="/" element={<LandingPage />} />
      <Route path="/map" element={<Suspense fallback={null}><App /></Suspense>} />
      <Route path="/citizen-science" element={<CitizenSciencePage />} />
      <Route path="/community" element={<CommunityPage />} />
      <Route path="/ai" element={<AIPage />} />
      <Route path="/terms" element={<TermsPage />} />
      <Route path="*" element={<NotFoundPage />} />
    </Routes>
  </BrowserRouter>
)
