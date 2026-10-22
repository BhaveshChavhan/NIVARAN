import { useState, useEffect } from 'react'
import { motion } from 'framer-motion'
import { 
  Users, Mail, Phone, Clock, Hash, UserCircle, 
  ShieldCheck, ShieldAlert, MapPin,
  Search, Filter
} from 'lucide-react'
import { fetchUsersList } from '../lib/api'

interface AppUser {
  id?: string
  name?: string
  phone?: string
  email?: string
  id_number?: string
  is_verified?: boolean
  gender?: string
  last_seen?: string
  created_at?: string
}

export default function UsersPage() {
  const [users, setUsers] = useState<AppUser[]>([])
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState('')

  useEffect(() => {
    const fetchUsers = async () => {
      try {
        const usersData = await fetchUsersList()
        setUsers(usersData)
      } catch (err) {
        console.error('Failed to fetch users:', err)
      } finally {
        setLoading(false)
      }
    }
    fetchUsers()
  }, [])

  const filteredUsers = users.filter(u => 
    u.name?.toLowerCase().includes(search.toLowerCase()) ||
    u.email?.toLowerCase().includes(search.toLowerCase()) ||
    u.phone?.includes(search)
  )

  const truncateId = (id: string) => id ? `${id.slice(0, 8)}...${id.slice(-6)}` : 'N/A'

  return (
    <div className="h-full overflow-y-auto" style={{ background: '#0f0f0f' }}>
      <div className="p-6 max-w-[1200px] mx-auto space-y-6">
        {/* Header */}
        <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
          <div>
            <h1 className="text-2xl font-display font-bold text-white flex items-center gap-3">
              <div className="flex items-center justify-center w-10 h-10 rounded-xl" style={{ background: 'rgba(99,102,241,0.12)' }}>
                <Users size={20} className="text-indigo-400" />
              </div>
              Registered Users
            </h1>
            <p className="text-sm text-gray-500 mt-1 font-body">
              Monitor user accounts and verification status.
            </p>
          </div>
          
          <div className="flex items-center gap-3">
            <div className="relative group">
              <Search size={16} className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-500 group-focus-within:text-indigo-400 transition-colors" />
              <input 
                type="text"
                placeholder="Search users..."
                value={search}
                onChange={e => setSearch(e.target.value)}
                className="bg-[#141414] border border-[#1e1e1e] rounded-lg pl-10 pr-4 py-2 text-sm text-white focus:outline-none focus:border-indigo-500/50 w-full md:w-64 transition-all"
              />
            </div>
            
            <div className="flex items-center gap-2 px-4 py-2 rounded-lg" style={{ background: '#141414', border: '1px solid #1e1e1e' }}>
              <div className="text-xs text-gray-400">Total</div>
              <div className="text-lg font-bold text-indigo-400">{users.length}</div>
            </div>
          </div>
        </div>

        {/* Users List */}
        {loading ? (
          <div className="flex justify-center py-20">
            <div className="w-8 h-8 border-2 border-indigo-500 rounded-full border-t-transparent animate-spin"></div>
          </div>
        ) : filteredUsers.length === 0 ? (
          <div className="text-center py-20 text-gray-500 font-medium bg-[#141414] rounded-2xl border border-[#1e1e1e]">
            {search ? 'No users matching your search.' : 'No users found.'}
          </div>
        ) : (
          <div className="grid gap-3">
            {filteredUsers.map((user, i) => (
              <motion.div
                key={user.id || i}
                initial={{ opacity: 0, y: 10 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ delay: i * 0.03 }}
                className="group flex flex-col md:flex-row md:items-center p-4 rounded-xl gap-4 transition-all hover:bg-[#1a1a1a]"
                style={{ background: '#141414', border: '1px solid #1e1e1e' }}
              >
                {/* Avatar & Basic Info */}
                <div className="flex items-center gap-4 min-w-[240px]">
                  <div className="relative">
                    <div className="w-12 h-12 rounded-full flex items-center justify-center shrink-0 overflow-hidden" style={{ background: 'rgba(255,255,255,0.03)' }}>
                      <UserCircle size={32} className="text-gray-500" />
                    </div>
                    {user.is_verified && (
                      <div className="absolute -bottom-1 -right-1 bg-green-500 rounded-full p-0.5 border-2 border-[#141414]">
                        <ShieldCheck size={10} className="text-white" />
                      </div>
                    )}
                  </div>
                  
                  <div className="min-w-0">
                    <div className="flex items-center gap-2">
                      <span className="text-sm font-semibold text-white truncate">
                        {user.name || 'Anonymous User'}
                      </span>
                      {user.gender && (
                        <span className={`text-[10px] px-1.5 py-0.5 rounded-full font-bold uppercase ${
                          user.gender === 'female' ? 'bg-pink-500/10 text-pink-400' : 'bg-blue-500/10 text-blue-400'
                        }`}>
                          {user.gender}
                        </span>
                      )}
                    </div>
                    <div className="flex items-center gap-1.5 text-xs text-gray-500 mt-0.5">
                      <Hash size={10} />
                      <span className="font-mono text-[10px] uppercase tracking-tighter">
                        {user.id_number || truncateId(user.id || '')}
                      </span>
                    </div>
                  </div>
                </div>

                {/* Contact Info */}
                <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 flex-1 gap-4">
                  <div className="flex items-center gap-2.5 text-sm text-gray-400 group-hover:text-gray-300 transition-colors">
                    <div className="p-1.5 rounded-lg bg-white/5">
                      <Mail size={14} className="text-indigo-400/70" />
                    </div>
                    <span className="truncate">{user.email || 'N/A'}</span>
                  </div>

                  <div className="flex items-center gap-2.5 text-sm text-gray-400 group-hover:text-gray-300 transition-colors">
                    <div className="p-1.5 rounded-lg bg-white/5">
                      <Phone size={14} className="text-emerald-400/70" />
                    </div>
                    <span>{user.phone || 'N/A'}</span>
                  </div>

                  <div className="hidden lg:flex items-center gap-2.5 text-sm text-gray-400 group-hover:text-gray-300 transition-colors">
                    <div className="p-1.5 rounded-lg bg-white/5">
                      <MapPin size={14} className="text-red-400/70" />
                    </div>
                    <span className="text-xs truncate">
                      {user.last_seen ? `Last seen: ${new Date(user.last_seen).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}` : 'Location unknown'}
                    </span>
                  </div>
                </div>

                {/* Meta / Status */}
                <div className="pt-3 md:pt-0 md:pl-4 border-t md:border-t-0 md:border-l border-[#1e1e1e] flex flex-row md:flex-col justify-between items-center md:items-end gap-1 min-w-[120px]">
                   <div className="flex items-center gap-1.5 text-[10px] text-gray-500 font-mono">
                    <Clock size={10} />
                    {user.created_at ? new Date(user.created_at).toLocaleDateString() : 'New User'}
                  </div>
                  
                  <div className={`px-2 py-0.5 rounded-full text-[10px] font-bold tracking-widest uppercase ${
                    user.is_verified 
                    ? 'bg-green-500/10 text-green-400 border border-green-500/20' 
                    : 'bg-yellow-500/10 text-yellow-500 border border-yellow-500/20'
                  }`}>
                    {user.is_verified ? 'Verified' : 'Pending'}
                  </div>
                </div>
              </motion.div>
            ))}
          </div>
        )}
      </div>
    </div>
  )
}
