import axios from 'axios'
import type { SOSAlert, Incident, HeatmapPoint, AnalyticsData, DashboardStats } from '../types'
import { supabase } from './supabase'

export const BASE = (import.meta as any).env.VITE_API_URL || 'http://localhost:3000'

export const api = axios.create({
  baseURL: BASE,
  timeout: 8000,
  headers: { 'Content-Type': 'application/json' },
})

api.interceptors.request.use(cfg => {
  const token = localStorage.getItem('safenet_token')
  if (token) cfg.headers.Authorization = `Bearer ${token}`
  return cfg
})



// ─── API Calls ─────────────────────────────────────────────────────────────
export const fetchUsersList = async (): Promise<any[]> => {
  try {
    const { data, error } = await supabase
      .from('users')
      .select('*')
      .order('created_at', { ascending: false })
    if (error) throw error
    return data || []
  } catch (error) {
    console.error('fetchUsersList error:', error)
    return []
  }
}

export const fetchHeatmap = async (radius_km = 20): Promise<HeatmapPoint[]> => {
  try {
    const { data, error } = await supabase.from('incidents').select('lat, lng, risk_score')
    if (error) {
      console.warn('Heatmap fetch error (possibly missing table):', error.message)
      return []
    }
    return (data || []).map(d => ({
      lat: d.lat || 0,
      lng: d.lng || 0,
      intensity: (d.risk_score || 0) / 100
    }))
  } catch (error) {
    console.error('fetchHeatmap error:', error)
    return []
  }
}

export const fetchIncidents = async (params?: Record<string, string>): Promise<Incident[]> => {
  try {
    let query = supabase.from('incidents').select('*').order('created_at', { ascending: false })
    
    if (params?.type && params.type !== 'all') query = query.eq('type', params.type)
    if (params?.severity && params.severity !== 'all') query = query.eq('severity', params.severity)
    
    const { data, error } = await query
    if (error) throw error
    return data as Incident[]
  } catch (error) {
    console.error('fetchIncidents error:', error)
    return []
  }
}

export const fetchSOSAlerts = async (): Promise<SOSAlert[]> => {
  try {
    const { data, error } = await supabase
      .from('sos_logs')
      .select('*')
      .order('created_at', { ascending: false })
    
    if (error) throw error
    return data as SOSAlert[]
  } catch (error) {
    console.error('fetchSOSAlerts error:', error)
    return []
  }
}

export const fetchFIRs = async (): Promise<any[]> => {
  try {
    const { data, error } = await supabase
      .from('firs')
      .select('*')
      .order('created_at', { ascending: false })
    
    if (error) throw error
    return data as any[]
  } catch (error) {
    console.error('fetchFIRs error:', error)
    return []
  }
}

export const triggerSOS = async (data: Partial<SOSAlert>): Promise<SOSAlert> => {
  return (await api.post('/sos/trigger', data)).data
}

export const resolveSOSAlert = async (id: string): Promise<void> => {
  const { error } = await supabase
    .from('sos_logs')
    .update({ status: 'resolved' })
    .eq('id', id)
  
  if (error) {
    console.error('resolveSOSAlert error:', error)
    throw error
  }
}

export const patchIncident = async (id: string, data: Partial<Incident>): Promise<any> => {
  const { data: updated, error } = await supabase
    .from('incidents')
    .update(data)
    .eq('id', id)
    .select()
    .single()
  
  if (error) {
    console.error('patchIncident error:', error)
    throw error
  }
  return updated
}

const nameCache: Record<string, string> = {}
const namePromises: Record<string, Promise<string>> = {}

export const getUserName = async (email: string): Promise<string> => {
  if (!email) return ''
  if (email in nameCache) return nameCache[email]
  if (email in namePromises) return namePromises[email]
  
  namePromises[email] = (async () => {
    try {
      const { data, error } = await supabase
        .from('users')
        .select('name')
        .eq('email', email)
        .maybeSingle()
      
      if (data?.name) {
        nameCache[email] = data.name
        return data.name
      }
      return ''
    } catch (err) {
      console.error('Error fetching real name:', err)
      return ''
    }
  })()
    
  return namePromises[email]
}

export const fetchAISummary = async (zoneId: string): Promise<{ summary: string }> => {
  try {
    return (await api.get(`/ai/zone-summary?zone_id=${zoneId}`)).data
  } catch (error) {
    return { summary: 'AI summary currently unavailable for this zone.' }
  }
}

export const fetchAnalytics = async (): Promise<AnalyticsData> => {
  try {
    const fourteenDaysAgo = new Date(Date.now() - 14 * 24 * 60 * 60 * 1000).toISOString()
    
    // Fetch last 14 days of incidents and sos_logs
    const [incRes, sosRes] = await Promise.all([
      supabase.from('incidents').select('type, source, created_at').gte('created_at', fourteenDaysAgo),
      supabase.from('sos_logs').select('emergency_type, type, created_at').gte('created_at', fourteenDaysAgo)
    ])

    const incidents = incRes.data || []
    const sosLogs = sosRes.data || []

    // 1. Unified events
    const allEvents: { type: string, source: string, created_at: string, dateObj: Date }[] = [
      ...incidents.map(inc => ({
        type: inc.type || 'other',
        source: inc.source === 'police' ? 'Police Data' : 'User Reports',
        created_at: inc.created_at,
        dateObj: new Date(inc.created_at)
      })),
      ...sosLogs.map((sos: any) => ({
        type: sos.emergency_type || sos.type || 'other',
        source: 'App SOS Triggers',
        created_at: sos.created_at,
        dateObj: new Date(sos.created_at)
      }))
    ]

    // 2. Trend Line (14 days zero-fill)
    const byDayMap: Record<string, number> = {}
    for (let i = 13; i >= 0; i--) {
      const d = new Date(Date.now() - i * 24 * 60 * 60 * 1000)
      const dateStr = d.toISOString().split('T')[0]
      byDayMap[dateStr] = 0
    }
    
    // 3. Types and Sources
    const byTypeMap: Record<string, number> = {}
    const bySourceMap: Record<string, number> = {}
    
    // 4. Heatmap preparation
    const heatmapMap: Record<string, number> = {} 

    allEvents.forEach(ev => {
      // By Day
      const dateStr = ev.created_at.split('T')[0]
      if (byDayMap[dateStr] !== undefined) {
        byDayMap[dateStr]++
      }

      // By Type
      byTypeMap[ev.type] = (byTypeMap[ev.type] || 0) + 1

      // By Source
      bySourceMap[ev.source] = (bySourceMap[ev.source] || 0) + 1

      // Heatmap
      const dayOfWeek = ev.dateObj.getDay()
      const hourOfDay = ev.dateObj.getHours()
      const heatKey = `${dayOfWeek}_${hourOfDay}`
      heatmapMap[heatKey] = (heatmapMap[heatKey] || 0) + 1
    })

    const hourly_heatmap = []
    for (let d = 0; d < 7; d++) {
      for (let h = 0; h < 24; h++) {
        hourly_heatmap.push({
          day: d,
          hour: h,
          count: heatmapMap[`${d}_${h}`] || 0
        })
      }
    }

    return {
      incidents_by_day: Object.entries(byDayMap).map(([date, count]) => ({ date, count })),
      incidents_by_type: Object.entries(byTypeMap).map(([type, count]) => ({ type, count })),
      incidents_by_source: Object.entries(bySourceMap).map(([source, count]) => ({ source, count })),
      hourly_heatmap
    }
  } catch (error) {
    console.error('fetchAnalytics error:', error)
    return {
      incidents_by_day: [],
      incidents_by_type: [],
      incidents_by_source: [],
      hourly_heatmap: []
    }
  }
}

export const fetchStats = async (): Promise<DashboardStats> => {
  try {
    const yesterday = new Date(Date.now() - 86400000).toISOString().split('T')[0]
    
    // Perform queries and handle potential errors (like missing tables)
    const { count: sosCount, error: sosErr } = await supabase.from('sos_logs').select('*', { count: 'exact', head: true }).eq('status', 'active')
    const { count: incCount, error: incErr } = await supabase.from('incidents').select('*', { count: 'exact', head: true }).gt('created_at', yesterday)
    const { count: meshCount, error: meshErr } = await supabase.from('mesh_nodes').select('*', { count: 'exact', head: true }).eq('status', 'active')
    const { count: userCount, error: userErr } = await supabase.from('users').select('*', { count: 'exact', head: true })

    if (sosErr) console.warn('sos_logs count error:', sosErr.message)
    if (incErr) console.warn('incidents count error:', incErr.message)
    if (meshErr) console.warn('mesh_nodes count error:', meshErr.message)
    if (userErr) console.warn('users count error:', userErr.message)

    return {
      active_sos: sosCount || 0,
      incidents_24h: incCount || 0,
      high_risk_zones: 3, 
      mesh_nodes_active: meshCount || 4, 
      total_users: userCount || 0,
    }
  } catch (error) {
    console.error('fetchStats error:', error)
    return {
      active_sos: 0,
      incidents_24h: 0,
      high_risk_zones: 0,
      mesh_nodes_active: 0,
      total_users: 0
    }
  }
}

// ─── Routing ───────────────────────────────────────────────────────────────
export const fetchRoute = async (start: [number, number], end: [number, number]): Promise<[number, number][]> => {
  try {
    const url = `https://router.project-osrm.org/route/v1/driving/${start[1]},${start[0]};${end[1]},${end[0]}?overview=full&geometries=geojson`
    const { data } = await axios.get(url)
    
    if (data.routes && data.routes.length > 0) {
      // OSRM returns coordinates as [lng, lat], we need [lat, lng] for Leaflet
      return data.routes[0].geometry.coordinates.map((coord: [number, number]) => [coord[1], coord[0]])
    }
    return []
  } catch (error) {
    console.error('fetchRoute error:', error)
    return []
  }
}
