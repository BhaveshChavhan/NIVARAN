import { useEffect, useState, useMemo } from 'react'
import { motion, AnimatePresence } from 'framer-motion'
import {
  Filter, Download, ChevronDown, ChevronRight,
  CheckCircle, XCircle, AlertTriangle, Search, RefreshCw
} from 'lucide-react'
import { useAppStore } from '../store/useAppStore'
import { fetchIncidents, patchIncident, fetchAISummary } from '../lib/api'
import { supabase } from '../lib/supabase'
import type { Incident } from '../types'
import toast from 'react-hot-toast'
import React from 'react'

const SEVERITY_COLORS: Record<string | number, { bg: string; text: string }> = {
  1: { bg: 'rgba(34,197,94,0.12)', text: '#22c55e' },
  2: { bg: 'rgba(245,158,11,0.12)', text: '#f59e0b' },
  3: { bg: 'rgba(249,115,22,0.12)', text: '#f97316' },
  4: { bg: 'rgba(239,68,68,0.12)', text: '#ef4444' },
  low: { bg: 'rgba(34,197,94,0.12)', text: '#22c55e' },
  medium: { bg: 'rgba(245,158,11,0.12)', text: '#f59e0b' },
  high: { bg: 'rgba(249,115,22,0.12)', text: '#f97316' },
  critical: { bg: 'rgba(239,68,68,0.12)', text: '#ef4444' },
}

const SOURCE_LABELS: Record<string, string> = {
  user_report: 'User Report',
  scrape: 'Web Scrape',
  police: 'Police Feed',
  sensor: 'IoT Sensor',
}

function Badge({ value, colorMap }: { value: string; colorMap: Record<string, { bg: string; text: string }> }) {
  const c = colorMap[value] || { bg: '#1a1a1a', text: '#6b7280' }
  return (
    <span className="inline-flex items-center px-2 py-0.5 rounded text-xs font-semibold capitalize"
      style={{ background: c.bg, color: c.text }}>
      {value}
    </span>
  )
}

export default function IncidentsPage() {
  const { incidents, setIncidents, addIncident, patchIncident: storePatch } = useAppStore()
  const [loading, setLoading] = useState(false)
  const [search, setSearch] = useState('')
  const [filterType, setFilterType] = useState('all')
  const [filterSeverity, setFilterSeverity] = useState('all')
  const [filterSource, setFilterSource] = useState('all')
  const [filterVerified, setFilterVerified] = useState('all')
  const [expandedId, setExpandedId] = useState<string | null>(null)
  const [aiSummaries, setAiSummaries] = useState<Record<string, string>>({})
  const [loadingAI, setLoadingAI] = useState<string | null>(null)
  const [verifying, setVerifying] = useState<string | null>(null)

  useEffect(() => {
    setLoading(true)
    fetchIncidents().then(data => { setIncidents(data); setLoading(false) })
  }, [])

  // Realtime subscription
  useEffect(() => {
    const channel = supabase
      .channel('incidents_page')
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'incidents' }, payload => {
        addIncident(payload.new as Incident)
        toast.error('New Incident Reported!', {
          icon: '⚠️',
          style: { background: '#1a0000', color: '#ef4444', border: '1px solid #ef4444' }
        })
      })
      .subscribe()
    return () => { supabase.removeChannel(channel) }
  }, [addIncident])

  const filtered = useMemo(() => {
    return incidents.filter(i => {
      if (search && !i.title.toLowerCase().includes(search.toLowerCase()) &&
        !i.address.toLowerCase().includes(search.toLowerCase())) return false
      if (filterType !== 'all' && i.type !== filterType) return false
      if (filterSeverity !== 'all' && i.severity !== filterSeverity) return false
      if (filterSource !== 'all' && i.source !== filterSource) return false
      if (filterVerified === 'yes' && !i.verified) return false
      if (filterVerified === 'no' && i.verified) return false
      return true
    })
  }, [incidents, search, filterType, filterSeverity, filterSource, filterVerified])

  const handleExpand = async (id: string) => {
    if (expandedId === id) { setExpandedId(null); return }
    setExpandedId(id)
    if (!aiSummaries[id]) {
      setLoadingAI(id)
      const { summary } = await fetchAISummary(id)
      setAiSummaries(prev => ({ ...prev, [id]: summary }))
      setLoadingAI(null)
    }
  }

  const handleVerify = async (id: string, verified: boolean) => {
    setVerifying(id)
    await patchIncident(id, { verified })
    storePatch(id, { verified })
    toast.success(verified ? 'Incident verified' : 'Incident rejected', {
      style: { background: '#1a1a1a', color: '#e5e7eb', border: '1px solid #2a2a2a' }
    })
    setVerifying(null)
  }

  const exportCSV = () => {
    const headers = ['ID', 'Title', 'Type', 'Severity', 'Source', 'Address', 'Risk Score', 'Verified', 'Date']
    const rows = filtered.map(i => [
      i.id, `"${i.title}"`, i.type, i.severity, i.source, `"${i.address}"`,
      i.risk_score, i.verified, new Date(i.created_at).toLocaleString()
    ])
    const csv = [headers, ...rows].map(r => r.join(',')).join('\n')
    const blob = new Blob([csv], { type: 'text/csv' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a'); a.href = url; a.download = 'incidents.csv'; a.click()
    toast.success('CSV exported', { style: { background: '#1a1a1a', color: '#e5e7eb', border: '1px solid #2a2a2a' } })
  }

  return (
    <div className="flex flex-col h-full overflow-hidden" style={{ background: '#0f0f0f' }}>
      {/* Header */}
      <div className="flex items-center justify-between px-6 py-4 border-b" style={{ borderColor: '#1e1e1e' }}>
        <div>
          <h1 className="text-lg font-display font-bold text-white">Incidents</h1>
          <p className="text-xs text-gray-600 font-mono mt-0.5">{filtered.length} of {incidents.length} shown</p>
        </div>
        <div className="flex items-center gap-2">
          <button onClick={() => { setLoading(true); fetchIncidents().then(d => { setIncidents(d); setLoading(false) }) }}
            className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs text-gray-500 hover:text-gray-300 transition-colors"
            style={{ border: '1px solid #2a2a2a' }}>
            <RefreshCw size={11} className={loading ? 'animate-spin' : ''} />
            Refresh
          </button>
          <button onClick={exportCSV}
            className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-medium text-white transition-colors"
            style={{ background: '#1a1a1a', border: '1px solid #2a2a2a' }}>
            <Download size={11} />
            Export CSV
          </button>
        </div>
      </div>

      {/* Filters */}
      <div className="flex items-center gap-2 px-6 py-3 border-b flex-wrap" style={{ borderColor: '#1e1e1e', background: '#0a0a0a' }}>
        <div className="flex items-center gap-2 px-3 py-1.5 rounded-lg flex-1 min-w-48"
          style={{ background: '#141414', border: '1px solid #1e1e1e' }}>
          <Search size={12} className="text-gray-600" />
          <input value={search} onChange={e => setSearch(e.target.value)}
            placeholder="Search incidents..."
            className="bg-transparent text-sm text-white outline-none flex-1 placeholder-gray-700" />
        </div>

        {[
          { label: 'Type', value: filterType, set: setFilterType, opts: ['all', 'theft', 'assault', 'fire', 'accident', 'vandalism', 'other'] },
          { label: 'Severity', value: filterSeverity, set: setFilterSeverity, opts: ['all', 'low', 'medium', 'high', 'critical'] },
          { label: 'Source', value: filterSource, set: setFilterSource, opts: ['all', 'user_report', 'scrape', 'police', 'sensor'] },
          { label: 'Verified', value: filterVerified, set: setFilterVerified, opts: ['all', 'yes', 'no'] },
        ].map(f => (
          <div key={f.label} className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg"
            style={{ background: '#141414', border: '1px solid #1e1e1e' }}>
            <Filter size={11} className="text-gray-600" />
            <select value={f.value} onChange={e => f.set(e.target.value)}
              className="bg-transparent text-xs text-gray-400 outline-none cursor-pointer">
              {f.opts.map(o => <option key={o} value={o} style={{ background: '#1a1a1a' }}>{o === 'all' ? `All ${f.label}s` : o}</option>)}
            </select>
          </div>
        ))}
      </div>

      {/* Table */}
      <div className="flex-1 overflow-auto">
        <table className="w-full min-w-[900px]">
          <thead className="sticky top-0 z-10" style={{ background: '#0a0a0a' }}>
            <tr className="border-b" style={{ borderColor: '#1e1e1e' }}>
              {['', 'Title', 'Type', 'Severity', 'Source', 'Risk', 'Address', 'Date', 'Verified', 'Actions'].map(h => (
                <th key={h} className="px-4 py-3 text-left text-xs font-mono text-gray-600 uppercase tracking-wider whitespace-nowrap">
                  {h}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            <AnimatePresence>
              {loading ? (
                <tr><td colSpan={10} className="text-center py-12 text-gray-600 font-mono text-sm">Loading incidents...</td></tr>
              ) : filtered.length === 0 ? (
                <tr><td colSpan={10} className="text-center py-12 text-gray-600 font-mono text-sm">No incidents match filters</td></tr>
              ) : filtered.map((inc, idx) => (
                <React.Fragment key={inc.id}>
                  <motion.tr
                    initial={{ opacity: 0 }}
                    animate={{ opacity: 1 }}
                    transition={{ delay: idx * 0.02 }}
                    className="data-row border-b cursor-pointer"
                    style={{ borderColor: '#1a1a1a' }}
                    onClick={() => handleExpand(inc.id)}
                  >
                    <td className="pl-4 py-3">
                      <ChevronRight size={14} className="text-gray-600 transition-transform"
                        style={{ transform: expandedId === inc.id ? 'rotate(90deg)' : 'none' }} />
                    </td>
                    <td className="px-4 py-3">
                      <div className="text-sm text-white font-medium max-w-[200px] truncate">{inc.title}</div>
                    </td>
                    <td className="px-4 py-3">
                      <span className="text-xs capitalize text-gray-400">{inc.type}</span>
                    </td>
                    <td className="px-4 py-3">
                      <Badge value={inc.severity} colorMap={SEVERITY_COLORS} />
                    </td>
                    <td className="px-4 py-3">
                      <span className="text-xs text-gray-500">{SOURCE_LABELS[inc.source] || inc.source}</span>
                    </td>
                    <td className="px-4 py-3">
                      <div className="flex items-center gap-2">
                        <div className="w-16 h-1.5 rounded-full" style={{ background: '#1e1e1e' }}>
                          <div className="h-full rounded-full transition-all"
                            style={{
                              width: `${inc.risk_score}%`,
                              background: inc.risk_score > 70 ? '#ef4444' : inc.risk_score > 40 ? '#f59e0b' : '#22c55e'
                            }} />
                        </div>
                        <span className="text-xs font-mono text-gray-500">{inc.risk_score}</span>
                      </div>
                    </td>
                    <td className="px-4 py-3">
                      <span className="text-xs text-gray-500 max-w-[150px] truncate block">{inc.address}</span>
                    </td>
                    <td className="px-4 py-3">
                      <span className="text-xs font-mono text-gray-600 whitespace-nowrap">
                        {new Date(inc.created_at).toLocaleDateString('en-IN', { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' })}
                      </span>
                    </td>
                    <td className="px-4 py-3">
                      {inc.verified
                        ? <span className="flex items-center gap-1 text-xs text-green-500"><CheckCircle size={12} /> Verified</span>
                        : <span className="flex items-center gap-1 text-xs text-gray-600"><XCircle size={12} /> Pending</span>
                      }
                    </td>
                    <td className="px-4 py-3" onClick={e => e.stopPropagation()}>
                      <div className="flex items-center gap-1">
                        {!inc.verified && (
                          <button onClick={() => handleVerify(inc.id, true)}
                            disabled={verifying === inc.id}
                            className="px-2 py-1 rounded text-xs font-medium transition-colors"
                            style={{ background: 'rgba(34,197,94,0.1)', color: '#22c55e', border: '1px solid rgba(34,197,94,0.2)' }}>
                            Verify
                          </button>
                        )}
                        {inc.verified && (
                          <button onClick={() => handleVerify(inc.id, false)}
                            disabled={verifying === inc.id}
                            className="px-2 py-1 rounded text-xs font-medium transition-colors"
                            style={{ background: 'rgba(239,68,68,0.08)', color: '#ef4444', border: '1px solid rgba(239,68,68,0.2)' }}>
                            Reject
                          </button>
                        )}
                      </div>
                    </td>
                  </motion.tr>

                  {/* Expanded AI summary row */}
                  <AnimatePresence>
                    {expandedId === inc.id && (
                      <motion.tr key={`expand-${inc.id}`}
                        initial={{ opacity: 0 }}
                        animate={{ opacity: 1 }}
                        exit={{ opacity: 0 }}
                      >
                        <td colSpan={10} className="px-4 pb-4 pt-0">
                          <div className="rounded-xl p-5 ml-6" style={{ background: '#141414', border: '1px solid #2a2a2a' }}>
                            <div className="flex items-center gap-2 mb-3">
                              <div className="w-1.5 h-1.5 rounded-full bg-red-500" />
                              <span className="text-xs font-mono text-gray-500 uppercase tracking-wider">AI Analysis</span>
                            </div>
                            {loadingAI === inc.id ? (
                              <div className="flex items-center gap-2 text-sm text-gray-600">
                                <RefreshCw size={12} className="animate-spin" />
                                Analyzing incident with AI...
                              </div>
                            ) : (
                              <p className="text-sm text-gray-300 leading-relaxed font-body">
                                {aiSummaries[inc.id]}
                              </p>
                            )}
                            <div className="mt-4 pt-3 border-t grid grid-cols-3 gap-4" style={{ borderColor: '#2a2a2a' }}>
                              <div>
                                <div className="text-xs text-gray-600 font-mono mb-1">Location</div>
                                <div className="text-xs text-gray-300">{inc.address}</div>
                              </div>
                              <div>
                                <div className="text-xs text-gray-600 font-mono mb-1">Coordinates</div>
                                <div className="text-xs font-mono text-gray-400">{inc.lat.toFixed(5)}, {inc.lng.toFixed(5)}</div>
                              </div>
                              <div>
                                <div className="text-xs text-gray-600 font-mono mb-1">Description</div>
                                <div className="text-xs text-gray-400">{inc.description}</div>
                              </div>
                            </div>
                          </div>
                        </td>
                      </motion.tr>
                    )}
                  </AnimatePresence>
                </React.Fragment>
              ))}
            </AnimatePresence>
          </tbody>
        </table>
      </div>
    </div>
  )
}
