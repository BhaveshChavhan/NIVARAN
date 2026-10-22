import { useEffect, useRef } from 'react'
import { useMap } from 'react-leaflet'
import L from 'leaflet'
import type { HeatmapPoint } from '../../types'

if (typeof window !== 'undefined') {
  ;(window as any).L = L
}


interface Props {
  points: HeatmapPoint[]
}

export function HeatmapLayer({ points }: Props) {
  const map = useMap()
  const heatRef = useRef<any>(null)

  useEffect(() => {
    // Dynamically import leaflet.heat
    import('leaflet.heat').then(() => {
      const L = (window as any).L || map.options // fallback
      if (heatRef.current) {
        map.removeLayer(heatRef.current)
      }
      if (points.length === 0) return

      const heatData = points.map(p => [p.lat, p.lng, p.intensity] as [number, number, number])

      try {
        const heat = (window as any).L?.heatLayer
          ? (window as any).L.heatLayer(heatData, {
              radius: 35,
              blur: 25,
              maxZoom: 16,
              max: 1.0,
              gradient: { 0.2: '#1e3a5f', 0.4: '#1e5a8f', 0.6: '#f59e0b', 0.8: '#f97316', 1.0: '#ef4444' },
            })
          : null

        if (heat) {
          heat.addTo(map)
          heatRef.current = heat
        }
      } catch (e) {
        console.warn('leaflet.heat not available, skipping heatmap layer')
      }
    }).catch(() => {
      console.warn('leaflet.heat import failed')
    })

    return () => {
      if (heatRef.current) {
        try { map.removeLayer(heatRef.current) } catch {}
      }
    }
  }, [points, map])

  return null
}
