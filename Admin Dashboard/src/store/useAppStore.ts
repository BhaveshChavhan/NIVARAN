import { create } from 'zustand'
import type { SOSAlert, Incident, DashboardStats, TimeFilter } from '../types'

interface AppStore {
  // Auth
  isAuthenticated: boolean
  setAuthenticated: (v: boolean) => void

  // City
  city: string
  cityCenter: [number, number]
  cityZoom: number
  setCity: (name: string, center: [number, number], zoom: number) => void

  // Time filter
  timeFilter: TimeFilter
  setTimeFilter: (f: TimeFilter) => void

  // SOS Alerts
  sosAlerts: SOSAlert[]
  setSosAlerts: (alerts: SOSAlert[]) => void
  addSosAlert: (alert: SOSAlert) => void
  resolveSos: (id: string) => void
  patchSosAlert: (id: string, data: Partial<SOSAlert>) => void

  incidents: Incident[]
  setIncidents: (incs: Incident[]) => void
  addIncident: (inc: Incident) => void
  patchIncident: (id: string, data: Partial<Incident>) => void

  // Stats
  stats: DashboardStats
  setStats: (s: DashboardStats) => void

  // UI
  meshRelayVisible: boolean
  setMeshRelayVisible: (v: boolean) => void
  simulatingMesh: boolean
  setSimulatingMesh: (v: boolean) => void
}

export const useAppStore = create<AppStore>((set) => ({
  isAuthenticated: !!localStorage.getItem('safenet_token'),
  setAuthenticated: (v) => {
    if (v) localStorage.setItem('safenet_token', 'demo-token')
    else localStorage.removeItem('safenet_token')
    set({ isAuthenticated: v })
  },

  city: 'Nashik',
  cityCenter: [19.9975, 73.7898],
  cityZoom: 12,
  setCity: (name, center, zoom) => set({ city: name, cityCenter: center, cityZoom: zoom }),

  timeFilter: '24h',
  setTimeFilter: (f) => set({ timeFilter: f }),

  sosAlerts: [],
  setSosAlerts: (alerts) => set({ sosAlerts: alerts }),
  addSosAlert: (alert) => set(s => ({ sosAlerts: [alert, ...s.sosAlerts] })),
  resolveSos: (id) => set(s => ({
    sosAlerts: s.sosAlerts.map(a =>
      a.id === id ? { ...a, status: 'resolved' as const, resolved_at: new Date().toISOString() } : a
    )
  })),
  patchSosAlert: (id, data) => set(s => ({
    sosAlerts: s.sosAlerts.map(a => a.id === id ? { ...a, ...data } : a)
  })),

  incidents: [],
  setIncidents: (incs) => set({ incidents: incs }),
  addIncident: (inc) => set(s => ({ incidents: [inc, ...s.incidents] })),
  patchIncident: (id, data) => set(s => ({
    incidents: s.incidents.map(i => i.id === id ? { ...i, ...data } : i)
  })),

  stats: { active_sos: 0, incidents_24h: 0, high_risk_zones: 0, mesh_nodes_active: 0, total_users: 0 },
  setStats: (s) => set({ stats: s }),

  meshRelayVisible: false,
  setMeshRelayVisible: (v) => set({ meshRelayVisible: v }),
  simulatingMesh: false,
  setSimulatingMesh: (v) => set({ simulatingMesh: v }),
}))
