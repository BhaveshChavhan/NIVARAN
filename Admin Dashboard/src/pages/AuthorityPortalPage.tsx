import { useState, useEffect } from 'react'
import { motion, AnimatePresence } from 'framer-motion'
import {
  Shield, CheckCircle, XCircle, FileText, Search,
  Clock, MapPin, AlertTriangle,
  ThumbsUp, ThumbsDown, Download,
  User, Building, BadgeCheck
} from 'lucide-react'
import { fetchIncidents, fetchFIRs } from '../lib/api'
import type { Incident } from '../types'

const STATUS_TABS = ['pending_review', 'verified', 'rejected', 'all'] as const
type ReviewStatus = typeof STATUS_TABS[number]

interface FIRRecord {
  id: string
  fir_number: string
  incident_id?: string
  incident_type: string
  status: 'pending' | 'filed' | 'under_investigation' | 'chargesheet_filed' | 'closed'
  officer: string
  station: string
  filed_at: string
  description: string
  severity: string
  lat?: number
  lng?: number
  user_email?: string
  evidence_ids?: string[]
}

const statusColors: Record<string, string> = {
  pending: '#f59e0b',
  filed: '#f59e0b',
  under_investigation: '#6366f1',
  chargesheet_filed: '#10b981',
  closed: '#6b7280',
  pending_review: '#f59e0b',
  verified: '#10b981',
  rejected: '#ef4444',
}

const statusLabels: Record<string, string> = {
  pending: 'Pending Review',
  filed: 'Filed',
  under_investigation: 'Under Investigation',
  chargesheet_filed: 'Chargesheet Filed',
  closed: 'Closed',
}

export default function AuthorityPortalPage() {
  const [activeTab, setActiveTab] = useState<'verification' | 'fir' | 'reports'>('verification')
  const [reviewStatus, setReviewStatus] = useState<ReviewStatus>('pending_review')
  const [incidents, setIncidents] = useState<Incident[]>([])
  const [firs, setFirs] = useState<FIRRecord[]>([])
  const [search, setSearch] = useState('')
  const [selectedIncident, setSelectedIncident] = useState<Incident | null>(null)
  const [isLoading, setIsLoading] = useState(true)

  useEffect(() => {
    setIsLoading(true)
    Promise.all([fetchIncidents(), fetchFIRs()]).then(([incData, firData]) => {
      setIncidents(incData)
      setFirs(firData.map(f => ({
        id: f.id,
        fir_number: f.id.substring(0, 8).toUpperCase(),
        incident_type: f.crime_type || 'Unknown',
        status: f.status || 'pending',
        officer: 'Unassigned',
        station: 'Pending Allocation',
        filed_at: f.created_at,
        description: f.incident_description || 'No description',
        severity: 'High',
        user_email: f.user_email,
        evidence_ids: f.evidence_ids || []
      })))
      setIsLoading(false)
    })
  }, [])

  const filteredIncidents = incidents.filter(inc => {
    const matchesSearch = !search ||
      inc.title.toLowerCase().includes(search.toLowerCase()) ||
      inc.address.toLowerCase().includes(search.toLowerCase()) ||
      inc.type.toLowerCase().includes(search.toLowerCase())

    if (reviewStatus === 'all') return matchesSearch
    if (reviewStatus === 'verified') return matchesSearch && inc.verified
    if (reviewStatus === 'rejected') return matchesSearch && !inc.verified && inc.risk_score < 30
    return matchesSearch && !inc.verified && inc.risk_score >= 30
  })

  const filteredFIRs = firs.filter(f =>
    !search ||
    f.fir_number.toLowerCase().includes(search.toLowerCase()) ||
    f.officer.toLowerCase().includes(search.toLowerCase()) ||
    f.station.toLowerCase().includes(search.toLowerCase())
  )

  const handleVerify = (id: string, verified: boolean) => {
    // In real app, call patchIncident API
    setIncidents(prev => prev.map(i => i.id === id ? { ...i, verified } : i))
  }

  const stats = {
    pending: incidents.filter(i => !i.verified && i.risk_score >= 30).length,
    verified: incidents.filter(i => i.verified).length,
    rejected: incidents.filter(i => !i.verified && i.risk_score < 30).length,
    total_firs: firs.length,
    active_firs: firs.filter(f => f.status !== 'closed').length,
  }

  return (
    <div className="h-full overflow-y-auto" style={{ background: '#0f0f0f' }}>
      <div className="p-6 max-w-[1600px] mx-auto space-y-6">
        {/* Header */}
        <div className="flex items-center justify-between">
          <div>
            <h1 className="text-xl font-display font-bold text-white flex items-center gap-3">
              <div className="flex items-center justify-center w-10 h-10 rounded-xl" style={{ background: 'rgba(99,102,241,0.12)' }}>
                <Building size={20} className="text-indigo-400" />
              </div>
              Authority Portal
            </h1>
            <p className="text-sm text-gray-500 mt-1 font-body">Police & civic agency incident verification, FIR management, and reports</p>
          </div>
          <div className="flex items-center gap-3">
            <div className="flex items-center gap-2 px-3 py-1.5 rounded-lg text-xs font-mono" style={{ background: 'rgba(16,185,129,0.1)', color: '#10b981', border: '1px solid rgba(16,185,129,0.2)' }}>
              <BadgeCheck size={14} />
              Authorized: SI Patil • Nashik City
            </div>
          </div>
        </div>

        {/* Stats Row */}
        <div className="grid grid-cols-5 gap-3">
          {[
            { label: 'Pending Review', value: stats.pending, color: '#f59e0b', icon: Clock },
            { label: 'Verified', value: stats.verified, color: '#10b981', icon: CheckCircle },
            { label: 'Rejected', value: stats.rejected, color: '#ef4444', icon: XCircle },
            { label: 'Total FIRs', value: stats.total_firs, color: '#6366f1', icon: FileText },
            { label: 'Active FIRs', value: stats.active_firs, color: '#3b82f6', icon: AlertTriangle },
          ].map((s, i) => (
            <motion.div
              key={s.label}
              initial={{ opacity: 0, y: 20 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ delay: i * 0.05 }}
              className="rounded-xl p-4"
              style={{ background: '#141414', border: '1px solid #1e1e1e' }}
            >
              <div className="flex items-center justify-between mb-2">
                <s.icon size={16} style={{ color: s.color }} />
                <span className="text-2xl font-display font-bold text-white">{s.value}</span>
              </div>
              <p className="text-xs text-gray-500">{s.label}</p>
            </motion.div>
          ))}
        </div>

        {/* Tab Navigation */}
        <div className="flex items-center gap-1 p-1 rounded-xl" style={{ background: '#141414', border: '1px solid #1e1e1e' }}>
          {(['verification', 'fir', 'reports'] as const).map(tab => (
            <button
              key={tab}
              onClick={() => setActiveTab(tab)}
              className={`flex-1 py-2.5 px-4 rounded-lg text-sm font-medium transition-all ${
                activeTab === tab
                  ? 'text-white'
                  : 'text-gray-500 hover:text-gray-300'
              }`}
              style={activeTab === tab ? { background: '#1e1e1e' } : {}}
            >
              {tab === 'verification' ? '🔍 Incident Verification' :
               tab === 'fir' ? '📋 FIR Management' : '📊 Reports & Export'}
            </button>
          ))}
        </div>

        {/* Search */}
        <div className="relative">
          <Search size={16} className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-600" />
          <input
            type="text"
            value={search}
            onChange={e => setSearch(e.target.value)}
            placeholder={activeTab === 'fir' ? 'Search FIR number, officer, station...' : 'Search incidents by title, type, location...'}
            className="w-full pl-10 pr-4 py-2.5 rounded-lg text-sm font-body text-white placeholder-gray-600"
            style={{ background: '#141414', border: '1px solid #1e1e1e', outline: 'none' }}
          />
        </div>

        {/* Verification Tab */}
        {activeTab === 'verification' && (
          <div className="space-y-4">
            {/* Status filter */}
            <div className="flex gap-2">
              {STATUS_TABS.map(st => (
                <button
                  key={st}
                  onClick={() => setReviewStatus(st)}
                  className={`px-4 py-2 rounded-lg text-xs font-medium transition-all ${
                    reviewStatus === st ? 'text-white' : 'text-gray-500 hover:text-gray-300'
                  }`}
                  style={reviewStatus === st ? {
                    background: `${statusColors[st]}20`,
                    color: statusColors[st],
                    border: `1px solid ${statusColors[st]}40`,
                  } : { background: '#141414', border: '1px solid #1e1e1e' }}
                >
                  {st.replace('_', ' ').replace(/\b\w/g, l => l.toUpperCase())}
                  {st === 'pending_review' && ` (${stats.pending})`}
                  {st === 'verified' && ` (${stats.verified})`}
                </button>
              ))}
            </div>

            {/* Incidents list */}
            <div className="space-y-2">
              <AnimatePresence mode="popLayout">
                {filteredIncidents.map((inc, i) => (
                  <motion.div
                    key={inc.id}
                    initial={{ opacity: 0, x: -20 }}
                    animate={{ opacity: 1, x: 0 }}
                    exit={{ opacity: 0, x: 20 }}
                    transition={{ delay: i * 0.02 }}
                    className="rounded-xl p-4 flex items-center gap-4 cursor-pointer hover:border-gray-700 transition-colors"
                    style={{ background: '#141414', border: '1px solid #1e1e1e' }}
                    onClick={() => setSelectedIncident(inc)}
                  >
                    {/* Severity indicator */}
                    <div className="w-2 h-12 rounded-full" style={{
                      background: inc.severity === 'critical' ? '#ef4444' :
                        inc.severity === 'high' ? '#f59e0b' :
                        inc.severity === 'medium' ? '#6366f1' : '#6b7280'
                    }} />

                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-2 mb-1">
                        <span className="text-sm font-medium text-white truncate">{inc.title}</span>
                        <span className="px-2 py-0.5 rounded-full text-[10px] font-mono uppercase"
                          style={{ background: `${statusColors[inc.verified ? 'verified' : 'pending_review']}20`, color: statusColors[inc.verified ? 'verified' : 'pending_review'] }}>
                          {inc.verified ? 'Verified' : 'Pending'}
                        </span>
                      </div>
                      <div className="flex items-center gap-3 text-xs text-gray-500">
                        <span className="flex items-center gap-1"><MapPin size={11} />{inc.address}</span>
                        <span className="flex items-center gap-1"><Clock size={11} />{new Date(inc.created_at).toLocaleString()}</span>
                        <span>Risk: {inc.risk_score}</span>
                      </div>
                    </div>

                    {/* Action buttons */}
                    {!inc.verified && (
                      <div className="flex items-center gap-2">
                        <button
                          onClick={e => { e.stopPropagation(); handleVerify(inc.id, true) }}
                          className="flex items-center gap-1 px-3 py-1.5 rounded-lg text-xs font-medium transition-all hover:opacity-80"
                          style={{ background: 'rgba(16,185,129,0.1)', color: '#10b981', border: '1px solid rgba(16,185,129,0.2)' }}
                        >
                          <ThumbsUp size={12} /> Verify
                        </button>
                        <button
                          onClick={e => { e.stopPropagation(); handleVerify(inc.id, false) }}
                          className="flex items-center gap-1 px-3 py-1.5 rounded-lg text-xs font-medium transition-all hover:opacity-80"
                          style={{ background: 'rgba(239,68,68,0.1)', color: '#ef4444', border: '1px solid rgba(239,68,68,0.2)' }}
                        >
                          <ThumbsDown size={12} /> Reject
                        </button>
                      </div>
                    )}
                    {inc.verified && (
                      <BadgeCheck size={20} className="text-green-500 shrink-0" />
                    )}
                  </motion.div>
                ))}
              </AnimatePresence>
              {filteredIncidents.length === 0 && (
                <div className="text-center py-12 text-gray-600 text-sm">
                  No incidents matching the current filter.
                </div>
              )}
            </div>
          </div>
        )}

        {/* FIR Management Tab */}
        {activeTab === 'fir' && (
          <div className="space-y-3">
            {filteredFIRs.map((fir, i) => (
              <motion.div
                key={fir.id}
                initial={{ opacity: 0, y: 10 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ delay: i * 0.02 }}
                className="rounded-xl p-4"
                style={{ background: '#141414', border: '1px solid #1e1e1e' }}
              >
                <div className="flex items-center justify-between mb-3">
                  <div className="flex items-center gap-3">
                    <FileText size={16} className="text-indigo-400" />
                    <span className="text-sm font-mono font-bold text-white">{fir.fir_number}</span>
                    <span className="px-2 py-0.5 rounded-full text-[10px] font-medium uppercase"
                      style={{ background: `${statusColors[fir.status]}20`, color: statusColors[fir.status] }}>
                      {statusLabels[fir.status]}
                    </span>
                  </div>
                  <div className="flex items-center gap-2 text-xs text-gray-500">
                    <User size={12} />
                    <span>{fir.officer}</span>
                    <span className="text-gray-700">•</span>
                    <Building size={12} />
                    <span>{fir.station}</span>
                  </div>
                </div>
                <div className="flex items-center gap-4 text-xs text-gray-500">
                  <span>Type: <span className="text-gray-300 capitalize">{fir.incident_type}</span></span>
                  <span>Severity: <span className="text-gray-300 capitalize">{fir.severity}</span></span>
                  <span className="flex items-center gap-1"><Clock size={11} />{new Date(fir.filed_at).toLocaleDateString()}</span>
                  <span className="flex items-center gap-1"><MapPin size={11} />{(fir.lat ?? 0).toFixed(4)}, {(fir.lng ?? 0).toFixed(4)}</span>
                </div>
              </motion.div>
            ))}
          </div>
        )}

        {/* Reports Tab */}
        {activeTab === 'reports' && (
          <div className="grid grid-cols-2 gap-4">
            {[
              { title: 'Daily Crime Summary', desc: 'Comprehensive daily report with incident breakdown', icon: FileText, color: '#6366f1' },
              { title: 'Zone Safety Report', desc: 'Area-wise safety scores and risk assessment', icon: Shield, color: '#10b981' },
              { title: 'FIR Status Report', desc: 'All FIRs with investigation status tracking', icon: CheckCircle, color: '#f59e0b' },
              { title: 'Trend Analysis', desc: 'Weekly/monthly crime trend comparison', icon: AlertTriangle, color: '#ef4444' },
              { title: 'Patrol Recommendation', desc: 'AI-generated patrol route suggestions', icon: MapPin, color: '#3b82f6' },
              { title: 'Community Alert Log', desc: 'All community-reported incidents log', icon: User, color: '#8b5cf6' },
            ].map((report, i) => (
              <motion.div
                key={report.title}
                initial={{ opacity: 0, scale: 0.95 }}
                animate={{ opacity: 1, scale: 1 }}
                transition={{ delay: i * 0.05 }}
                className="rounded-xl p-5 cursor-pointer hover:border-gray-700 transition-all group"
                style={{ background: '#141414', border: '1px solid #1e1e1e' }}
              >
                <div className="flex items-center gap-3 mb-3">
                  <div className="w-10 h-10 rounded-xl flex items-center justify-center" style={{ background: `${report.color}15` }}>
                    <report.icon size={18} style={{ color: report.color }} />
                  </div>
                  <div>
                    <div className="text-sm font-medium text-white">{report.title}</div>
                    <div className="text-xs text-gray-500">{report.desc}</div>
                  </div>
                </div>
                <button className="flex items-center gap-2 text-xs font-medium px-3 py-2 rounded-lg w-full justify-center transition-all group-hover:opacity-100 opacity-70"
                  style={{ background: `${report.color}15`, color: report.color, border: `1px solid ${report.color}30` }}>
                  <Download size={13} /> Generate & Download
                </button>
              </motion.div>
            ))}
          </div>
        )}

        {/* Incident Detail Modal */}
        <AnimatePresence>
          {selectedIncident && (
            <motion.div
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              exit={{ opacity: 0 }}
              className="fixed inset-0 z-50 flex items-center justify-center"
              style={{ background: 'rgba(0,0,0,0.7)', backdropFilter: 'blur(4px)' }}
              onClick={() => setSelectedIncident(null)}
            >
              <motion.div
                initial={{ scale: 0.9, opacity: 0 }}
                animate={{ scale: 1, opacity: 1 }}
                exit={{ scale: 0.9, opacity: 0 }}
                className="w-full max-w-lg rounded-2xl p-6 space-y-4"
                style={{ background: '#141414', border: '1px solid #2a2a2a' }}
                onClick={e => e.stopPropagation()}
              >
                <div className="flex items-center justify-between">
                  <h3 className="text-lg font-display font-bold text-white">{selectedIncident.title}</h3>
                  <button onClick={() => setSelectedIncident(null)} className="text-gray-500 hover:text-white">✕</button>
                </div>

                <div className="grid grid-cols-2 gap-3">
                  {[
                    { label: 'Type', value: selectedIncident.type },
                    { label: 'Severity', value: selectedIncident.severity },
                    { label: 'Source', value: selectedIncident.source },
                    { label: 'Risk Score', value: selectedIncident.risk_score },
                    { label: 'Location', value: selectedIncident.address },
                    { label: 'Status', value: selectedIncident.verified ? 'Verified' : 'Pending' },
                  ].map(item => (
                    <div key={item.label} className="p-3 rounded-lg" style={{ background: '#1a1a1a', border: '1px solid #252525' }}>
                      <div className="text-[10px] text-gray-600 uppercase tracking-wider mb-1">{item.label}</div>
                      <div className="text-sm text-white capitalize">{item.value}</div>
                    </div>
                  ))}
                </div>

                <div className="p-3 rounded-lg" style={{ background: '#1a1a1a', border: '1px solid #252525' }}>
                  <div className="text-[10px] text-gray-600 uppercase tracking-wider mb-1">Description</div>
                  <div className="text-sm text-gray-300">{selectedIncident.description}</div>
                </div>

                <div className="flex gap-3">
                  <button
                    onClick={() => { handleVerify(selectedIncident.id, true); setSelectedIncident(null) }}
                    className="flex-1 flex items-center justify-center gap-2 py-2.5 rounded-xl text-sm font-medium"
                    style={{ background: 'rgba(16,185,129,0.15)', color: '#10b981', border: '1px solid rgba(16,185,129,0.3)' }}
                  >
                    <CheckCircle size={16} /> Verify & Approve
                  </button>
                  <button
                    onClick={() => { handleVerify(selectedIncident.id, false); setSelectedIncident(null) }}
                    className="flex-1 flex items-center justify-center gap-2 py-2.5 rounded-xl text-sm font-medium"
                    style={{ background: 'rgba(239,68,68,0.15)', color: '#ef4444', border: '1px solid rgba(239,68,68,0.3)' }}
                  >
                    <XCircle size={16} /> Reject
                  </button>
                </div>
              </motion.div>
            </motion.div>
          )}
        </AnimatePresence>
      </div>
    </div>
  )
}
