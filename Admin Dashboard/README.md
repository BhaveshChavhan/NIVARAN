# SafeNet — AI Predictive Safety Alert System

Admin dashboard for the SafeNet hackathon demo. Built with Vite + React 18 + TypeScript, Tailwind CSS dark theme, Leaflet.js heatmaps, Supabase realtime, Recharts analytics.

---

## Quick Start

### 1. Install dependencies

```bash
cd safenet-dashboard
npm install
```

### 2. Configure environment

```bash
cp .env.example .env
```

Edit `.env`:

```env
VITE_API_URL=http://localhost:8000        # Your FastAPI/Express backend
VITE_SUPABASE_URL=https://xxx.supabase.co
VITE_SUPABASE_ANON_KEY=your-anon-key
```

> **Demo mode**: If the API is unreachable, all pages fall back to rich mock data automatically. No backend required for the demo.

### 3. Run dev server

```bash
npm run dev
```

Open [http://localhost:5173](http://localhost:5173)

---

## Login

| Field    | Value                  |
|----------|------------------------|
| Email    | `admin@safenet.com`    |
| Password | `demo1234`             |

---

## Pages

| Route        | Description                                      |
|--------------|--------------------------------------------------|
| `/`          | **Live Map** — heatmap, SOS markers, stats panel |
| `/incidents` | Filterable incidents table with AI summaries     |
| `/analytics` | Charts: line, bar, pie + temporal heatmap grid   |
| `/sos`       | SOS alerts feed with mesh relay path display     |

---

## Demo Features (For Judges)

### 🔴 Simulate SOS (Money Shot)
1. Go to **Live Map**
2. Click **"Simulate SOS"** (top-right red button)
3. Within ~400ms a **pulsing red marker** appears on the map
4. A **toast notification** fires top-right: "SOS ALERT RECEIVED"
5. The sidebar counter increments live

### 🔵 Mesh Relay Simulation
1. Click **"Mesh Relay"** (blue button, toolbar)
2. Animated SVG shows a SOS packet hopping: `Device_Alpha → Device_Beta → Node_Delta → Gateway_Main`
3. Animated packet dots travel along each edge with latency stats

### 📡 Supabase Realtime
- Subscribe to `sos_alerts` Postgres channel
- When a new row is inserted in Supabase, the marker appears instantly without refresh
- Toast fires automatically

---

## Architecture

```
src/
├── components/
│   ├── Layout.tsx               # Sidebar nav
│   └── map/
│       ├── SOSMarker.tsx        # Pulsing red markers + popups
│       ├── HeatmapLayer.tsx     # leaflet.heat integration
│       └── MeshRelayOverlay.tsx # Animated mesh diagram
├── lib/
│   ├── api.ts                   # Axios + mock fallback
│   └── supabase.ts              # Supabase client
├── pages/
│   ├── AuthPage.tsx
│   ├── LiveMapPage.tsx          # ← Most important
│   ├── IncidentsPage.tsx
│   ├── AnalyticsPage.tsx
│   └── SOSAlertsPage.tsx
├── store/
│   └── useAppStore.ts           # Zustand global state
└── types/
    └── index.ts                 # Shared TypeScript types
```

---

## Supabase Setup (Optional for Full Realtime)

Create table in Supabase SQL editor:

```sql
create table sos_alerts (
  id text primary key,
  user_name text not null,
  lat float8 not null,
  lng float8 not null,
  emergency_type text not null,
  status text default 'active',
  mesh_path text[] default '{}',
  created_at timestamptz default now(),
  resolved_at timestamptz
);

-- Enable realtime
alter publication supabase_realtime add table sos_alerts;
```

---

## Backend API Contract (Optional)

The dashboard calls these endpoints (falls back to mocks if unavailable):

```
GET  /incidents/heatmap?radius_km=20   → HeatmapPoint[]
GET  /incidents                        → Incident[]
GET  /sos                              → SOSAlert[]
POST /sos/trigger                      → SOSAlert
PATCH /incidents/:id                   → Incident
GET  /ai/zone-summary?zone_id=:id      → { summary: string }
GET  /analytics                        → AnalyticsData
GET  /stats                            → DashboardStats
```

---

## Build for Production

```bash
npm run build
npm run preview
```

---

## Tech Stack

| Library         | Version | Use                              |
|-----------------|---------|----------------------------------|
| React           | 18.2    | UI framework                     |
| TypeScript      | 5.3     | Type safety                      |
| Vite            | 5.0     | Build tool                       |
| Tailwind CSS    | 3.4     | Dark theme styling               |
| react-leaflet   | 4.2     | Interactive map                  |
| leaflet.heat    | 0.2     | Density heatmap layer            |
| @supabase/js    | 2.39    | Realtime SOS subscriptions       |
| Recharts        | 2.10    | Analytics charts                 |
| Framer Motion   | 11.0    | Animations                       |
| Zustand         | 4.4     | Global state                     |
| react-hot-toast | 2.4     | SOS toast notifications          |
| date-fns        | 3.2     | Date formatting                  |
| axios           | 1.6     | HTTP client                      |
| lucide-react    | 0.312   | Icons                            |
