import { Routes, Route, Navigate } from 'react-router-dom'
import { Toaster } from 'react-hot-toast'
import { useAppStore } from './store/useAppStore'
import Layout from './components/Layout'
import AuthPage from './pages/AuthPage'
import LiveMapPage from './pages/LiveMapPage'
import IncidentsPage from './pages/IncidentsPage'
import AnalyticsPage from './pages/AnalyticsPage'
import SOSAlertsPage from './pages/SOSAlertsPage'
import AuthorityPortalPage from './pages/AuthorityPortalPage'
import DataIngestionPage from './pages/DataIngestionPage'
import UsersPage from './pages/UsersPage'
import MLPredictionsPage from './pages/MLPredictionsPage'
import ChatPage from './pages/ChatPage'

function ProtectedRoute({ children }: { children: React.ReactNode }) {
  const auth = useAppStore(s => s.isAuthenticated)
  return auth ? <>{children}</> : <Navigate to="/auth" replace />
}

export default function App() {
  return (
    <>
      <Toaster
        position="top-right"
        toastOptions={{
          duration: 5000,
          style: { background: '#1a1a1a', color: '#e5e7eb', border: '1px solid #2a2a2a', fontFamily: 'DM Sans, sans-serif' },
        }}
      />
      <Routes>
        <Route path="/auth" element={<AuthPage />} />
        <Route path="/" element={<ProtectedRoute><Layout /></ProtectedRoute>}>
          <Route index element={<LiveMapPage />} />
          <Route path="incidents" element={<IncidentsPage />} />
          <Route path="analytics" element={<AnalyticsPage />} />
          <Route path="sos" element={<SOSAlertsPage />} />
          <Route path="data-ingestion" element={<DataIngestionPage />} />
          <Route path="authority" element={<AuthorityPortalPage />} />
          <Route path="users" element={<UsersPage />} />
          <Route path="ml-predictions" element={<MLPredictionsPage />} />
          <Route path="chat" element={<ChatPage />} />
        </Route>
        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
    </>
  )
}

