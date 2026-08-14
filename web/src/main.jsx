import React from 'react'
import ReactDOM from 'react-dom/client'
import { BrowserRouter, Routes, Route } from 'react-router-dom'
import './tailwind.css'
import './base.css'
import App from './App.jsx'
import LandingPage from './pages/LandingPage.jsx'
import CitizenSciencePage from './pages/CitizenSciencePage.jsx'
import CommunityPage from './pages/CommunityPage.jsx'
import AIPage from './pages/AIPage.jsx'
import TermsPage from './pages/TermsPage.jsx'

ReactDOM.createRoot(document.getElementById('root')).render(
  <BrowserRouter>
    <Routes>
      <Route path="/" element={<LandingPage />} />
      <Route path="/map" element={<App />} />
      <Route path="/citizen-science" element={<CitizenSciencePage />} />
      <Route path="/community" element={<CommunityPage />} />
      <Route path="/ai" element={<AIPage />} />
      <Route path="/terms" element={<TermsPage />} />
    </Routes>
  </BrowserRouter>
)
