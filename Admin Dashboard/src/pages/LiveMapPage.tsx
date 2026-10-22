import { useEffect, useState, useCallback, useRef, forwardRef } from 'react'
import { useSearchParams } from 'react-router-dom'
import { MapContainer, TileLayer, Circle, Popup, Marker } from 'react-leaflet'
import { motion, AnimatePresence } from 'framer-motion'
import toast from 'react-hot-toast'
import {
  AlertTriangle, Radio, Shield, Cpu, ChevronDown,
  Zap, Network, RefreshCw, Clock, MapPin, Layers
} from 'lucide-react'
import { useAppStore } from '../store/useAppStore'
import { fetchHeatmap, fetchSOSAlerts, fetchStats, fetchIncidents, triggerSOS, resolveSOSAlert, getUserName } from '../lib/api'
import { supabase } from '../lib/supabase'
import { SOSMarker, MapController } from '../components/map/SOSMarker'
import { IncidentMarker } from '../components/map/IncidentMarker'
import { HeatmapLayer } from '../components/map/HeatmapLayer'
import { MeshRelayOverlay } from '../components/map/MeshRelayOverlay'
import type { HeatmapPoint, SOSAlert } from '../types'

const GOOGLE_KEY = (import.meta as any).env.VITE_GOOGLE_MAPS_API_KEY || 'AIzaSyBysLlo3koysojda0_SYVBPszM7WxcPs6U'

const MAP_LAYERS = [
  {
    id: 'google_roads',
    name: 'Google Maps',
    url: `https://mt1.google.com/vt/lyrs=m&x={x}&y={y}&z={z}&key=${GOOGLE_KEY}`,
    subdomains: 'abcd',
    maxZoom: 21,
    attribution: '&copy; Google Maps',
  },
  {
    id: 'google_satellite',
    name: 'Google Satellite',
    url: `https://mt1.google.com/vt/lyrs=y&x={x}&y={y}&z={z}&key=${GOOGLE_KEY}`,
    subdomains: 'abcd',
    maxZoom: 21,
    attribution: '&copy; Google Maps Satellite',
  },
  {
    id: 'carto_dark',
    name: 'Dark Ops',
    url: 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
    subdomains: 'abcd',
    maxZoom: 20,
    attribution: '&copy; OSM &copy; CARTO',
  },
  {
    id: 'osm',
    name: 'OpenStreetMap',
    url: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
    subdomains: 'abc',
    maxZoom: 19,
    attribution: '&copy; OpenStreetMap',
  },
]

const CITIES = [
  { name: 'Nashik', center: [19.9975, 73.7898] as [number, number], zoom: 13 },
  { name: 'Mumbai', center: [19.076, 72.8777] as [number, number], zoom: 12 },
  { name: 'Pune', center: [18.5204, 73.8567] as [number, number], zoom: 13 },
  { name: 'Nagpur', center: [21.1458, 79.0882] as [number, number], zoom: 13 },
]


const TIME_FILTERS = ['1h', '6h', '24h', '7d'] as const

const SAFE_ZONES = [
  { id: '1', name: 'Nashik Police HQ', type: 'police' as const, lat: 20.0059, lng: 73.7797, radius_m: 200 },
  { id: '2', name: 'Civil Hospital', type: 'hospital' as const, lat: 19.9974, lng: 73.7826, radius_m: 180 },
  { id: '3', name: 'Panchavati Police', type: 'police' as const, lat: 20.0112, lng: 73.6855, radius_m: 150 },
  { id: '4', name: 'Wockhardt Hospital', type: 'hospital' as const, lat: 19.9912, lng: 73.7786, radius_m: 180 },
  { id: '5', name: 'Satpur Police', type: 'police' as const, lat: 19.9760, lng: 73.8218, radius_m: 150 },
]

export default function LiveMapPage() {
  const [searchParams] = useSearchParams()
  const {
    city, cityCenter, cityZoom, setCity,
    timeFilter, setTimeFilter,
    sosAlerts, setSosAlerts, addSosAlert, resolveSos,
    incidents, setIncidents, addIncident,
    stats, setStats,
    setMeshRelayVisible,
  } = useAppStore()

  const [heatmap, setHeatmap] = useState<HeatmapPoint[]>([])
  const [cityOpen, setCityOpen] = useState(false)
  const [showAllAlerts, setShowAllAlerts] = useState(true)
  const [selectedLayerId, setSelectedLayerId] = useState('google_roads')
  const [layerOpen, setLayerOpen] = useState(false)
  const [newAlertIds, setNewAlertIds] = useState<Set<string>>(new Set())
  const [focusLocation, setFocusLocation] = useState<{center: [number, number], zoom: number} | null>(null)
  const heatRefreshRef = useRef<ReturnType<typeof setInterval>>()


  // ─── Handle Tracking Search Params ────────────────────────────────────
  useEffect(() => {
    const lat = searchParams.get('lat')
    const lng = searchParams.get('lng')
    const email = searchParams.get('track')
    const name = searchParams.get('name')
    
    if (lat && lng) {
      const coords: [number, number] = [parseFloat(lat), parseFloat(lng)]
      setFocusLocation({ center: coords, zoom: 18 })
      
      if (email) {
        toast(`Tracking User: ${name || email}`, { 
          icon: '📍',
          style: { background: '#1a1a1a', color: '#60a5fa', border: '1px solid #3b82f6' }
        })
      }
    }
  }, [searchParams])

  // ─── Load initial data ─────────────────────────────────────────────────
  useEffect(() => {
    Promise.all([fetchSOSAlerts(), fetchStats(), fetchHeatmap(20), fetchIncidents()]).then(([alerts, st, heat, incs]) => {
      setSosAlerts(alerts)
      setStats(st)
      setHeatmap(heat)
      setIncidents(incs)
      
      // Auto-center on latest SOS location if not already focused from URL
      if (alerts.length > 0 && !searchParams.get('lat')) {
        const latest = alerts[0]
        const lat = Number(latest.lat ?? (latest as any).latitude)
        const lng = Number(latest.lng ?? (latest as any).longitude)
        if (lat && lng && !isNaN(lat) && !isNaN(lng)) {
          setFocusLocation({ center: [lat, lng], zoom: 15 })
        }
      }
    })
  }, [searchParams, setSosAlerts, setStats, setIncidents])

  // ─── Heatmap refresh every 30s ────────────────────────────────────────
  useEffect(() => {
    heatRefreshRef.current = setInterval(async () => {
      const heat = await fetchHeatmap(20)
      setHeatmap(heat)
    }, 30000)
    return () => clearInterval(heatRefreshRef.current)
  }, [])

  const handleNewSOS = useCallback((alert: SOSAlert) => {
    addSosAlert(alert)
    setNewAlertIds(prev => new Set([...prev, alert.id]))
    setTimeout(() => setNewAlertIds(prev => { const s = new Set(prev); s.delete(alert.id); return s }), 5000)

    toast(
      (t) => (
        <div className="flex items-start gap-3" onClick={() => toast.dismiss(t.id)}>
          <div className="w-8 h-8 rounded-full flex items-center justify-center flex-shrink-0 animate-pulse"
            style={{ background: 'rgba(239,68,68,0.2)' }}>
            <Radio size={14} className="text-red-400" />
          </div>
          <div>
            <div className="font-semibold text-white text-sm">SOS ALERT RECEIVED</div>
            <div className="text-xs mt-0.5" style={{ color: '#9ca3af' }}>
              {alert.user_name} needs help
            </div>
            <div className="text-xs font-mono mt-1" style={{ color: '#6b7280' }}>
              {(alert.lat ?? (alert as any).latitude)?.toFixed?.(4) || '0.0000'}, {(alert.lng ?? (alert as any).longitude)?.toFixed?.(4) || '0.0000'} • {alert.emergency_type || (alert as any).type || 'other'}
            </div>
          </div>
        </div>
      ),
      {
        duration: 6000,
        style: {
          background: '#1a0000',
          border: '1px solid #ef4444',
          color: 'white',
          maxWidth: '320px',
        },
      }
    )

    setStats({ ...stats, active_sos: stats.active_sos + 1 })
  }, [addSosAlert, setStats, stats])

  // ─── Realtime Subscriptions ──────────────────────────────────────────
  useEffect(() => {
    const sosChannel = supabase
      .channel('sos_alerts_map')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'sos_logs' }, payload => {
        if (payload.eventType === 'INSERT') {
          handleNewSOS(payload.new as SOSAlert)
        } else if (payload.eventType === 'UPDATE') {
          useAppStore.getState().patchSosAlert(payload.new.id, payload.new as SOSAlert)
        }
      })
      .subscribe()

    const incChannel = supabase
      .channel('incidents_map')
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'incidents' }, payload => {
        addIncident(payload.new as any)
      })
      .subscribe()

    return () => { 
      supabase.removeChannel(sosChannel)
      supabase.removeChannel(incChannel)
    }
  }, [addIncident, handleNewSOS])

  const handleNavigate = (alert: SOSAlert) => {
    const lat = Number(alert.lat ?? (alert as any).latitude)
    const lng = Number(alert.lng ?? (alert as any).longitude)
    if (lat && lng) {
      setFocusLocation({ center: [lat, lng], zoom: 18 })
    }
  }

  const handleResolve = async (alert: SOSAlert) => {
    try {
      await resolveSOSAlert(alert.id)
      resolveSos(alert.id)
      toast.success('SOS Alert resolved successfully')
    } catch (e: any) {
      toast.error(e.message || 'Failed to resolve SOS')
    }
  }

  const activeSOS = sosAlerts.filter(a => a.status === 'active')
  const displayedSOS = showAllAlerts ? sosAlerts : activeSOS

  return (
    <div className="relative w-full h-full flex" style={{ background: '#0f0f0f' }}>

      {/* ── Toolbar ──────────────────────────────────────────────────── */}
      <div className="absolute top-4 left-4 right-[296px] z-[1000] flex items-center gap-2">
        {/* City Selector */}
        <div className="relative">
          <button
            onClick={() => setCityOpen(!cityOpen)}
            className="flex items-center gap-2 px-3 py-2 rounded-lg text-sm font-medium text-white"
            style={{ background: '#1a1a1a', border: '1px solid #2a2a2a' }}
          >
            <Shield size={13} className="text-red-500" />
            {city}
            <ChevronDown size={13} className="text-gray-500" />
          </button>
          <AnimatePresence>
            {cityOpen && (
              <motion.div
                initial={{ opacity: 0, y: -4 }}
                animate={{ opacity: 1, y: 0 }}
                exit={{ opacity: 0, y: -4 }}
                className="absolute top-full mt-1 left-0 rounded-lg overflow-hidden shadow-xl z-10"
                style={{ background: '#1a1a1a', border: '1px solid #2a2a2a', minWidth: '140px' }}
              >
                {CITIES.map(c => (
                  <button key={c.name}
                    className="w-full text-left px-4 py-2.5 text-sm hover:bg-white/5 transition-colors"
                    style={{ color: c.name === city ? '#ef4444' : '#e5e7eb' }}
                    onClick={() => { setCity(c.name, c.center, c.zoom); setCityOpen(false) }}>
                    {c.name}
                  </button>
                ))}
              </motion.div>
            )}
          </AnimatePresence>
        </div>

        {/* SOS Alert Filter Toggle */}
        <button
          onClick={() => setShowAllAlerts(!showAllAlerts)}
          className="flex items-center gap-1.5 px-3 py-2 rounded-lg text-xs font-medium transition-all"
          style={{
            background: showAllAlerts ? 'rgba(239, 68, 68, 0.15)' : '#1a1a1a',
            border: showAllAlerts ? '1px solid #ef4444' : '1px solid #2a2a2a',
            color: showAllAlerts ? '#f87171' : '#9ca3af',
          }}
        >
          <Radio size={13} className={showAllAlerts ? 'animate-pulse text-red-500' : ''} />
          {showAllAlerts ? `All SOS Pins (${sosAlerts.length})` : `Active Only (${activeSOS.length})`}
        </button>

        {/* Locate Latest SOS Button */}
        {sosAlerts.length > 0 && (
          <button
            onClick={() => {
              const target = activeSOS.length > 0 ? activeSOS[0] : sosAlerts[0]
              const lat = Number(target.lat ?? (target as any).latitude)
              const lng = Number(target.lng ?? (target as any).longitude)
              if (lat && lng && !isNaN(lat) && !isNaN(lng)) {
                setFocusLocation({ center: [lat, lng], zoom: 17 })
                toast(`Centering on SOS location (${target.user_name || 'Emergency'})`, {
                  icon: '📍',
                  style: { background: '#1a1a1a', color: '#fff', border: '1px solid #ef4444' }
                })
              }
            }}
            className="flex items-center gap-1.5 px-3 py-2 rounded-lg text-xs font-medium text-white transition-all hover:border-red-500"
            style={{ background: '#1a1a1a', border: '1px solid #2a2a2a' }}
          >
            <MapPin size={13} className="text-red-400" />
            Locate SOS
          </button>
        )}

        {/* Time Filter */}
        <div className="flex items-center rounded-lg overflow-hidden" style={{ border: '1px solid #2a2a2a', background: '#1a1a1a' }}>
          {TIME_FILTERS.map(f => (
            <button key={f}
              onClick={() => setTimeFilter(f)}
              className="px-3 py-2 text-xs font-mono transition-colors"
              style={{
                color: timeFilter === f ? 'white' : '#6b7280',
                background: timeFilter === f ? '#ef4444' : 'transparent',
              }}>
              {f}
            </button>
          ))}
        </div>

        <div className="flex-1" />

        {/* Map Layer Selector (Google Maps / Satellite / Dark Ops / OSM) */}
        <div className="relative">
          <button
            onClick={() => setLayerOpen(!layerOpen)}
            className="flex items-center gap-1.5 px-3 py-2 rounded-lg text-xs font-medium text-white transition-all hover:border-gray-500"
            style={{ background: '#1a1a1a', border: '1px solid #2a2a2a' }}
          >
            <Layers size={13} className="text-blue-400" />
            {MAP_LAYERS.find(l => l.id === selectedLayerId)?.name || 'Google Maps'}
            <ChevronDown size={12} className="text-gray-500" />
          </button>
          <AnimatePresence>
            {layerOpen && (
              <motion.div
                initial={{ opacity: 0, y: -4 }}
                animate={{ opacity: 1, y: 0 }}
                exit={{ opacity: 0, y: -4 }}
                className="absolute top-full mt-1 right-0 rounded-lg overflow-hidden shadow-xl z-[1500]"
                style={{ background: '#1a1a1a', border: '1px solid #2a2a2a', minWidth: '150px' }}
              >
                {MAP_LAYERS.map(l => (
                  <button
                    key={l.id}
                    className="w-full text-left px-3.5 py-2 text-xs hover:bg-white/5 transition-colors flex items-center justify-between"
                    style={{ color: l.id === selectedLayerId ? '#60a5fa' : '#e5e7eb' }}
                    onClick={() => { setSelectedLayerId(l.id); setLayerOpen(false) }}
                  >
                    <span>{l.name}</span>
                    {l.id === selectedLayerId && <span className="w-1.5 h-1.5 rounded-full bg-blue-500" />}
                  </button>
                ))}
              </motion.div>
            )}
          </AnimatePresence>
        </div>

        {/* Simulate Mesh */}
        <button
          onClick={() => setMeshRelayVisible(true)}
          className="flex items-center gap-2 px-3 py-2 rounded-lg text-xs font-medium transition-all hover:border-blue-500/50"
          style={{ background: '#1a1a1a', border: '1px solid #2a2a2a', color: '#60a5fa' }}
        >
          <Network size={13} />
          Mesh Relay
        </button>
      </div>

      {/* ── Map ─────────────────────────────────────────────────────── */}
      <div className="flex-1 h-full relative" style={{ minHeight: '100%', width: '100%' }}>
        <MapContainer
          center={cityCenter}
          zoom={cityZoom}
          style={{ height: '100%', width: '100%', minHeight: '100%', background: '#0f0f0f' }}
          zoomControl={false}
        >
          {(() => {
            const currentLayer = MAP_LAYERS.find(l => l.id === selectedLayerId) || MAP_LAYERS[0]
            return (
              <TileLayer
                key={currentLayer.id}
                url={currentLayer.url}
                subdomains={currentLayer.subdomains}
                maxZoom={currentLayer.maxZoom}
                attribution={currentLayer.attribution}
              />
            )
          })()}


          <MapController center={cityCenter} zoom={cityZoom} focus={focusLocation} />

          {/* Heatmap */}
          <HeatmapLayer points={heatmap} />

          {/* Safe Zones */}
          {SAFE_ZONES.map(z => (
            <Circle key={z.id}
              center={[z.lat, z.lng]}
              radius={z.radius_m}
              pathOptions={{
                color: z.type === 'police' ? '#3b82f6' : '#22c55e',
                fillColor: z.type === 'police' ? '#3b82f6' : '#22c55e',
                fillOpacity: 0.08,
                weight: 1.5,
              }}
            >
              <Popup>
                <div style={{ fontFamily: 'DM Sans, sans-serif' }}>
                  <div style={{ fontWeight: '600', color: 'white', marginBottom: '4px' }}>{z.name}</div>
                  <div style={{ fontSize: '11px', color: '#9ca3af', textTransform: 'capitalize' }}>{z.type.replace('_', ' ')}</div>
                </div>
              </Popup>
            </Circle>
          ))}

          {/* SOS Markers */}
          {displayedSOS.map(alert => (
            <SOSMarker key={alert.id} alert={alert} isNew={newAlertIds.has(alert.id)} onNavigate={handleNavigate} onResolve={handleResolve} />
          ))}


          {/* Incident Markers (recent 24h) */}
          {incidents
            .filter(inc => Date.now() - new Date(inc.created_at).getTime() < 86400000)
            .map(inc => (
              <IncidentMarker key={inc.id} incident={inc} />
            ))
          }
        </MapContainer>

        {/* Mesh relay overlay */}
        <MeshRelayOverlay />
      </div>

      {/* ── Stats Sidebar ─────────────────────────────────────────── */}
      <StatsSidebar activeSOS={activeSOS} allSOS={sosAlerts} onSelectSOS={handleNavigate} />
    </div>
  )
}

function StatsSidebar({ activeSOS, allSOS, onSelectSOS }: { activeSOS: SOSAlert[]; allSOS: SOSAlert[]; onSelectSOS: (alert: SOSAlert) => void }) {
  const { stats } = useAppStore()
  const alertsToShow = activeSOS.length > 0 ? activeSOS : allSOS.slice(0, 5)

  const statCards = [
    {
      label: 'Active SOS Alerts',
      value: stats.active_sos,
      icon: Radio,
      color: '#ef4444',
      bg: 'rgba(239,68,68,0.08)',
      pulse: stats.active_sos > 0,
    },
    {
      label: 'Incidents (24h)',
      value: stats.incidents_24h,
      icon: AlertTriangle,
      color: '#f59e0b',
      bg: 'rgba(245,158,11,0.08)',
      pulse: false,
    },
    {
      label: 'High Risk Zones',
      value: stats.high_risk_zones,
      icon: Shield,
      color: '#f97316',
      bg: 'rgba(249,115,22,0.08)',
      pulse: false,
    },
    {
      label: 'Mesh Nodes Active',
      value: stats.mesh_nodes_active,
      icon: Cpu,
      color: '#22c55e',
      bg: 'rgba(34,197,94,0.08)',
      pulse: false,
    },
  ]

  return (
    <motion.div
      initial={{ x: 280 }}
      animate={{ x: 0 }}
      transition={{ type: 'spring', stiffness: 200, damping: 28 }}
      className="w-72 h-full flex flex-col overflow-y-auto z-[500]"
      style={{ background: '#0f0f0f', borderLeft: '1px solid #1e1e1e' }}
    >
      <div className="px-4 pt-5 pb-3 border-b" style={{ borderColor: '#1e1e1e' }}>
        <div className="flex items-center gap-2">
          <div className="w-2 h-2 rounded-full bg-red-500 animate-pulse" />
          <span className="text-xs font-mono text-gray-500 uppercase tracking-wider">Live Dashboard</span>
        </div>
      </div>

      <div className="p-3 space-y-2">
        {statCards.map((card) => (
          <motion.div
            key={card.label}
            layout
            className="stat-card rounded-xl p-4"
            style={{ background: '#141414', border: '1px solid #1e1e1e' }}
          >
            <div className="flex items-center justify-between mb-3">
              <div className="flex items-center justify-center w-9 h-9 rounded-lg" style={{ background: card.bg }}>
                <card.icon size={16} style={{ color: card.color }} />
              </div>
              {card.pulse && (
                <div className="flex items-center gap-1.5">
                  <div className="w-1.5 h-1.5 rounded-full bg-red-500 status-active" />
                  <span className="text-xs font-mono text-red-400">LIVE</span>
                </div>
              )}
            </div>
            <div className="text-3xl font-display font-bold text-white">{card.value}</div>
            <div className="text-xs text-gray-600 mt-1 font-body">{card.label}</div>
          </motion.div>
        ))}
      </div>

      {/* Active / Recent SOS feed */}
      <div className="px-4 pt-3 pb-2 border-t" style={{ borderColor: '#1e1e1e' }}>
        <div className="flex items-center justify-between mb-3">
          <span className="text-xs font-mono text-gray-500 uppercase tracking-wider">
            {activeSOS.length > 0 ? 'Active Alerts' : 'Recent Alerts'}
          </span>
          <span className="text-xs font-mono text-red-400">{alertsToShow.length}</span>
        </div>
        <div className="space-y-2">
          <AnimatePresence mode="popLayout">
            {alertsToShow.map((alert) => (
              <SOSSidebarItem key={alert.id} alert={alert} onSelect={onSelectSOS} />
            ))}
          </AnimatePresence>
          {alertsToShow.length === 0 && (
            <div className="text-xs text-gray-600 text-center py-4 font-mono">No alerts logged</div>
          )}
        </div>
      </div>

      {/* Legend */}
      <div className="mt-auto px-4 py-4 border-t" style={{ borderColor: '#1e1e1e' }}>
        <div className="text-xs font-mono text-gray-600 uppercase tracking-wider mb-3">Legend</div>
        <div className="space-y-2">
          {[
            { color: '#ef4444', label: 'Active SOS Alert', dot: true },
            { color: '#10b981', label: 'Resolved Incident', dot: false },
            { color: '#3b82f6', label: 'Police Station', dot: false },
            { color: '#22c55e', label: 'Hospital', dot: false },
          ].map(l => (
            <div key={l.label} className="flex items-center gap-2">
              {l.dot
                ? <div className="w-2.5 h-2.5 rounded-full animate-pulse" style={{ background: l.color }} />
                : <div className="w-2.5 h-2.5 rounded-sm opacity-80" style={{ background: l.color }} />
              }
              <span className="text-xs text-gray-400">{l.label}</span>
            </div>
          ))}
          <div className="flex items-center gap-2">
            <div className="w-10 h-1.5 rounded" style={{ background: 'linear-gradient(90deg, #1e3a5f, #f59e0b, #ef4444)' }} />
            <span className="text-xs text-gray-500">Risk Heatmap</span>
          </div>
        </div>
      </div>

      {/* Last refresh */}
      <div className="px-4 py-2 border-t" style={{ borderColor: '#1e1e1e' }}>
        <div className="flex items-center gap-1.5 text-xs text-gray-700 font-mono">
          <RefreshCw size={10} className="animate-spin" style={{ animationDuration: '3s' }} />
          Heatmap refreshes every 30s
        </div>
      </div>
    </motion.div>
  )
}

const SOSSidebarItem = forwardRef<HTMLDivElement, { alert: SOSAlert; onSelect?: (alert: SOSAlert) => void }>(({ alert, onSelect }, ref) => {
  const initialName = alert.user_name || (alert as any).name || 'Unknown User'
  const [displayName, setDisplayName] = useState(initialName)
  const eType = alert.emergency_type || (alert as any).type || 'other'
  const isResolved = alert.status === 'resolved'

  useEffect(() => {
    async function fetchRealName() {
      const email = alert.user_email || (alert as any).email
      if (displayName === 'Unknown User' && email) {
        const realName = await getUserName(email)
        if (realName) {
          setDisplayName(realName)
        }
      }
    }
    fetchRealName()
  }, [initialName, alert])

  return (
    <motion.div
      ref={ref}
      initial={{ opacity: 0, x: 20, height: 0 }}
      animate={{ opacity: 1, x: 0, height: 'auto' }}
      exit={{ opacity: 0, x: -20, height: 0 }}
      layout
      onClick={() => onSelect?.(alert)}
      className="rounded-lg p-3 cursor-pointer transition-all hover:scale-[1.02]"
      style={{
        background: isResolved ? '#111814' : '#1a0000',
        border: isResolved ? '1px solid rgba(34,197,94,0.3)' : '1px solid rgba(239,68,68,0.3)'
      }}
    >
      <div className="flex items-start justify-between gap-2">
        <div className="flex-1 min-w-0">
          <div className="flex items-center justify-between">
            <h3 className="text-sm font-display font-bold text-white mb-1 truncate">
              {displayName}
            </h3>
            <span className={`text-[9px] px-1.5 py-0.5 rounded font-bold uppercase font-mono ${
              isResolved ? 'bg-green-500/10 text-green-400 border border-green-500/20' : 'bg-red-500/10 text-red-400 border border-red-500/20'
            }`}>
              {isResolved ? 'Resolved' : 'Active'}
            </span>
          </div>
          <div className="text-xs text-gray-500 font-mono mt-0.5">
            {Number(alert.lat ?? (alert as any).latitude ?? 0).toFixed(4)}, {Number(alert.lng ?? (alert as any).longitude ?? 0).toFixed(4)}
          </div>
          <div className="flex items-center gap-2 mt-1 flex-wrap">
            <span className="text-[10px] px-1.5 py-0.5 rounded uppercase font-bold tracking-wider"
              style={{ background: 'rgba(239,68,68,0.1)', color: '#f87171', border: '1px solid rgba(239,68,68,0.2)' }}>
              {eType}
            </span>
            <span className="text-[10px] px-1.5 py-0.5 rounded bg-[#1a1a1a] text-gray-500 font-mono">
              {new Date(alert.created_at).toLocaleDateString()}
            </span>
          </div>
        </div>
      </div>
      <div className="flex items-center justify-between mt-2 pt-1 border-t border-white/5">
        <div className="flex items-center gap-1">
          <Clock size={9} className="text-gray-500" />
          <span className="text-[10px] text-gray-500 font-mono">
            {new Date(alert.created_at).toLocaleTimeString()}
          </span>
        </div>
        <span className="text-[10px] text-blue-400 font-semibold flex items-center gap-0.5">
          <MapPin size={10} /> View Map
        </span>
      </div>
    </motion.div>
  )
})

