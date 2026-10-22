import { useState, useEffect } from 'react'
import { motion } from 'framer-motion'
import {
  Brain, TrendingUp, AlertTriangle, MapPin, Clock,
  Target, Zap, BarChart2, Activity, ArrowUp, ArrowDown
} from 'lucide-react'
import { api } from '../lib/api'

interface Forecast {
  step: number
  predicted: number
  lower_bound: number
  upper_bound: number
  confidence: number
}

interface Anomaly {
  index: number
  value: number
  z_score: number
  severity: string
}

interface MLHealth {
  ml_connected: boolean
  xgb_ready?: boolean
  bert_ready?: boolean
  trust_ready?: boolean
}

export default function MLPredictionsPage() {
  const [forecasts] = useState<Forecast[]>([])
  const [anomalies] = useState<Anomaly[]>([])
  const [predLat, setPredLat] = useState('19.9975')
  const [predLng, setPredLng] = useState('73.7898')
  const [predHour, setPredHour] = useState(new Date().getHours().toString())
  const [loading, setLoading] = useState(false)
  const [mlHealth, setMlHealth] = useState<MLHealth>({ ml_connected: false })
  const [riskResult, setRiskResult] = useState<null | { risk_score: number; risk_label: string; dominant_type: string; factors: string[]; recommendations: string[] }>(null)

  // Check ML service health on mount
  useEffect(() => {
    api.get('/api/ml/health')
      .then(res => setMlHealth(res.data))
      .catch(() => setMlHealth({ ml_connected: false }))
  }, [])

  const avgPredicted = forecasts.length ? forecasts.reduce((s, f) => s + f.predicted, 0) / forecasts.length : 0
  const peakHour = forecasts.length ? forecasts.reduce((p, f) => f.predicted > p.predicted ? f : p, forecasts[0]) : null
  const maxForecast = forecasts.length ? Math.max(...forecasts.map(f => f.upper_bound)) : 1

  const predictRisk = async () => {
    setLoading(true)
    try {
      const { data } = await api.post('/api/zones/predict', {
        locations: [{ latitude: parseFloat(predLat), longitude: parseFloat(predLng) }],
        time_of_day_hour: parseInt(predHour),
        day_of_week: new Date().getDay(),
        is_weekend: new Date().getDay() >= 5 ? 1 : 0,
      })

      if (data.predictions && data.predictions.length > 0) {
        const pred = data.predictions[0]
        const score = Math.round((pred.risk_score || 0) * 100)
        const label = pred.risk_label || 'unknown'
        const probs = pred.probabilities || {}

        setRiskResult({
          risk_score: score,
          risk_label: label,
          dominant_type: label === 'red' ? 'High Crime Zone' : label === 'orange' ? 'Moderate Risk' : 'Safe Zone',
          factors: [
            `ML Risk Label: ${label.toUpperCase()}`,
            `Green probability: ${((probs.green || 0) * 100).toFixed(1)}%`,
            `Orange probability: ${((probs.orange || 0) * 100).toFixed(1)}%`,
            `Red probability: ${((probs.red || 0) * 100).toFixed(1)}%`,
            data.success ? 'Source: ML Model (XGBoost)' : 'Source: Fallback (ML service offline)',
          ],
          recommendations: label === 'red'
            ? ['Avoid this area after dark', 'Use buddy tracking', 'Share live location with contacts']
            : label === 'orange'
            ? ['Stay alert and aware', 'Prefer well-lit routes', 'Keep emergency contacts accessible']
            : ['Area appears safe', 'Standard precautions recommended'],
        })
      }
    } catch (err: any) {
      setRiskResult({
        risk_score: 0,
        risk_label: 'unknown',
        dominant_type: 'Error',
        factors: [`API Error: ${err.message}`],
        recommendations: ['Ensure backend is running on port 3000', 'Check ML service on port 8000'],
      })
    } finally {
      setLoading(false)
    }
  }

  const severityColor = (s: string) =>
    s === 'critical' ? '#ef4444' : s === 'high' ? '#f59e0b' : '#6366f1'

  return (
    <div className="h-full overflow-y-auto" style={{ background: '#0f0f0f' }}>
      <div className="p-6 max-w-[1600px] mx-auto space-y-6">
        {/* Header */}
        <div className="flex items-center justify-between">
          <div>
            <h1 className="text-xl font-display font-bold text-white flex items-center gap-3">
              <div className="flex items-center justify-center w-10 h-10 rounded-xl" style={{ background: 'rgba(59,130,246,0.12)' }}>
                <Brain size={20} className="text-blue-400" />
              </div>
              ML Predictions
            </h1>
            <p className="text-sm text-gray-500 mt-1 font-body">
              Crime forecasting • Spatial risk estimation • Anomaly detection
            </p>
          </div>
          <div className="flex items-center gap-2 px-3 py-1.5 rounded-lg text-xs font-mono"
            style={{ background: 'rgba(16,185,129,0.1)', color: '#10b981', border: '1px solid rgba(16,185,129,0.2)' }}>
            <Zap size={12} /> 3 Models Active
          </div>
        </div>

        {/* Stats */}
        <div className="grid grid-cols-4 gap-3">
          {[
            { label: 'Avg Predicted/hr', value: avgPredicted.toFixed(1), icon: BarChart2, color: '#6366f1' },
            { label: 'Peak Hour', value: peakHour ? `${(new Date().getHours() + peakHour.step) % 24}:00` : 'N/A', icon: Clock, color: '#ef4444' },
            { label: 'Anomalies Detected', value: anomalies.length, icon: AlertTriangle, color: '#f59e0b' },
            { label: 'Forecast Horizon', value: '48h', icon: TrendingUp, color: '#3b82f6' },
          ].map((s, i) => (
            <motion.div
              key={s.label}
              initial={{ opacity: 0, y: 20 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ delay: i * 0.05 }}
              className="rounded-xl p-4"
              style={{ background: '#141414', border: '1px solid #1e1e1e' }}
            >
              <div className="flex items-center justify-between mb-2">
                <s.icon size={16} style={{ color: s.color }} />
                <span className="text-2xl font-display font-bold text-white">{s.value}</span>
              </div>
              <p className="text-xs text-gray-500">{s.label}</p>
            </motion.div>
          ))}
        </div>

        <div className="grid grid-cols-5 gap-4">
          {/* Forecast Chart - Left 3 cols */}
          <div className="col-span-3 space-y-4">
            <h2 className="text-sm font-display font-semibold text-gray-400 uppercase tracking-wider">
              48-Hour Incident Forecast
            </h2>
            <div className="rounded-xl p-5" style={{ background: '#141414', border: '1px solid #1e1e1e' }}>
              {/* Simple bar chart visualization */}
              <div className="flex items-end gap-0.5 h-40 mb-3">
                {forecasts.map((f, i) => {
                  const height = (f.predicted / maxForecast) * 100
                  const hour = (new Date().getHours() + f.step) % 24
                  const isNight = hour >= 22 || hour < 5
                  return (
                    <div
                      key={i}
                      className="flex-1 rounded-t-sm transition-all hover:opacity-80 cursor-pointer group relative"
                      style={{
                        height: `${height}%`,
                        background: isNight
                          ? 'linear-gradient(to top, rgba(239,68,68,0.6), rgba(239,68,68,0.2))'
                          : 'linear-gradient(to top, rgba(99,102,241,0.6), rgba(99,102,241,0.2))',
                        minHeight: '2px',
                      }}
                      title={`Hour +${f.step} (${hour}:00): ${f.predicted} incidents`}
                    />
                  )
                })}
              </div>
              <div className="flex items-center justify-between text-[10px] text-gray-600">
                <span>Now</span>
                <span>+12h</span>
                <span>+24h</span>
                <span>+36h</span>
                <span>+48h</span>
              </div>
              <div className="flex items-center gap-4 mt-3 text-[10px] text-gray-500">
                <span className="flex items-center gap-1">
                  <div className="w-2 h-2 rounded-full" style={{ background: '#6366f1' }} /> Daytime
                </span>
                <span className="flex items-center gap-1">
                  <div className="w-2 h-2 rounded-full" style={{ background: '#ef4444' }} /> Night (High Risk)
                </span>
              </div>
            </div>

            {/* Anomalies */}
            <h2 className="text-sm font-display font-semibold text-gray-400 uppercase tracking-wider">
              Detected Anomalies
            </h2>
            <div className="space-y-2">
              {anomalies.map((a, i) => (
                <motion.div
                  key={i}
                  initial={{ opacity: 0, x: -10 }}
                  animate={{ opacity: 1, x: 0 }}
                  transition={{ delay: i * 0.05 }}
                  className="rounded-xl p-4 flex items-center gap-4"
                  style={{ background: '#141414', border: '1px solid #1e1e1e' }}
                >
                  <div className="w-2 h-10 rounded-full" style={{ background: severityColor(a.severity) }} />
                  <div className="flex-1">
                    <div className="flex items-center gap-2 mb-1">
                      <AlertTriangle size={14} style={{ color: severityColor(a.severity) }} />
                      <span className="text-sm text-white font-medium capitalize">{a.severity} Anomaly</span>
                      <span className="px-2 py-0.5 rounded-full text-[10px] font-mono"
                        style={{ background: `${severityColor(a.severity)}20`, color: severityColor(a.severity) }}>
                        z = {a.z_score.toFixed(1)}
                      </span>
                    </div>
                    <div className="text-xs text-gray-500">
                      Incident count spike: {a.value.toFixed(1)} incidents/hr (expected: ~3.5)
                    </div>
                  </div>
                  <Activity size={16} style={{ color: severityColor(a.severity) }} />
                </motion.div>
              ))}
            </div>
          </div>

          {/* Risk Predictor - Right 2 cols */}
          <div className="col-span-2 space-y-4">
            <h2 className="text-sm font-display font-semibold text-gray-400 uppercase tracking-wider">
              Spatial Risk Predictor
            </h2>
            <div className="rounded-xl p-5 space-y-4" style={{ background: '#141414', border: '1px solid #1e1e1e' }}>
              <div className="space-y-3">
                <div>
                  <label className="text-[10px] text-gray-600 uppercase tracking-wider mb-1 block">Latitude</label>
                  <input type="text" value={predLat} onChange={e => setPredLat(e.target.value)}
                    className="w-full px-3 py-2 rounded-lg text-sm font-mono text-white"
                    style={{ background: '#1a1a1a', border: '1px solid #252525', outline: 'none' }} />
                </div>
                <div>
                  <label className="text-[10px] text-gray-600 uppercase tracking-wider mb-1 block">Longitude</label>
                  <input type="text" value={predLng} onChange={e => setPredLng(e.target.value)}
                    className="w-full px-3 py-2 rounded-lg text-sm font-mono text-white"
                    style={{ background: '#1a1a1a', border: '1px solid #252525', outline: 'none' }} />
                </div>
                <div>
                  <label className="text-[10px] text-gray-600 uppercase tracking-wider mb-1 block">Hour (0-23)</label>
                  <input type="number" value={predHour} onChange={e => setPredHour(e.target.value)}
                    min={0} max={23}
                    className="w-full px-3 py-2 rounded-lg text-sm font-mono text-white"
                    style={{ background: '#1a1a1a', border: '1px solid #252525', outline: 'none' }} />
                </div>
                <button onClick={predictRisk} disabled={loading}
                  className="w-full py-2.5 rounded-xl text-sm font-medium transition-all hover:opacity-90 disabled:opacity-50"
                  style={{ background: 'linear-gradient(135deg, #3b82f6, #6366f1)', color: 'white' }}>
                  <Target size={14} className="inline mr-2" />
                  {loading ? 'Predicting...' : 'Predict Risk Score'}
                </button>
              </div>

              {/* Result */}
              {riskResult && (
                <motion.div
                  initial={{ opacity: 0, y: 10 }}
                  animate={{ opacity: 1, y: 0 }}
                  className="space-y-3 pt-3 border-t border-gray-800"
                >
                  <div className="flex items-center justify-between">
                    <span className="text-sm text-gray-400">Risk Score</span>
                    <span className="text-3xl font-display font-bold" style={{
                      color: riskResult.risk_score > 60 ? '#ef4444' : riskResult.risk_score > 35 ? '#f59e0b' : '#10b981'
                    }}>
                      {riskResult.risk_score}
                    </span>
                  </div>
                  <div className="w-full h-2 rounded-full bg-gray-800 overflow-hidden">
                    <div className="h-full rounded-full transition-all" style={{
                      width: `${riskResult.risk_score}%`,
                      background: riskResult.risk_score > 60 ? '#ef4444' : riskResult.risk_score > 35 ? '#f59e0b' : '#10b981',
                    }} />
                  </div>
                  <div className="p-3 rounded-lg" style={{ background: '#1a1a1a' }}>
                    <div className="text-[10px] text-gray-600 uppercase tracking-wider mb-2">Risk Factors</div>
                    {riskResult.factors.map((f, i) => (
                      <div key={i} className="flex items-center gap-2 text-xs text-gray-400 mb-1">
                        <div className="w-1 h-1 rounded-full bg-gray-600" />
                        {f}
                      </div>
                    ))}
                  </div>
                  <div className="p-3 rounded-lg" style={{ background: '#1a1a1a' }}>
                    <div className="text-[10px] text-gray-600 uppercase tracking-wider mb-2">Recommendations</div>
                    {riskResult.recommendations.map((r, i) => (
                      <div key={i} className="flex items-center gap-2 text-xs text-blue-400 mb-1">
                        <Target size={10} />
                        {r}
                      </div>
                    ))}
                  </div>
                </motion.div>
              )}
            </div>

            {/* Model Status */}
            <div className="rounded-xl p-4" style={{ background: '#141414', border: '1px solid #1e1e1e' }}>
              <div className="text-xs font-medium text-gray-400 mb-3">Model Status</div>
              {[
                { name: 'XGBoost Zone Predictor', status: mlHealth.xgb_ready ? 'Active' : 'Offline', type: 'Red Zone' },
                { name: 'BERT Report Verifier', status: mlHealth.bert_ready ? 'Active' : 'Offline', type: 'NLP' },
                { name: 'Trust Scorer (RF)', status: mlHealth.trust_ready ? 'Active' : 'Offline', type: 'Metadata' },
              ].map((m, i) => (
                <div key={m.name} className="flex items-center justify-between py-2 border-b border-gray-800/50 last:border-0">
                  <div>
                    <div className="text-xs text-white">{m.name}</div>
                    <div className="text-[10px] text-gray-600">{m.type}</div>
                  </div>
                  <span className={`flex items-center gap-1 text-[10px] ${m.status === 'Active' ? 'text-green-400' : 'text-red-400'}`}>
                    <div className={`w-1.5 h-1.5 rounded-full ${m.status === 'Active' ? 'bg-green-500' : 'bg-red-500'}`} />
                    {m.status}
                  </span>
                </div>
              ))}
              <div className="mt-2 pt-2 border-t border-gray-800/50 flex items-center gap-1 text-[10px]">
                <div className={`w-1.5 h-1.5 rounded-full ${mlHealth.ml_connected ? 'bg-green-500' : 'bg-red-500'}`} />
                <span className={mlHealth.ml_connected ? 'text-green-400' : 'text-red-400'}>
                  ML Service: {mlHealth.ml_connected ? 'Connected' : 'Disconnected'}
                </span>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}
