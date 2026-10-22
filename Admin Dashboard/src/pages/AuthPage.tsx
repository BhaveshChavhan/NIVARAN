import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { motion } from 'framer-motion'
import { Shield, AlertCircle, Eye, EyeOff } from 'lucide-react'
import { useAppStore } from '../store/useAppStore'

export default function AuthPage() {
  const [email, setEmail] = useState('admin@safenet.com')
  const [password, setPassword] = useState('demo1234')
  const [showPw, setShowPw] = useState(false)
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(false)
  const { setAuthenticated } = useAppStore()
  const navigate = useNavigate()

  const handleLogin = async (e: React.FormEvent) => {
    e.preventDefault()
    setLoading(true)
    setError('')
    await new Promise(r => setTimeout(r, 700))
    if (email === 'admin@safenet.com' && password === 'demo1234') {
      setAuthenticated(true)
      navigate('/')
    } else {
      setError('Invalid credentials. Use admin@safenet.com / demo1234')
    }
    setLoading(false)
  }

  return (
    <div className="min-h-screen flex items-center justify-center" style={{ background: '#0a0a0a' }}>
      {/* Background grid */}
      <div className="fixed inset-0 pointer-events-none opacity-5"
        style={{ backgroundImage: 'linear-gradient(#ef4444 1px, transparent 1px), linear-gradient(90deg, #ef4444 1px, transparent 1px)', backgroundSize: '40px 40px' }} />

      <motion.div
        initial={{ opacity: 0, y: 20 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.4 }}
        className="relative w-full max-w-sm"
      >
        {/* Glow */}
        <div className="absolute inset-0 blur-3xl opacity-10 rounded-2xl" style={{ background: '#ef4444' }} />

        <div className="relative rounded-xl p-8" style={{ background: '#141414', border: '1px solid #2a2a2a' }}>
          {/* Logo */}
          <div className="flex flex-col items-center mb-8">
            <div className="flex items-center justify-center w-14 h-14 rounded-xl mb-4" style={{ background: 'rgba(239,68,68,0.12)', border: '1px solid rgba(239,68,68,0.2)' }}>
              <Shield size={28} className="text-red-500" />
            </div>
            <h1 className="text-xl font-display font-bold text-white">SafeNet Admin</h1>
            <p className="text-sm mt-1" style={{ color: '#6b7280', fontFamily: 'JetBrains Mono' }}>AI Predictive Safety System</p>
          </div>

          <form onSubmit={handleLogin} className="space-y-4">
            <div>
              <label className="block text-xs font-mono text-gray-500 uppercase tracking-wider mb-1.5">Email</label>
              <input
                type="email"
                value={email}
                onChange={e => setEmail(e.target.value)}
                className="w-full px-4 py-2.5 rounded-lg text-sm text-white outline-none transition-colors"
                style={{ background: '#1f1f1f', border: '1px solid #2a2a2a' }}
                onFocus={e => (e.target.style.borderColor = '#ef4444')}
                onBlur={e => (e.target.style.borderColor = '#2a2a2a')}
              />
            </div>
            <div>
              <label className="block text-xs font-mono text-gray-500 uppercase tracking-wider mb-1.5">Password</label>
              <div className="relative">
                <input
                  type={showPw ? 'text' : 'password'}
                  value={password}
                  onChange={e => setPassword(e.target.value)}
                  className="w-full px-4 py-2.5 rounded-lg text-sm text-white outline-none pr-10 transition-colors"
                  style={{ background: '#1f1f1f', border: '1px solid #2a2a2a' }}
                  onFocus={e => (e.target.style.borderColor = '#ef4444')}
                  onBlur={e => (e.target.style.borderColor = '#2a2a2a')}
                />
                <button type="button" onClick={() => setShowPw(!showPw)}
                  className="absolute right-3 top-1/2 -translate-y-1/2 text-gray-600 hover:text-gray-400">
                  {showPw ? <EyeOff size={15} /> : <Eye size={15} />}
                </button>
              </div>
            </div>

            {error && (
              <motion.div initial={{ opacity: 0 }} animate={{ opacity: 1 }}
                className="flex items-center gap-2 text-sm text-red-400 p-3 rounded-lg"
                style={{ background: 'rgba(239,68,68,0.08)', border: '1px solid rgba(239,68,68,0.2)' }}>
                <AlertCircle size={14} />
                {error}
              </motion.div>
            )}

            <button
              type="submit"
              disabled={loading}
              className="w-full py-2.5 rounded-lg text-sm font-semibold text-white transition-opacity mt-2"
              style={{ background: loading ? '#7f1d1d' : '#ef4444', opacity: loading ? 0.7 : 1 }}
            >
              {loading ? 'Authenticating...' : 'Sign In'}
            </button>
          </form>

          <div className="mt-6 p-3 rounded-lg text-xs" style={{ background: '#0f0f0f', border: '1px solid #1e1e1e', fontFamily: 'JetBrains Mono', color: '#4b5563' }}>
            <div className="text-gray-500 mb-1">Demo credentials:</div>
            <div>admin@safenet.com / demo1234</div>
          </div>
        </div>
      </motion.div>
    </div>
  )
}
