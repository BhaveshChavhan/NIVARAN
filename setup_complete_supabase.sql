-- ====================================================================
-- 🛡️ NIVARAN Complete Supabase Database Setup
-- Run this in your Supabase SQL Editor:
-- https://supabase.com/dashboard/project/lffrcldhbesywswwjqnu/sql/new
-- ====================================================================

-- 1. Users Table
CREATE TABLE IF NOT EXISTS public.users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email TEXT UNIQUE NOT NULL,
  name TEXT,
  phone TEXT,
  id_number TEXT,
  gender TEXT DEFAULT 'female',
  password TEXT,
  is_verified BOOLEAN DEFAULT FALSE,
  kyc_hash TEXT,
  kyc_tx_hash TEXT,
  last_lat DOUBLE PRECISION,
  last_lng DOUBLE PRECISION,
  last_seen TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. Emergency Contacts Table
CREATE TABLE IF NOT EXISTS public.contacts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_email TEXT NOT NULL,
  name TEXT NOT NULL,
  phone TEXT NOT NULL,
  relation TEXT DEFAULT 'Family',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(user_email, phone)
);

-- 3. SOS Logs Table (Powers App SOS & Admin Dashboard)
CREATE TABLE IF NOT EXISTS public.sos_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_email TEXT NOT NULL,
  user_name TEXT,
  user_phone TEXT,
  type TEXT DEFAULT 'crime',
  emergency_type TEXT DEFAULT 'crime',
  status TEXT DEFAULT 'active',
  latitude DOUBLE PRECISION DEFAULT 0.0,
  longitude DOUBLE PRECISION DEFAULT 0.0,
  lat DOUBLE PRECISION DEFAULT 0.0,
  lng DOUBLE PRECISION DEFAULT 0.0,
  mesh_path TEXT[] DEFAULT '{}',
  notes TEXT,
  audio_url TEXT,
  blockchain_hash TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  resolved_at TIMESTAMPTZ
);

-- 4. Community Incidents Table
CREATE TABLE IF NOT EXISTS public.incidents (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID DEFAULT '00000000-0000-0000-0000-000000000000',
  title TEXT,
  type TEXT NOT NULL,
  severity INTEGER DEFAULT 2,
  source TEXT DEFAULT 'user_report',
  lat DOUBLE PRECISION NOT NULL,
  lng DOUBLE PRECISION NOT NULL,
  address TEXT,
  description TEXT,
  verified BOOLEAN DEFAULT FALSE,
  risk_score INTEGER DEFAULT 50,
  media_urls TEXT[] DEFAULT '{}',
  blockchain_tx TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 5. Admin Broadcasts Table (Powers Admin Dashboard Live Chat)
CREATE TABLE IF NOT EXISTS public.admin_broadcasts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_email TEXT NOT NULL,
  message TEXT NOT NULL,
  is_admin BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 6. Mesh Broadcasts Table
CREATE TABLE IF NOT EXISTS public.mesh_broadcasts (
  id TEXT PRIMARY KEY,
  sender_id TEXT,
  sender_name TEXT,
  payload TEXT,
  is_admin BOOLEAN DEFAULT FALSE,
  priority TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 7. FIR Reports Table
CREATE TABLE IF NOT EXISTS public.firs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_email TEXT NOT NULL,
  crime_type TEXT NOT NULL,
  date_time TEXT,
  location TEXT,
  incident_description TEXT,
  accused_description TEXT,
  witnesses TEXT,
  generated_fir TEXT,
  evidence_ids TEXT[] DEFAULT '{}',
  status TEXT DEFAULT 'pending',
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 8. Verified Identities Table
CREATE TABLE IF NOT EXISTS public.verified_identities (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  verifier_email TEXT NOT NULL,
  scanned_hash TEXT NOT NULL,
  verified_at TIMESTAMPTZ DEFAULT NOW()
);

-- ====================================================================
-- 🔓 Row Level Security & Public Access (Enable full read/write for app)
-- ====================================================================

DO $$
DECLARE
  t text;
BEGIN
  FOR t IN 
    SELECT tablename FROM pg_tables WHERE schemaname = 'public'
  LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY;', t);
    EXECUTE format('DROP POLICY IF EXISTS "Public Access" ON public.%I;', t);
    EXECUTE format('CREATE POLICY "Public Access" ON public.%I FOR ALL USING (true) WITH CHECK (true);', t);
  END LOOP;
END $$;

-- Enable Real-Time replication for live map & live chat
ALTER PUBLICATION supabase_realtime ADD TABLE public.sos_logs;
ALTER PUBLICATION supabase_realtime ADD TABLE public.admin_broadcasts;
ALTER PUBLICATION supabase_realtime ADD TABLE public.incidents;
ALTER PUBLICATION supabase_realtime ADD TABLE public.users;
