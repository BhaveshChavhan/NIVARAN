export interface SOSAlert {
  id: string
  user_name: string
  user_email?: string
  user_phone?: string
  lat: number
  lng: number
  latitude?: number
  longitude?: number
  emergency_type: 'medical' | 'fire' | 'crime' | 'accident' | 'other'
  status: 'active' | 'resolved' | 'false_alarm'
  mesh_path: string[] // e.g. ["Device_A", "Device_B", "Gateway"]
  created_at: string
  resolved_at?: string
  notes?: string
  audio_url?: string
}

export interface Incident {
  id: string
  title: string
  type: 'theft' | 'assault' | 'fire' | 'accident' | 'vandalism' | 'other'
  severity: 'low' | 'medium' | 'high' | 'critical'
  source: 'user_report' | 'scrape' | 'police' | 'sensor'
  lat: number
  lng: number
  address: string
  description: string
  verified: boolean
  risk_score: number
  created_at: string
  ai_summary?: string
}

export interface HeatmapPoint {
  lat: number
  lng: number
  intensity: number
}

export interface SafeZone {
  id: string
  name: string
  type: 'police' | 'hospital' | 'fire_station'
  lat: number
  lng: number
  radius_m: number
}

export interface MeshNode {
  id: string
  device_id: string
  lat: number
  lng: number
  battery: number
  last_seen: string
  status: 'active' | 'inactive'
}

export interface City {
  name: string
  lat: number
  lng: number
  zoom: number
}

export type TimeFilter = '1h' | '6h' | '24h' | '7d'

export interface DashboardStats {
  active_sos: number
  incidents_24h: number
  high_risk_zones: number
  mesh_nodes_active: number
  total_users: number
}

export interface AnalyticsData {
  incidents_by_day: { date: string; count: number }[]
  incidents_by_type: { type: string; count: number }[]
  incidents_by_source: { source: string; count: number }[]
  hourly_heatmap: { day: number; hour: number; count: number }[]
}
