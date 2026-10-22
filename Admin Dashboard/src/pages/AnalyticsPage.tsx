import { useEffect, useState } from 'react'
import { motion } from 'framer-motion'
import {
  LineChart, Line, BarChart, Bar, PieChart, Pie, Cell,
  XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, Legend
} from 'recharts'
import { TrendingUp, BarChart2, PieChart as PieIcon, Grid } from 'lucide-react'
import { fetchAnalytics } from '../lib/api'
import type { AnalyticsData } from '../types'

const DAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']

const TYPE_COLORS: Record<string, string> = {
  theft: '#ef4444',
  assault: '#f97316',
  fire: '#f59e0b',
  accident: '#8b5cf6',
  vandalism: '#3b82f6',
  other: '#6b7280',
}

const SOURCE_COLORS = ['#ef4444', '#3b82f6', '#22c55e', '#f59e0b']

const tooltipStyle = {
  contentStyle: { background: '#1a1a1a', border: '1px solid #2a2a2a', borderRadius: '8px', fontFamily: 'JetBrains Mono', fontSize: '11px', color: '#e5e7eb' },
  itemStyle: { color: '#9ca3af' },
  labelStyle: { color: '#e5e7eb', marginBottom: '4px' },
}

function ChartCard({ title, icon: Icon, children }: { title: string; icon: React.ElementType; children: React.ReactNode }) {
  return (
    <motion.div
      initial={{ opacity: 0, y: 12 }}
      animate={{ opacity: 1, y: 0 }}
      className="rounded-xl p-5"
      style={{ background: '#141414', border: '1px solid #1e1e1e' }}
    >
      <div className="flex items-center gap-2 mb-5">
        <div className="flex items-center justify-center w-7 h-7 rounded-lg" style={{ background: 'rgba(239,68,68,0.1)' }}>
          <Icon size={13} className="text-red-400" />
        </div>
        <span className="text-sm font-display font-semibold text-white">{title}</span>
      </div>
      {children}
    </motion.div>
  )
}

function HeatmapGrid({ data }: { data: AnalyticsData['hourly_heatmap'] }) {
  const max = Math.max(...data.map(d => d.count), 1)

  const getColor = (count: number) => {
    if (count === 0) return '#1a1a1a'
    const ratio = count / max
    if (ratio < 0.25) return '#1e3a5f'
    if (ratio < 0.5) return '#1e5a8f'
    if (ratio < 0.75) return '#f59e0b'
    return '#ef4444'
  }

  return (
    <div className="overflow-x-auto">
      <div style={{ minWidth: '600px' }}>
        {/* Hour labels */}
        <div className="flex gap-1 mb-1 ml-8">
          {Array.from({ length: 24 }, (_, h) => (
            <div key={h} className="text-center text-gray-700 font-mono" style={{ fontSize: '9px', width: '22px' }}>
              {h % 4 === 0 ? `${h}h` : ''}
            </div>
          ))}
        </div>

        {/* Grid rows */}
        {DAYS.map((day, dayIdx) => (
          <div key={day} className="flex items-center gap-1 mb-1">
            <div className="text-gray-600 font-mono text-right" style={{ fontSize: '10px', width: '28px' }}>{day}</div>
            {Array.from({ length: 24 }, (_, hour) => {
              const cell = data.find(d => d.day === dayIdx && d.hour === hour)
              const count = cell?.count || 0
              return (
                <div
                  key={hour}
                  className="heatmap-cell rounded-sm cursor-default"
                  style={{ width: '22px', height: '18px', background: getColor(count) }}
                  title={`${day} ${hour}:00 — ${count} incidents`}
                />
              )
            })}
          </div>
        ))}

        {/* Color scale */}
        <div className="flex items-center gap-2 mt-3 ml-8">
          <span className="text-xs text-gray-600 font-mono">Low</span>
          <div className="flex gap-0.5">
            {['#1a1a1a', '#1e3a5f', '#1e5a8f', '#f59e0b', '#ef4444'].map(c => (
              <div key={c} className="w-5 h-3 rounded-sm" style={{ background: c }} />
            ))}
          </div>
          <span className="text-xs text-gray-600 font-mono">High</span>
        </div>
      </div>
    </div>
  )
}

export default function AnalyticsPage() {
  const [data, setData] = useState<AnalyticsData | null>(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    fetchAnalytics().then(d => { setData(d); setLoading(false) })
  }, [])

  if (loading || !data) {
    return (
      <div className="flex items-center justify-center h-full" style={{ background: '#0f0f0f' }}>
        <div className="text-center">
          <div className="w-8 h-8 border-2 border-red-500 border-t-transparent rounded-full animate-spin mx-auto mb-3" />
          <div className="text-sm text-gray-600 font-mono">Loading analytics...</div>
        </div>
      </div>
    )
  }

  const totalIncidents = (data.incidents_by_type || []).reduce((a, b) => a + b.count, 0)
  const avgPerDay = data.incidents_by_day.length > 0 
    ? Math.round(data.incidents_by_day.reduce((a, b) => a + b.count, 0) / data.incidents_by_day.length)
    : 0
  const peakDay = data.incidents_by_day.length > 0 
    ? data.incidents_by_day.reduce((a, b) => a.count > b.count ? a : b)
    : { date: 'N/A', count: 0 }

  return (
    <div className="h-full overflow-y-auto" style={{ background: '#0f0f0f' }}>
      <div className="px-6 py-5 border-b" style={{ borderColor: '#1e1e1e' }}>
        <h1 className="text-lg font-display font-bold text-white">Analytics</h1>
        <p className="text-xs text-gray-600 font-mono mt-0.5">Last 14 days • Nashik region</p>
      </div>

      <div className="p-6 space-y-5">
        {/* KPI row */}
        <div className="grid grid-cols-3 gap-4">
          {[
            { label: 'Total Incidents', value: totalIncidents, sub: 'last 14 days' },
            { label: 'Daily Average', value: avgPerDay, sub: 'incidents/day' },
            { label: 'Peak Day', value: peakDay.count, sub: peakDay.date },
          ].map((kpi, i) => (
            <motion.div key={kpi.label} initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: i * 0.1 }}
              className="rounded-xl p-4" style={{ background: '#141414', border: '1px solid #1e1e1e' }}>
              <div className="text-xs text-gray-600 font-mono uppercase tracking-wider mb-1">{kpi.label}</div>
              <div className="text-3xl font-display font-bold text-white">{kpi.value}</div>
              <div className="text-xs text-gray-600 mt-1 font-mono">{kpi.sub}</div>
            </motion.div>
          ))}
        </div>

        {/* Line chart */}
        <ChartCard title="Incidents Per Day — 14 Day Trend" icon={TrendingUp}>
          <ResponsiveContainer width="100%" height={220}>
            <LineChart data={data.incidents_by_day} margin={{ top: 5, right: 20, left: -10, bottom: 0 }}>
              <CartesianGrid strokeDasharray="3 3" stroke="#1e1e1e" />
              <XAxis dataKey="date" tickFormatter={d => d.slice(5)} tick={{ fill: '#6b7280', fontSize: 10, fontFamily: 'JetBrains Mono' }} />
              <YAxis tick={{ fill: '#6b7280', fontSize: 10, fontFamily: 'JetBrains Mono' }} />
              <Tooltip {...tooltipStyle} labelFormatter={l => `Date: ${l}`} />
              <Line type="monotone" dataKey="count" stroke="#ef4444" strokeWidth={2}
                dot={{ fill: '#ef4444', strokeWidth: 0, r: 3 }}
                activeDot={{ r: 5, fill: '#ef4444', strokeWidth: 2, stroke: '#1a1a1a' }} />
            </LineChart>
          </ResponsiveContainer>
        </ChartCard>

        {/* Bar + Pie row */}
        <div className="grid grid-cols-2 gap-5">
          <ChartCard title="Incidents by Type" icon={BarChart2}>
            <ResponsiveContainer width="100%" height={220}>
              <BarChart data={data.incidents_by_type} margin={{ top: 5, right: 10, left: -15, bottom: 0 }}>
                <CartesianGrid strokeDasharray="3 3" stroke="#1e1e1e" vertical={false} />
                <XAxis dataKey="type" tick={{ fill: '#6b7280', fontSize: 10, fontFamily: 'JetBrains Mono' }} />
                <YAxis tick={{ fill: '#6b7280', fontSize: 10, fontFamily: 'JetBrains Mono' }} />
                <Tooltip {...tooltipStyle} />
                <Bar dataKey="count" radius={[4, 4, 0, 0]}>
                  {data.incidents_by_type.map((entry) => (
                    <Cell key={entry.type} fill={TYPE_COLORS[entry.type] || '#6b7280'} />
                  ))}
                </Bar>
              </BarChart>
            </ResponsiveContainer>
          </ChartCard>

          <ChartCard title="Incidents by Source" icon={PieIcon}>
            <ResponsiveContainer width="100%" height={220}>
              <PieChart>
                <Pie data={data.incidents_by_source} dataKey="count" nameKey="source"
                  cx="50%" cy="50%" innerRadius={55} outerRadius={85}
                  paddingAngle={3} strokeWidth={0}>
                  {data.incidents_by_source.map((entry, i) => (
                    <Cell key={entry.source} fill={SOURCE_COLORS[i % SOURCE_COLORS.length]} opacity={0.85} />
                  ))}
                </Pie>
                <Tooltip {...tooltipStyle} formatter={(val, name) => [val, name]} />
                <Legend iconType="circle" iconSize={8}
                  formatter={v => <span style={{ color: '#9ca3af', fontSize: '11px', fontFamily: 'JetBrains Mono' }}>{v}</span>} />
              </PieChart>
            </ResponsiveContainer>
          </ChartCard>
        </div>

        {/* Heatmap grid */}
        <ChartCard title="Temporal Crime Pattern — Hour × Day of Week" icon={Grid}>
          <p className="text-xs text-gray-600 font-mono mb-4">
            Incident frequency by hour of day and day of week — darker = more incidents
          </p>
          <HeatmapGrid data={data.hourly_heatmap} />
        </ChartCard>
      </div>
    </div>
  )
}
