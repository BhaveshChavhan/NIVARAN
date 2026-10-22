import { useEffect, useState, forwardRef } from 'react'
import { motion, AnimatePresence } from 'framer-motion'
import { Radio, CheckCircle, Clock, ArrowRight, RefreshCw, Filter } from 'lucide-react'
import { useAppStore } from '../store/useAppStore'
import { fetchSOSAlerts, BASE } from '../lib/api'
import { supabase } from '../lib/supabase'
import type { SOSAlert } from '../types'
import toast from 'react-hot-toast'
import { format, formatDistanceToNow } from 'date-fns'

const EMERGENCY_COLORS: Record<string, { bg: string; text: string; border: string }> = {
  medical: { bg: 'rgba(245,158,11,0.1)', text: '#f59e0b', border: 'rgba(245,158,11,0.2)' },
  fire: { bg: 'rgba(249,115,22,0.1)', text: '#f97316', border: 'rgba(249,115,22,0.2)' },
  crime: { bg: 'rgba(239,68,68,0.1)', text: '#ef4444', border: 'rgba(239,68,68,0.2)' },
  accident: { bg: 'rgba(139,92,246,0.1)', text: '#8b5cf6', border: 'rgba(139,92,246,0.2)' },
  other: { bg: 'rgba(107,114,128,0.1)', text: '#9ca3af', border: 'rgba(107,114,128,0.2)' },
}

function StatusBadge({ status }: { status: SOSAlert['status'] }) {
  if (status === 'active') {
    return (
      <div className="flex items-center gap-1.5">
        <div className="w-2 h-2 rounded-full bg-red-500 status-active" />
        <span className="text-xs font-semibold text-red-400 uppercase tracking-wide">Active</span>
      </div>
    )
  }
  if (status === 'resolved') {
    return (
      <div className="flex items-center gap-1.5">
        <div className="w-2 h-2 rounded-full bg-green-500" />
        <span className="text-xs font-semibold text-green-400 uppercase tracking-wide">Resolved</span>
      </div>
    )
  }
  return (
    <div className="flex items-center gap-1.5">
      <div className="w-2 h-2 rounded-full bg-gray-500" />
      <span className="text-xs font-semibold text-gray-400 uppercase tracking-wide">False Alarm</span>
    </div>
  )
}

function MeshPath({ path }: { path: string[] }) {
  return (
    <div className="flex items-center gap-1 flex-wrap">
      {path.map((node, i) => (
        <span key={i} className="flex items-center gap-1">
          <span className="inline-flex items-center px-2 py-0.5 rounded text-xs font-mono"
            style={{ background: '#1a1a1a', border: '1px solid #2a2a2a', color: '#60a5fa', fontSize: '10px' }}>
            {node}
          </span>
          {i < path.length - 1 && (
            <ArrowRight size={10} className="text-gray-700 flex-shrink-0" />
          )}
        </span>
      ))}
    </div>
  )
}

export default function SOSAlertsPage() {
  const { sosAlerts, setSosAlerts, resolveSos, addSosAlert } = useAppStore()
  const [loading, setLoading] = useState(false)
  const [resolving, setResolving] = useState<string | null>(null)
  const [filterStatus, setFilterStatus] = useState<'all' | 'active' | 'resolved'>('all')
  const [filterType, setFilterType] = useState('all')

  useEffect(() => {
    setLoading(true)
    fetchSOSAlerts().then(data => { setSosAlerts(data); setLoading(false) })
  }, [])

  // Realtime subscription
  useEffect(() => {
    const channel = supabase
      .channel('sos_page')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'sos_logs' }, payload => {
        if (payload.eventType === 'INSERT') {
          const newAlert = payload.new as SOSAlert
          addSosAlert(newAlert)
          // High-visibility notification
          toast.error(`🆘 CRITICAL SOS: ${newAlert.user_name || 'New User'} needs help!`, {
            duration: 10000,
            position: 'top-right',
            style: { 
              background: '#ef4444', 
              color: '#fff', 
              fontWeight: 'bold',
              border: '2px solid #fff',
              fontSize: '14px'
            }
          })
        } else if (payload.eventType === 'UPDATE') {
          useAppStore.getState().patchSosAlert(payload.new.id, payload.new as SOSAlert)
        }
      })
      .subscribe()
    return () => { supabase.removeChannel(channel) }
  }, [])

  const handleResolve = async (id: string) => {
    setResolving(id)
    await new Promise(r => setTimeout(r, 500))
    resolveSos(id)
    toast.success('Alert resolved', {
      icon: '✓',
      style: { background: '#1a1a1a', color: '#e5e7eb', border: '1px solid #2a2a2a' }
    })
    setResolving(null)
  }

  const filtered = sosAlerts.filter(a => {
    if (filterStatus !== 'all' && a.status !== filterStatus) return false
    if (filterType !== 'all' && a.emergency_type !== filterType) return false
    return true
  })

  const activeCount = sosAlerts.filter(a => a.status === 'active').length
  const resolvedCount = sosAlerts.filter(a => a.status === 'resolved').length

  return (
    <div className="flex flex-col h-full overflow-hidden" style={{ background: '#0f0f0f' }}>
      {/* Header */}
      <div className="flex items-center justify-between px-6 py-4 border-b" style={{ borderColor: '#1e1e1e' }}>
        <div className="flex items-center gap-4">
          <div>
            <h1 className="text-lg font-display font-bold text-white">SOS Alerts</h1>
            <p className="text-xs text-gray-600 font-mono mt-0.5">{filtered.length} alerts shown</p>
          </div>
          <div className="flex items-center gap-3">
            <div className="flex items-center gap-2 px-3 py-1.5 rounded-lg" style={{ background: 'rgba(239,68,68,0.08)', border: '1px solid rgba(239,68,68,0.15)' }}>
              <div className="w-1.5 h-1.5 rounded-full bg-red-500 status-active" />
              <span className="text-xs font-mono text-red-400">{activeCount} Active</span>
            </div>
            <div className="flex items-center gap-2 px-3 py-1.5 rounded-lg" style={{ background: 'rgba(34,197,94,0.06)', border: '1px solid rgba(34,197,94,0.12)' }}>
              <CheckCircle size={11} className="text-green-500" />
              <span className="text-xs font-mono text-green-400">{resolvedCount} Resolved</span>
            </div>
          </div>
        </div>
        <button
          onClick={() => { setLoading(true); fetchSOSAlerts().then(d => { setSosAlerts(d); setLoading(false) }) }}
          className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs text-gray-500 hover:text-gray-300 transition-colors"
          style={{ border: '1px solid #2a2a2a' }}
        >
          <RefreshCw size={11} className={loading ? 'animate-spin' : ''} />
          Refresh
        </button>
      </div>

      {/* Filters */}
      <div className="flex items-center gap-3 px-6 py-3 border-b" style={{ borderColor: '#1e1e1e', background: '#0a0a0a' }}>
        <Filter size={12} className="text-gray-600" />
        <div className="flex items-center rounded-lg overflow-hidden" style={{ border: '1px solid #2a2a2a' }}>
          {(['all', 'active', 'resolved'] as const).map(s => (
            <button key={s} onClick={() => setFilterStatus(s)}
              className="px-3 py-1.5 text-xs font-mono capitalize transition-colors"
              style={{ color: filterStatus === s ? 'white' : '#6b7280', background: filterStatus === s ? '#ef4444' : 'transparent' }}>
              {s}
            </button>
          ))}
        </div>
        <div className="flex items-center px-3 py-1.5 rounded-lg gap-2" style={{ background: '#141414', border: '1px solid #1e1e1e' }}>
          <select value={filterType} onChange={e => setFilterType(e.target.value)}
            className="bg-transparent text-xs text-gray-400 outline-none cursor-pointer">
            {['all', 'medical', 'fire', 'crime', 'accident', 'other'].map(t => (
              <option key={t} value={t} style={{ background: '#1a1a1a' }}>{t === 'all' ? 'All Types' : t}</option>
            ))}
          </select>
        </div>
      </div>

      {/* Alerts table */}
      <div className="flex-1 overflow-y-auto">
        {loading ? (
          <div className="flex items-center justify-center py-20">
            <div className="text-sm text-gray-600 font-mono flex items-center gap-2">
              <RefreshCw size={14} className="animate-spin" /> Loading alerts...
            </div>
          </div>
        ) : filtered.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-20 gap-3">
            <Radio size={32} className="text-gray-700" />
            <div className="text-sm text-gray-600 font-mono">No alerts match filters</div>
          </div>
        ) : (
          <div className="p-4 space-y-2">
            <AnimatePresence mode="popLayout">
              {filtered.map((alert, idx) => (
                <SOSAlertRow 
                  key={alert.id} 
                  alert={alert} 
                  idx={idx} 
                  resolving={resolving} 
                  handleResolve={handleResolve} 
                />
              ))}
            </AnimatePresence>
          </div>
        )}
      </div>
    </div>
  )
}

const SOSAlertRow = forwardRef<HTMLDivElement, { 
  alert: SOSAlert, 
  idx: number, 
  resolving: string | null, 
  handleResolve: (id: string) => void 
}>(({ alert, idx, resolving, handleResolve }, ref) => {
  const initialName = alert.user_name || (alert as any).name || 'Unknown User'
  const [displayName, setDisplayName] = useState(initialName)
  const [hasAudio, setHasAudio] = useState(true)
  const eType = alert.emergency_type || (alert as any).type || 'other'
  const ec = EMERGENCY_COLORS[eType] || EMERGENCY_COLORS.other

  useEffect(() => {
    if ((alert as any).audio_url) {
      setHasAudio(true)
    }
  }, [(alert as any).audio_url])

  useEffect(() => {
    async function fetchRealName() {
      const email = alert.user_email || (alert as any).email;
      if (initialName === 'Unknown User' && email) {
        try {
          const { data } = await supabase
            .from('users')
            .select('name')
            .eq('email', email)
            .maybeSingle()
          
          if (data?.name) {
            setDisplayName(data.name)
          }
        } catch (err) {
          console.error('Error fetching real name:', err)
        }
      }
    }
    fetchRealName()
  }, [initialName, alert.user_email, (alert as any).email])

  return (
    <motion.div
      ref={ref}
      initial={{ opacity: 0, y: -10 }}
      animate={{ opacity: 1, y: 0 }}
      exit={{ opacity: 0, x: -20 }}
      transition={{ delay: idx * 0.02 }}
      layout
      className="rounded-xl p-4 transition-all"
      style={{
        background: alert.status === 'active' ? '#1a0000' : '#141414',
        border: `1px solid ${alert.status === 'active' ? 'rgba(239,68,68,0.2)' : '#1e1e1e'}`,
      }}
    >
      <div className="flex items-start gap-4">
        {/* Icon */}
        <div className="flex items-center justify-center w-10 h-10 rounded-xl flex-shrink-0"
          style={{ background: ec.bg, border: `1px solid ${ec.border}` }}>
          <Radio size={16} style={{ color: ec.text }} className={alert.status === 'active' ? 'animate-pulse' : ''} />
        </div>

        {/* Main content */}
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-3 mb-2 flex-wrap">
            <span className="font-semibold text-white text-sm">{displayName}</span>
            <span className="text-xs px-2 py-0.5 rounded capitalize font-semibold"
              style={{ background: ec.bg, color: ec.text, border: `1px solid ${ec.border}` }}>
              {eType}
            </span>
            <StatusBadge status={alert.status} />
          </div>

          <div className="grid grid-cols-2 gap-x-6 gap-y-1 mb-3">
            <div className="flex items-center gap-1.5">
              <span className="text-xs font-mono text-gray-400">
                GPS: {(alert.lat || (alert as any).latitude)?.toFixed(5) || 'N/A'}, {(alert.lng || (alert as any).longitude)?.toFixed(5) || 'N/A'}
              </span>
            </div>
            <div className="flex items-center gap-1.5">
              <Clock size={10} className="text-gray-600" />
              <span className="text-xs font-mono text-gray-400">
                {format(new Date(alert.created_at), 'dd MMM, HH:mm:ss')}
                <span className="text-[10px] text-gray-600 ml-1 font-bold">IST</span>
                <span className="text-gray-600 ml-1.5">
                  ({formatDistanceToNow(new Date(alert.created_at), { addSuffix: true })})
                </span>
              </span>
            </div>
            {alert.resolved_at && (
              <div className="flex items-center gap-1.5">
                <span className="text-xs text-gray-600 font-mono">Resolved:</span>
                <span className="text-xs font-mono text-green-500">
                  {format(new Date(alert.resolved_at), 'HH:mm:ss')}
                </span>
              </div>
            )}
            <div className="flex items-center gap-1.5">
              <span className="text-xs text-gray-600 font-mono">ID:</span>
              <span className="text-xs font-mono text-gray-600 truncate">{alert.id}</span>
            </div>
          </div>

          {/* Mesh path */}
          {alert.mesh_path?.length > 0 && (
            <div className="mb-3">
              <div className="text-xs text-gray-600 font-mono uppercase tracking-wider mb-1.5">
                Mesh Relay Path ({alert.mesh_path.length} hops)
              </div>
              <MeshPath path={alert.mesh_path} />
            </div>
          )}

          {/* SOS Audio Recording */}
          <div className="mt-2 bg-black/20 p-2 rounded-lg border border-red-500/10" style={{ background: 'rgba(0,0,0,0.2)' }}>
            <div className="text-xs text-gray-500 font-mono uppercase tracking-wider mb-1.5 flex items-center justify-between">
              <div className="flex items-center gap-1.5">
                <Radio size={12} className={alert.status === 'active' ? 'text-red-500 animate-pulse' : 'text-gray-400'} /> 
                SOS Audio Evidence {alert.status === 'active' && '(Recording...)'}
              </div>
              {alert.status !== 'active' && (
                <button 
                  onClick={() => {
                    setHasAudio(false);
                    setTimeout(() => setHasAudio(true), 100);
                  }}
                  className="text-[10px] text-blue-400 hover:text-blue-300 font-bold px-1.5 py-0.5 rounded border border-blue-400/20"
                >
                  RETRY
                </button>
              )}
            </div>
            {hasAudio ? (
              <audio 
                controls 
                key={`${alert.id}-${(alert as any).audio_url ? 'has-url' : hasAudio}`}
                className="w-full h-9 outline-none rounded bg-neutral-900" 
                src={(((alert as any).audio_url || `${BASE}/uploads/${alert.id}.m4a`) as string).replace('data:audio/m4a;', 'data:audio/mp4;')} 
                preload="auto"
                onError={() => {
                  if (alert.status !== 'active' && !(alert as any).audio_url) {
                    setHasAudio(false);
                  }
                }}
              />
            ) : (
              <div className="text-[10px] text-gray-500 italic py-2 flex items-center gap-1.5">
                <span>⚠️ No audio evidence uploaded yet for this alert.</span>
              </div>
            )}
          </div>
        </div>

        {/* Actions */}
        {alert.status === 'active' && (
          <button
            onClick={() => handleResolve(alert.id)}
            disabled={resolving === alert.id}
            className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-semibold transition-all flex-shrink-0"
            style={{ background: 'rgba(34,197,94,0.1)', color: '#22c55e', border: '1px solid rgba(34,197,94,0.2)' }}
          >
            {resolving === alert.id ? (
              <RefreshCw size={11} className="animate-spin" />
            ) : (
              <CheckCircle size={11} />
            )}
            Resolve
          </button>
        )}
      </div>
    </motion.div>
  )
})
