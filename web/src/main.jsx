import React from 'react'
import ReactDOM from 'react-dom/client'
import { BrowserRouter } from 'react-router-dom'
import './tailwind.css'
import './base.css'
import AppRoutes from './routes.jsx'

const container = document.getElementById('root')
const app = (
  <BrowserRouter>
    <AppRoutes />
  </BrowserRouter>
)

// Prerendered pages ship real HTML inside #root: hydrate it. The map shell
// (and dev mode) ships an empty #root: render from scratch.
if (container.hasChildNodes()) ReactDOM.hydrateRoot(container, app)
else ReactDOM.createRoot(container).render(app)
