import { motion, AnimatePresence } from 'framer-motion'
import { useAppStore } from '../../store/useAppStore'
import { X, Wifi, Radio, Server } from 'lucide-react'

const NODES = [
  { id: 'Device_Alpha', x: 120, y: 280, label: 'Field Unit A', icon: Wifi },
  { id: 'Device_Beta', x: 320, y: 180, label: 'Relay Node B', icon: Wifi },
  { id: 'Node_Delta', x: 520, y: 240, label: 'Relay Node C', icon: Radio },
  { id: 'Gateway_Main', x: 700, y: 160, label: 'Gateway', icon: Server },
]

const PATHS = [
  { from: 0, to: 1 },
  { from: 1, to: 2 },
  { from: 2, to: 3 },
]

export function MeshRelayOverlay() {
  const { meshRelayVisible, setMeshRelayVisible } = useAppStore()

  return (
    <AnimatePresence>
      {meshRelayVisible && (
        <motion.div
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          exit={{ opacity: 0 }}
          className="absolute inset-0 z-[2000] flex items-center justify-center"
          style={{ background: 'rgba(0,0,0,0.7)', backdropFilter: 'blur(4px)' }}
          onClick={() => setMeshRelayVisible(false)}
        >
          <motion.div
            initial={{ scale: 0.9, opacity: 0 }}
            animate={{ scale: 1, opacity: 1 }}
            exit={{ scale: 0.9, opacity: 0 }}
            className="relative rounded-xl p-6 w-full max-w-3xl mx-4"
            style={{ background: '#141414', border: '1px solid #2a2a2a' }}
            onClick={e => e.stopPropagation()}
          >
            <div className="flex items-center justify-between mb-6">
              <div>
                <h3 className="font-display font-bold text-white text-lg">Mesh Relay Simulation</h3>
                <p className="text-sm text-gray-500 mt-0.5">SOS packet routing through distributed mesh network</p>
              </div>
              <button onClick={() => setMeshRelayVisible(false)} className="text-gray-600 hover:text-gray-400 transition-colors">
                <X size={20} />
              </button>
            </div>

            <svg viewBox="0 0 840 360" className="w-full" style={{ height: '240px' }}>
              {/* Background grid */}
              <defs>
                <pattern id="grid" width="40" height="40" patternUnits="userSpaceOnUse">
                  <path d="M 40 0 L 0 0 0 40" fill="none" stroke="#1e1e1e" strokeWidth="1" />
                </pattern>
              </defs>
              <rect width="840" height="360" fill="url(#grid)" />

              {/* Paths */}
              {PATHS.map((p, i) => {
                const from = NODES[p.from]
                const to = NODES[p.to]
                return (
                  <g key={i}>
                    {/* Base line */}
                    <line x1={from.x} y1={from.y} x2={to.x} y2={to.y}
                      stroke="#2a2a2a" strokeWidth="2" />
                    {/* Animated packet line */}
                    <motion.line
                      x1={from.x} y1={from.y} x2={to.x} y2={to.y}
                      stroke="#ef4444" strokeWidth="2"
                      strokeDasharray="12 8"
                      initial={{ pathLength: 0, opacity: 0 }}
                      animate={{ pathLength: 1, opacity: 1 }}
                      transition={{ delay: i * 0.6, duration: 0.8, ease: 'easeInOut', repeat: Infinity, repeatDelay: 1.5 }}
                    />
                    {/* Packet dot */}
                    <motion.circle r="5" fill="#ef4444"
                      initial={{ cx: from.x, cy: from.y, opacity: 0 }}
                      animate={{ cx: [from.x, to.x], cy: [from.y, to.y], opacity: [0, 1, 1, 0] }}
                      transition={{ delay: i * 0.6, duration: 0.8, repeat: Infinity, repeatDelay: 1.5 }}
                    />
                  </g>
                )
              })}

              {/* Nodes */}
              {NODES.map((node, i) => (
                <motion.g key={node.id}
                  initial={{ opacity: 0, scale: 0 }}
                  animate={{ opacity: 1, scale: 1 }}
                  transition={{ delay: i * 0.15, type: 'spring' }}
                >
                  {/* Pulse ring for active nodes */}
                  <motion.circle cx={node.x} cy={node.y} r="28"
                    fill="none" stroke={i === NODES.length - 1 ? '#22c55e' : '#ef4444'}
                    strokeWidth="1" opacity="0.4"
                    animate={{ r: [22, 38], opacity: [0.4, 0] }}
                    transition={{ duration: 1.5, repeat: Infinity, delay: i * 0.3 }}
                  />
                  <circle cx={node.x} cy={node.y} r="22"
                    fill="#1a1a1a" stroke={i === NODES.length - 1 ? '#22c55e' : '#ef4444'}
                    strokeWidth="1.5"
                  />
                  <text x={node.x} y={node.y + 5} textAnchor="middle"
                    fontSize="9" fill={i === NODES.length - 1 ? '#22c55e' : '#ef4444'}
                    fontFamily="JetBrains Mono">
                    {i + 1}
                  </text>
                  <text x={node.x} y={node.y + 42} textAnchor="middle"
                    fontSize="11" fill="#9ca3af" fontFamily="DM Sans">
                    {node.id}
                  </text>
                  <text x={node.x} y={node.y + 56} textAnchor="middle"
                    fontSize="9" fill="#4b5563" fontFamily="DM Sans">
                    {node.label}
                  </text>
                </motion.g>
              ))}

              {/* SOS label at source */}
              <motion.text x={NODES[0].x} y={NODES[0].y - 38}
                textAnchor="middle" fontSize="10" fill="#ef4444"
                fontFamily="JetBrains Mono" fontWeight="600"
                animate={{ opacity: [1, 0.3] }}
                transition={{ duration: 0.8, repeat: Infinity, repeatType: 'reverse' }}>
                ● SOS TRIGGERED
              </motion.text>

              {/* Success label at gateway */}
              <motion.text x={NODES[3].x} y={NODES[3].y - 38}
                textAnchor="middle" fontSize="10" fill="#22c55e"
                fontFamily="JetBrains Mono" fontWeight="600"
                initial={{ opacity: 0 }}
                animate={{ opacity: 1 }}
                transition={{ delay: 2 }}>
                ✓ GATEWAY RECEIVED
              </motion.text>
            </svg>

            {/* Stats row */}
            <div className="grid grid-cols-4 gap-3 mt-4">
              {[
                { label: 'Hops', value: '3' },
                { label: 'Latency', value: '~240ms' },
                { label: 'Signal', value: '-62 dBm' },
                { label: 'Protocol', value: 'LoRa 868' },
              ].map(s => (
                <div key={s.label} className="rounded-lg px-3 py-2 text-center" style={{ background: '#0f0f0f', border: '1px solid #1e1e1e' }}>
                  <div className="text-xs text-gray-600 font-mono">{s.label}</div>
                  <div className="text-sm font-mono text-white font-semibold mt-0.5">{s.value}</div>
                </div>
              ))}
            </div>
          </motion.div>
        </motion.div>
      )}
    </AnimatePresence>
  )
}
