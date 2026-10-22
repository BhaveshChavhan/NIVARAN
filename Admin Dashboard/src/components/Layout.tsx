import { Outlet, NavLink, useNavigate } from 'react-router-dom'
import { motion } from 'framer-motion'
import { useAppStore } from '../store/useAppStore'
import {
  MapPin, AlertTriangle, BarChart2, Radio,
  Shield, LogOut, Activity, Wifi, Database, Building,
  Users, Brain
} from 'lucide-react'

const NAV = [
  { to: '/', icon: MapPin, label: 'Live Map', exact: true },
  { to: '/incidents', icon: AlertTriangle, label: 'Incidents' },
  { to: '/analytics', icon: BarChart2, label: 'Analytics' },
  { to: '/sos', icon: Radio, label: 'SOS Alerts' },
  { to: '/data-ingestion', icon: Database, label: 'Data Ingestion' },
  { to: '/authority', icon: Building, label: 'Authority Portal' },
  { to: '/users', icon: Users, label: 'Users' },
  { to: '/ml-predictions', icon: Brain, label: 'ML Predictions' },
  { to: '/chat', icon: Radio, label: 'Broadcast Chat' },
]

export default function Layout() {
  const { setAuthenticated, stats } = useAppStore()
  const navigate = useNavigate()

  return (
    <div className="flex h-screen w-full overflow-hidden" style={{ background: '#0f0f0f' }}>
      {/* Sidebar */}
      <motion.aside
        initial={{ x: -240 }}
        animate={{ x: 0 }}
        transition={{ type: 'spring', stiffness: 260, damping: 30 }}
        className="flex flex-col w-60 shrink-0 border-r"
        style={{ background: '#0f0f0f', borderColor: '#1e1e1e' }}
      >
        {/* Logo */}
        <div className="flex items-center gap-3 px-5 py-5 border-b" style={{ borderColor: '#1e1e1e' }}>
          <div className="relative flex items-center justify-center w-9 h-9 rounded-lg" style={{ background: 'rgba(239,68,68,0.12)' }}>
            <Shield size={18} className="text-red-500" />
            <span className="absolute -top-1 -right-1 w-2 h-2 bg-red-500 rounded-full animate-pulse" />
          </div>
          <div>
            <div className="font-display font-bold text-white text-sm tracking-wide">SafeNet</div>
            <div className="text-xs" style={{ color: '#4b5563', fontFamily: 'JetBrains Mono' }}>v2.4.1 • LIVE</div>
          </div>
        </div>

        {/* Nav */}
        <nav className="flex-1 py-4 px-3 space-y-0.5">
          {NAV.map(({ to, icon: Icon, label, exact }) => (
            <NavLink
              key={to}
              to={to}
              end={exact}
              className={({ isActive }) =>
                `nav-item flex items-center gap-3 px-3 py-2.5 rounded-md text-sm cursor-pointer ${isActive ? 'nav-active' : 'text-gray-500'}`
              }
            >
              <Icon size={16} />
              <span className="font-body font-medium">{label}</span>
            </NavLink>
          ))}
        </nav>

        {/* Live indicators */}
        <div className="px-4 py-3 mx-3 mb-3 rounded-lg space-y-2" style={{ background: '#141414', border: '1px solid #1e1e1e' }}>
          <div className="text-xs font-mono text-gray-600 uppercase tracking-wider mb-2">System Status</div>
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2 text-xs text-gray-400">
              <Activity size={11} className="text-green-500" />
              API
            </div>
            <span className="text-xs font-mono text-green-400">ONLINE</span>
          </div>
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2 text-xs text-gray-400">
              <Wifi size={11} className="text-blue-400" />
              Mesh Nodes
            </div>
            <span className="text-xs font-mono text-blue-400">{stats.mesh_nodes_active}</span>
          </div>
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2 text-xs text-gray-400">
              <Radio size={11} className="text-red-500" />
              Active SOS
            </div>
            <span className="text-xs font-mono text-red-400">{stats.active_sos}</span>
          </div>
        </div>

        {/* Logout */}
        <div className="px-3 pb-4">
          <button
            onClick={() => { setAuthenticated(false); navigate('/auth') }}
            className="nav-item flex items-center gap-3 px-3 py-2.5 rounded-md text-sm text-gray-600 w-full hover:text-gray-400"
          >
            <LogOut size={15} />
            <span>Sign Out</span>
          </button>
        </div>
      </motion.aside>

      {/* Main content */}
      <main className="flex-1 overflow-hidden">
        <Outlet />
      </main>
    </div>
  )
}
