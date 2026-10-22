import { Marker, Popup } from 'react-leaflet'
import L from 'leaflet'
import { format } from 'date-fns'
import type { Incident } from '../../types'

const createIncidentIcon = (severity: string) => {
  const color = severity === 'critical' ? '#ef4444' : severity === 'high' ? '#f97316' : severity === 'medium' ? '#f59e0b' : '#22c55e'
  return L.divIcon({
    className: '',
    html: `
      <div class="incident-marker-wrapper">
        <div class="incident-dot" style="background: ${color}"></div>
      </div>
    `,
    iconSize: [16, 16],
    iconAnchor: [8, 8],
    popupAnchor: [0, -8],
  })
}

interface Props {
  incident: Incident
}

export function IncidentMarker({ incident }: Props) {
  const lat = incident.lat || (incident as any).latitude || 0
  const lng = incident.lng || (incident as any).longitude || 0

  if (!lat || !lng) return null

  return (
    <Marker position={[lat, lng]} icon={createIncidentIcon(incident.severity)}>
      <Popup>
        <div style={{ minWidth: '200px', fontFamily: 'DM Sans, sans-serif' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: '8px', marginBottom: '8px' }}>
            <span style={{
              background: incident.severity === 'critical' ? 'rgba(239,68,68,0.15)' : 'rgba(245,158,11,0.15)',
              color: incident.severity === 'critical' ? '#ef4444' : '#f59e0b',
              fontSize: '10px',
              padding: '2px 8px',
              borderRadius: '9999px',
              fontWeight: '600',
              textTransform: 'uppercase',
            }}>
              {incident.severity}
            </span>
            <span style={{ fontSize: '10px', color: '#9ca3af', textTransform: 'capitalize' }}>
              {incident.type}
            </span>
          </div>

          <div style={{ fontWeight: '600', fontSize: '13px', color: 'white', marginBottom: '4px' }}>
            {incident.title}
          </div>
          <div style={{ fontSize: '11px', color: '#9ca3af', marginBottom: '6px' }}>
            {incident.address}
          </div>
          <div style={{ fontSize: '11px', color: '#6b7280' }}>
            {format(new Date(incident.created_at), 'dd MMM, HH:mm')}
          </div>
        </div>
      </Popup>
    </Marker>
  )
}
