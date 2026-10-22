import { useState, useEffect } from 'react'
import { motion } from 'framer-motion'
import {
  Database, Globe, Newspaper, MessageCircle, Shield,
  Building, RefreshCw, CheckCircle, AlertTriangle,
  Clock, TrendingUp, Zap, Server, Wifi, ExternalLink
} from 'lucide-react'
import toast from 'react-hot-toast'

interface DataSource {
  id: string
  name: string
  icon: typeof Database
  color: string
  description: string
  status: 'active' | 'syncing' | 'error' | 'idle'
  lastSync: string | null
  records: number
  health: number // 0-100
}

interface IngestedRecord {
  source: string
  source_id: string
  type?: string
  city?: string
  description?: string
  headline?: string
  content?: string
  sentiment?: string
  timestamp: string
}

const INITIAL_SOURCES: DataSource[] = [
  { id: 'ncrb_api', name: 'NCRB Crime API', icon: Database, color: '#6366f1', description: 'National Crime Records Bureau data feed', status: 'idle', lastSync: null, records: 0, health: 100 },
  { id: 'news_feeds', name: 'News Feed Scraper', icon: Newspaper, color: '#f59e0b', description: 'Crime-related news articles via RSS', status: 'idle', lastSync: null, records: 0, health: 100 },
  { id: 'social_media', name: 'Social Media Listener', icon: MessageCircle, color: '#3b82f6', description: 'Twitter/X & social platform safety posts', status: 'idle', lastSync: null, records: 0, health: 100 },
  { id: 'police_portal', name: 'Police Portal', icon: Shield, color: '#10b981', description: 'FIR records & investigation data', status: 'idle', lastSync: null, records: 0, health: 100 },
  { id: 'govt_database', name: 'Govt Open Data', icon: Building, color: '#8b5cf6', description: 'Civic safety datasets & infrastructure', status: 'idle', lastSync: null, records: 0, health: 100 },
]

export default function DataIngestionPage() {
  const [sources, setSources] = useState<DataSource[]>(INITIAL_SOURCES)
  const [isSyncing, setIsSyncing] = useState(false)
  const [recentRecords, setRecentRecords] = useState<IngestedRecord[]>([])
  const [totalRecords, setTotalRecords] = useState(0)
  const [selectedSource, setSelectedSource] = useState<string | null>(null)
  const [syncLog, setSyncLog] = useState<string[]>([])

  const startSync = async (sourceId?: string) => {
    // In a real app, this would trigger a backend job
    toast.error('Syncing is currently disabled in non-mock mode', {
      style: { background: '#1a1a1a', color: '#ef4444', border: '1px solid #ef4444' }
    })
  }

  const totalHealth = Math.round(sources.reduce((sum, s) => sum + s.health, 0) / sources.length)

  return (
    <div className="h-full overflow-y-auto" style={{ background: '#0f0f0f' }}>
      <div className="p-6 max-w-[1600px] mx-auto space-y-6">
        {/* Header */}
        <div className="flex items-center justify-between">
          <div>
            <h1 className="text-xl font-display font-bold text-white flex items-center gap-3">
              <div className="flex items-center justify-center w-10 h-10 rounded-xl" style={{ background: 'rgba(99,102,241,0.12)' }}>
                <Database size={20} className="text-indigo-400" />
              </div>
              Data Ingestion Pipeline
            </h1>
            <p className="text-sm text-gray-500 mt-1 font-body">
              External crime data sources • Real-time ingestion • NLP processing
            </p>
          </div>
          <button
            onClick={() => startSync()}
            disabled={isSyncing}
            className={`flex items-center gap-2 px-5 py-2.5 rounded-xl text-sm font-medium transition-all ${
              isSyncing ? 'opacity-50 cursor-not-allowed' : 'hover:opacity-90'
            }`}
            style={{ background: 'linear-gradient(135deg, #6366f1, #8b5cf6)', color: 'white' }}
          >
            <RefreshCw size={14} className={isSyncing ? 'animate-spin' : ''} />
            {isSyncing ? 'Syncing...' : 'Sync All Sources'}
          </button>
        </div>

        {/* Pipeline Stats */}
        <div className="grid grid-cols-4 gap-3">
          {[
            { label: 'Total Records Ingested', value: totalRecords.toLocaleString(), icon: Database, color: '#6366f1' },
            { label: 'Active Sources', value: `${sources.filter(s => s.status === 'active').length}/${sources.length}`, icon: Globe, color: '#10b981' },
            { label: 'Pipeline Health', value: `${totalHealth}%`, icon: Zap, color: totalHealth > 90 ? '#10b981' : '#f59e0b' },
            { label: 'Last Full Sync', value: sources.some(s => s.lastSync) ? 'Just now' : 'Never', icon: Clock, color: '#3b82f6' },
          ].map((stat, i) => (
            <motion.div
              key={stat.label}
              initial={{ opacity: 0, y: 20 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ delay: i * 0.05 }}
              className="rounded-xl p-4"
              style={{ background: '#141414', border: '1px solid #1e1e1e' }}
            >
              <div className="flex items-center justify-between mb-2">
                <stat.icon size={16} style={{ color: stat.color }} />
                <span className="text-2xl font-display font-bold text-white">{stat.value}</span>
              </div>
              <p className="text-xs text-gray-500">{stat.label}</p>
            </motion.div>
          ))}
        </div>

        <div className="grid grid-cols-5 gap-4">
          {/* Data Sources - Left 3 cols */}
          <div className="col-span-3 space-y-3">
            <h2 className="text-sm font-display font-semibold text-gray-400 uppercase tracking-wider">Data Sources</h2>
            {sources.map((source, i) => (
              <motion.div
                key={source.id}
                initial={{ opacity: 0, x: -20 }}
                animate={{ opacity: 1, x: 0 }}
                transition={{ delay: i * 0.05 }}
                className={`rounded-xl p-4 cursor-pointer transition-all ${
                  selectedSource === source.id ? 'ring-1' : ''
                }`}
                style={{
                  background: '#141414',
                  border: `1px solid ${selectedSource === source.id ? source.color + '40' : '#1e1e1e'}`,
                  ...(selectedSource === source.id ? { ringColor: source.color } : {}),
                }}
                onClick={() => setSelectedSource(selectedSource === source.id ? null : source.id)}
              >
                <div className="flex items-center gap-4">
                  {/* Icon */}
                  <div className="w-11 h-11 rounded-xl flex items-center justify-center shrink-0"
                    style={{ background: `${source.color}15` }}>
                    <source.icon size={20} style={{ color: source.color }} />
                  </div>

                  {/* Info */}
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2 mb-0.5">
                      <span className="text-sm font-medium text-white">{source.name}</span>
                      <span className={`w-2 h-2 rounded-full ${
                        source.status === 'active' ? 'bg-green-500' :
                        source.status === 'syncing' ? 'bg-yellow-500 animate-pulse' :
                        source.status === 'error' ? 'bg-red-500' : 'bg-gray-600'
                      }`} />
                    </div>
                    <p className="text-xs text-gray-500">{source.description}</p>
                  </div>

                  {/* Metrics */}
                  <div className="text-right shrink-0">
                    <div className="text-sm font-mono font-bold text-white">{source.records.toLocaleString()}</div>
                    <div className="text-[10px] text-gray-600">records</div>
                  </div>

                  {/* Health */}
                  <div className="w-16 shrink-0">
                    <div className="flex items-center justify-between mb-1">
                      <span className="text-[10px] text-gray-600">Health</span>
                      <span className="text-[10px] font-mono" style={{ color: source.health > 90 ? '#10b981' : '#f59e0b' }}>
                        {source.health}%
                      </span>
                    </div>
                    <div className="w-full h-1 rounded-full bg-gray-800">
                      <div className="h-full rounded-full transition-all"
                        style={{ width: `${source.health}%`, background: source.health > 90 ? '#10b981' : '#f59e0b' }} />
                    </div>
                  </div>

                  {/* Sync button */}
                  <button
                    onClick={e => { e.stopPropagation(); startSync(source.id) }}
                    disabled={isSyncing}
                    className="px-3 py-1.5 rounded-lg text-xs font-medium transition-all hover:opacity-80 shrink-0"
                    style={{ background: `${source.color}15`, color: source.color, border: `1px solid ${source.color}30` }}
                  >
                    <RefreshCw size={12} className={source.status === 'syncing' ? 'animate-spin' : ''} />
                  </button>
                </div>

                {/* Last sync info */}
                {source.lastSync && (
                  <div className="mt-2 pt-2 border-t border-gray-800/50 flex items-center gap-2 text-[10px] text-gray-600">
                    <Clock size={10} />
                    Last synced: {new Date(source.lastSync).toLocaleString()}
                  </div>
                )}
              </motion.div>
            ))}
          </div>

          {/* Activity Log - Right 2 cols */}
          <div className="col-span-2 space-y-3">
            <h2 className="text-sm font-display font-semibold text-gray-400 uppercase tracking-wider">Activity Feed</h2>

            {/* Sync log */}
            <div className="rounded-xl p-4 space-y-2" style={{ background: '#141414', border: '1px solid #1e1e1e' }}>
              <div className="flex items-center gap-2 mb-2">
                <Server size={14} className="text-gray-500" />
                <span className="text-xs font-medium text-gray-400">Sync Log</span>
              </div>
              <div className="max-h-40 overflow-y-auto space-y-1 font-mono text-[11px]" style={{ scrollbarWidth: 'thin' }}>
                {syncLog.length === 0 ? (
                  <div className="text-gray-600 text-center py-4">No sync activity yet. Click "Sync All Sources" to start.</div>
                ) : (
                  syncLog.slice(-20).reverse().map((log, i) => (
                    <div key={i} className={`${log.includes('✅') ? 'text-green-500' : 'text-gray-500'}`}>{log}</div>
                  ))
                )}
              </div>
            </div>

            {/* Recent records */}
            <div className="rounded-xl p-4" style={{ background: '#141414', border: '1px solid #1e1e1e' }}>
              <div className="flex items-center gap-2 mb-3">
                <Wifi size={14} className="text-blue-400" />
                <span className="text-xs font-medium text-gray-400">Recent Ingested Records</span>
                <span className="text-[10px] font-mono text-gray-600 ml-auto">{recentRecords.length} records</span>
              </div>
              <div className="max-h-96 overflow-y-auto space-y-2" style={{ scrollbarWidth: 'thin' }}>
                {recentRecords.length === 0 ? (
                  <div className="text-gray-600 text-center py-8 text-xs">
                    Ingested records will appear here after syncing.
                  </div>
                ) : (
                  recentRecords.slice(0, 20).map((record, i) => {
                    const sourceInfo = sources.find(s => s.id === record.source)
                    return (
                      <motion.div
                        key={`${record.source_id}-${i}`}
                        initial={{ opacity: 0, x: 10 }}
                        animate={{ opacity: 1, x: 0 }}
                        transition={{ delay: i * 0.02 }}
                        className="p-2.5 rounded-lg"
                        style={{ background: '#1a1a1a', border: '1px solid #222' }}
                      >
                        <div className="flex items-center gap-2 mb-1">
                          <span className="w-1.5 h-1.5 rounded-full" style={{ background: sourceInfo?.color || '#666' }} />
                          <span className="text-[10px] font-mono text-gray-500">{record.source_id}</span>
                          {record.type && (
                            <span className="text-[10px] px-1.5 py-0.5 rounded capitalize"
                              style={{ background: '#252525', color: '#999' }}>
                              {record.type}
                            </span>
                          )}
                          {record.city && (
                            <span className="text-[10px] text-gray-600 ml-auto">{record.city}</span>
                          )}
                        </div>
                        <p className="text-[11px] text-gray-400 truncate">{record.description || record.headline || record.content}</p>
                      </motion.div>
                    )
                  })
                )}
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}
