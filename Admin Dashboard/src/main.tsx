import React from 'react'
import ReactDOM from 'react-dom/client'
import { BrowserRouter } from 'react-router-dom'
import L from 'leaflet'
import 'leaflet/dist/leaflet.css'
import App from './App'
import './index.css'

// Ensure global L is always available for Leaflet plugins (e.g. leaflet.heat)
if (typeof window !== 'undefined') {
  ;(window as any).L = L
}

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <BrowserRouter>
      <App />
    </BrowserRouter>
  </React.StrictMode>
)

