import { useState, useEffect, useRef } from 'react'
import { useNavigate } from 'react-router-dom'
import { motion, AnimatePresence } from 'framer-motion'
import {
  Send, Shield, User, Search, Loader2, MessageSquare, MoreVertical,
  Paperclip, MapPin, ExternalLink, Clock, Radio, Megaphone, CheckCircle2, AlertCircle, Phone
} from 'lucide-react'
import { format, isToday, isYesterday } from 'date-fns'
import { supabase } from '../lib/supabase'
import { fetchUsersList } from '../lib/api'
import toast from 'react-hot-toast'

interface ChatMessage {
  id: string
  user_email: string
  message: string
  is_admin: boolean
  created_at: string
}

interface ChatThread {
  email: string
  name: string
  phone?: string
  lastLat?: number
  lastLng?: number
  lastSeen?: string
  lastMessage: string
  timestamp: string
  unreadCount: number
  messages: ChatMessage[]
}

export default function ChatPage() {
  const navigate = useNavigate()
  const [threads, setThreads] = useState<Record<string, ChatThread>>({})
  const [selectedUserEmail, setSelectedUserEmail] = useState<string | null>(null)
  const [searchQuery, setSearchQuery] = useState('')
  const [newMessage, setNewMessage] = useState('')
  const [isLoading, setIsLoading] = useState(true)
  const [isSending, setIsSending] = useState(false)
  const [isTracking, setIsTracking] = useState(false)
  const [isBroadcastModalOpen, setIsBroadcastModalOpen] = useState(false)
  const [broadcastText, setBroadcastText] = useState('')
  const [isBroadcasting, setIsBroadcasting] = useState(false)
  const messagesEndRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    loadAllUsersAndChats()

    // 1. Listen for new admin/user messages in realtime
    const chatChannel = supabase
      .channel('admin_broadcasts_live')
      .on(
        'postgres_changes',
        { event: 'INSERT', schema: 'public', table: 'admin_broadcasts' },
        (payload) => {
          handleIncomingMessage(payload.new as ChatMessage)
        }
      )
      .subscribe()

    // 2. Listen for new registered users or profile updates in realtime
    const usersChannel = supabase
      .channel('users_live')
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'users' },
        (payload) => {
          if (payload.eventType === 'INSERT' || payload.eventType === 'UPDATE') {
            const u = payload.new as any
            if (u.email) {
              setThreads((prev) => {
                const existing = prev[u.email]
                return {
                  ...prev,
                  [u.email]: {
                    email: u.email,
                    name: u.name || existing?.name || u.email.split('@')[0],
                    phone: u.phone || existing?.phone || '',
                    lastLat: u.last_lat ?? existing?.lastLat,
                    lastLng: u.last_lng ?? existing?.lastLng,
                    lastSeen: u.last_seen || existing?.lastSeen,
                    lastMessage: existing?.lastMessage || 'New user registered',
                    timestamp: existing?.timestamp || u.created_at || new Date().toISOString(),
                    unreadCount: existing?.unreadCount || 0,
                    messages: existing?.messages || [],
                  },
                }
              })
            }
          }
        }
      )
      .subscribe()

    return () => {
      supabase.removeChannel(chatChannel)
      supabase.removeChannel(usersChannel)
    }
  }, [])

  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' })
  }, [selectedUserEmail, threads])

  const loadAllUsersAndChats = async () => {
    try {
      setIsLoading(true)

      // Parallel fetch of all registered users + all broadcast messages
      const [users, { data: messages, error: msgError }] = await Promise.all([
        fetchUsersList(),
        supabase.from('admin_broadcasts').select('*').order('created_at', { ascending: true })
      ])

      if (msgError) {
        console.warn('admin_broadcasts load warning:', msgError.message)
      }

      const groupedThreads: Record<string, ChatThread> = {}

      // Step 1: Initialize thread for EVERY registered user in the database
      if (users && users.length > 0) {
        users.forEach((u: any) => {
          if (u.email) {
            groupedThreads[u.email] = {
              email: u.email,
              name: u.name || u.email.split('@')[0],
              phone: u.phone || '',
              lastLat: u.last_lat,
              lastLng: u.last_lng,
              lastSeen: u.last_seen || u.created_at,
              lastMessage: 'Tap to chat with user',
              timestamp: u.last_seen || u.created_at || new Date().toISOString(),
              unreadCount: 0,
              messages: [],
            }
          }
        })
      }

      // Step 2: Merge in all broadcast messages
      if (messages && messages.length > 0) {
        messages.forEach((msg: ChatMessage) => {
          if (!groupedThreads[msg.user_email]) {
            groupedThreads[msg.user_email] = {
              email: msg.user_email,
              name: msg.user_email.split('@')[0],
              lastMessage: msg.message,
              timestamp: msg.created_at,
              unreadCount: 0,
              messages: [],
            }
          }
          groupedThreads[msg.user_email].messages.push(msg)
          groupedThreads[msg.user_email].lastMessage = msg.message
          groupedThreads[msg.user_email].timestamp = msg.created_at
        })
      }

      setThreads(groupedThreads)

      // Auto-select first user if none selected
      const threadKeys = Object.keys(groupedThreads)
      if (threadKeys.length > 0 && !selectedUserEmail) {
        setSelectedUserEmail(threadKeys[0])
      }
    } catch (error: any) {
      toast.error('Failed to load chat users: ' + (error.message || ''))
      console.error('loadAllUsersAndChats error:', error)
    } finally {
      setIsLoading(false)
    }
  }

  const handleIncomingMessage = (msg: ChatMessage) => {
    setThreads((prev) => {
      const newThreads = { ...prev }
      if (!newThreads[msg.user_email]) {
        newThreads[msg.user_email] = {
          email: msg.user_email,
          name: msg.user_email.split('@')[0],
          lastMessage: msg.message,
          timestamp: msg.created_at,
          unreadCount: 0,
          messages: [],
        }
      }

      if (!newThreads[msg.user_email].messages.find(m => m.id === msg.id)) {
        newThreads[msg.user_email].messages = [...newThreads[msg.user_email].messages, msg]
        newThreads[msg.user_email].lastMessage = msg.message
        newThreads[msg.user_email].timestamp = msg.created_at

        if (selectedUserEmail !== msg.user_email && !msg.is_admin) {
          newThreads[msg.user_email].unreadCount++
        }
      }

      return newThreads
    })
  }

  const handleSend = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!newMessage.trim() || !selectedUserEmail) return

    const messageText = newMessage.trim()
    setNewMessage('')
    setIsSending(true)

    try {
      const { data, error } = await supabase.from('admin_broadcasts').insert({
        user_email: selectedUserEmail,
        message: messageText,
        is_admin: true,
        created_at: new Date().toISOString(),
      }).select().single()

      if (error) throw error

      if (data) {
        handleIncomingMessage(data as ChatMessage)
      }
    } catch (error: any) {
      toast.error('Failed to send message: ' + (error.message || ''))
      console.error(error)
      setNewMessage(messageText)
    } finally {
      setIsSending(false)
    }
  }

  const handleBroadcastToAll = async (e: React.FormEvent) => {
    e.preventDefault()
    const text = broadcastText.trim()
    if (!text) return

    const allEmails = Object.keys(threads)
    if (allEmails.length === 0) {
      toast.error('No users available to broadcast to')
      return
    }

    setIsBroadcasting(true)
    try {
      const records = allEmails.map((email) => ({
        user_email: email,
        message: `📢 [BROADCAST] ${text}`,
        is_admin: true,
        created_at: new Date().toISOString(),
      }))

      const { error } = await supabase.from('admin_broadcasts').insert(records)
      if (error) throw error

      toast.success(`Broadcast successfully sent to all ${allEmails.length} users!`, {
        icon: '📢',
        style: { background: '#141414', color: '#60a5fa', border: '1px solid #3b82f6' }
      })

      // Locally append to all threads
      setThreads(prev => {
        const next = { ...prev }
        allEmails.forEach(email => {
          if (next[email]) {
            const fakeMsg: ChatMessage = {
              id: 'bc_' + Date.now() + '_' + Math.random(),
              user_email: email,
              message: `📢 [BROADCAST] ${text}`,
              is_admin: true,
              created_at: new Date().toISOString(),
            }
            next[email] = {
              ...next[email],
              lastMessage: fakeMsg.message,
              timestamp: fakeMsg.created_at,
              messages: [...next[email].messages, fakeMsg],
            }
          }
        })
        return next
      })

      setBroadcastText('')
      setIsBroadcastModalOpen(false)
    } catch (err: any) {
      toast.error('Failed to send broadcast: ' + (err.message || ''))
    } finally {
      setIsBroadcasting(false)
    }
  }

  const handleTrackUser = async () => {
    if (!selectedUserEmail) return
    setIsTracking(true)
    try {
      const thread = threads[selectedUserEmail]
      if (thread?.lastLat && thread?.lastLng) {
        navigate(`/?track=${encodeURIComponent(selectedUserEmail)}&lat=${thread.lastLat}&lng=${thread.lastLng}&name=${encodeURIComponent(thread.name)}`)
        return
      }

      const { data, error } = await supabase
        .from('users')
        .select('last_lat, last_lng, name')
        .eq('email', selectedUserEmail)
        .maybeSingle()

      if (error) throw error
      if (!data?.last_lat || !data?.last_lng) {
        toast.error('No live GPS coordinates available for this user yet.')
        return
      }

      const name = data.name || selectedUserEmail.split('@')[0]
      navigate(`/?track=${encodeURIComponent(selectedUserEmail)}&lat=${data.last_lat}&lng=${data.last_lng}&name=${encodeURIComponent(name)}`)
    } catch (err) {
      toast.error('Failed to retrieve user location')
    } finally {
      setIsTracking(false)
    }
  }

  const formatMessageTime = (dateStr?: string) => {
    if (!dateStr) return ''
    try {
      const d = new Date(dateStr)
      if (isNaN(d.getTime())) return ''
      if (isToday(d)) return format(d, 'h:mm a')
      if (isYesterday(d)) return `Yesterday ${format(d, 'h:mm a')}`
      return format(d, 'MMM d, h:mm a')
    } catch {
      return ''
    }
  }

  const filteredThreads = Object.values(threads)
    .filter(t =>
      t.email.toLowerCase().includes(searchQuery.toLowerCase()) ||
      t.name.toLowerCase().includes(searchQuery.toLowerCase()) ||
      (t.phone && t.phone.includes(searchQuery))
    )
    .sort((a, b) => new Date(b.timestamp).getTime() - new Date(a.timestamp).getTime())

  const selectedThread = selectedUserEmail ? threads[selectedUserEmail] : null

  return (
    <div className="h-full flex flex-col p-6 max-w-[1600px] mx-auto overflow-hidden">
      {/* Header */}
      <div className="mb-6 flex justify-between items-center">
        <div>
          <div className="flex items-center gap-2">
            <h1 className="text-3xl font-display font-bold text-white tracking-tight">Broadcast & Support Chat</h1>
            <span className="px-2 py-0.5 rounded-full text-xs font-mono font-bold bg-blue-500/10 text-blue-400 border border-blue-500/20">
              {Object.keys(threads).length} USERS
            </span>
          </div>
          <p className="text-gray-400 mt-1">Direct bidirectional messaging with registered users & emergency broadcast dispatch.</p>
        </div>

        <button
          onClick={() => setIsBroadcastModalOpen(true)}
          className="flex items-center gap-2 px-4 py-2.5 rounded-xl font-semibold text-sm bg-gradient-to-r from-red-600 to-rose-600 hover:from-red-500 hover:to-rose-500 text-white shadow-lg shadow-red-900/30 transition-all hover:scale-[1.02]"
        >
          <Megaphone size={16} />
          Broadcast to All Users
        </button>
      </div>

      {/* Main Chat Container */}
      <div className="flex-1 flex overflow-hidden bg-[#141414] border border-[#1e1e1e] rounded-2xl shadow-2xl">
        {/* Sidebar (All Users) */}
        <div className="w-80 lg:w-96 border-r border-[#1e1e1e] flex flex-col bg-[#0f0f0f]">
          {/* Search Box */}
          <div className="p-4 border-b border-[#1e1e1e]">
            <div className="relative">
              <Search className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-500 w-4 h-4" />
              <input
                type="text"
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                placeholder="Search by name, email, or phone..."
                className="w-full bg-[#1a1a1a] border border-[#2a2a2a] rounded-xl pl-10 pr-4 py-2 text-sm text-white placeholder-gray-600 focus:outline-none focus:border-blue-500 transition-all"
              />
            </div>
            <div className="mt-2 flex items-center justify-between text-xs text-gray-500 font-mono">
              <span>All Registered App Users</span>
              <span className="text-blue-400 font-bold">{filteredThreads.length}</span>
            </div>
          </div>

          {/* User List */}
          <div className="flex-1 overflow-y-auto pt-2">
            {isLoading ? (
              <div className="flex flex-col items-center justify-center h-full gap-2 text-gray-500">
                <Loader2 className="w-6 h-6 text-blue-500 animate-spin" />
                <span className="text-xs font-mono">Loading all users...</span>
              </div>
            ) : filteredThreads.length === 0 ? (
              <div className="text-center py-10 px-4 text-gray-500">
                <MessageSquare className="w-8 h-8 mx-auto mb-2 opacity-20" />
                <p className="text-sm">No users matched search.</p>
              </div>
            ) : (
              filteredThreads.map((thread) => {
                const isSelected = selectedUserEmail === thread.email
                return (
                  <button
                    key={thread.email}
                    onClick={() => {
                      setSelectedUserEmail(thread.email)
                      setThreads(prev => ({
                        ...prev,
                        [thread.email]: { ...prev[thread.email], unreadCount: 0 }
                      }))
                    }}
                    className={`w-full flex items-center gap-3 p-3.5 transition-all border-l-2 text-left ${
                      isSelected
                        ? 'bg-blue-500/10 border-blue-500'
                        : 'hover:bg-white/5 border-transparent'
                    }`}
                  >
                    {/* User Avatar */}
                    <div className="relative shrink-0">
                      <div className="w-11 h-11 rounded-full bg-gradient-to-br from-blue-600 via-indigo-600 to-purple-700 flex items-center justify-center text-white font-bold text-base shadow-md">
                        {thread.name ? thread.name[0].toUpperCase() : thread.email[0].toUpperCase()}
                      </div>
                      <div className="absolute -bottom-0.5 -right-0.5 w-3 h-3 bg-green-500 border-2 border-[#0f0f0f] rounded-full" />
                    </div>

                    {/* User Details & Last Message */}
                    <div className="flex-1 min-w-0">
                      <div className="flex justify-between items-baseline mb-0.5">
                        <span className="text-sm font-semibold text-gray-100 truncate">
                          {thread.name || thread.email.split('@')[0]}
                        </span>
                        <span className="text-[10px] text-gray-500 font-mono shrink-0 ml-1">
                          {formatMessageTime(thread.timestamp)}
                        </span>
                      </div>
                      <div className="text-[11px] text-gray-400 font-mono truncate mb-1">
                        {thread.email}
                      </div>
                      <div className="flex items-center justify-between">
                        <p className={`text-xs truncate ${thread.unreadCount > 0 ? 'text-white font-semibold' : 'text-gray-500'}`}>
                          {thread.lastMessage}
                        </p>
                        {thread.unreadCount > 0 && (
                          <span className="bg-blue-600 text-[10px] font-bold text-white px-1.5 py-0.5 rounded-full min-w-[18px] text-center ml-2">
                            {thread.unreadCount}
                          </span>
                        )}
                      </div>
                    </div>
                  </button>
                )
              })
            )}
          </div>
        </div>

        {/* Chat Area */}
        <div className="flex-1 flex flex-col bg-[#141414] relative">
          {!selectedUserEmail ? (
            <div className="flex-1 flex flex-col items-center justify-center text-gray-600 p-8 text-center">
              <div className="p-4 rounded-full bg-white/5 mb-4">
                <MessageSquare className="w-12 h-12 opacity-30 text-blue-400" />
              </div>
              <h3 className="text-lg font-bold text-white mb-1">Select a User to Chat</h3>
              <p className="text-sm text-gray-500 max-w-sm">
                Choose any user from the sidebar to send support messages, urgent warnings, or view live location tracking.
              </p>
            </div>
          ) : (
            <>
              {/* Chat Header */}
              <div className="p-4 border-b border-[#1e1e1e] flex justify-between items-center bg-[#141414]/90 backdrop-blur-md sticky top-0 z-10">
                <div className="flex items-center gap-3">
                  <div className="w-10 h-10 rounded-full bg-blue-600/20 text-blue-400 flex items-center justify-center font-bold text-lg relative border border-blue-500/30">
                    {selectedThread?.name ? selectedThread.name[0].toUpperCase() : selectedUserEmail[0].toUpperCase()}
                    <div className="absolute bottom-0 right-0 w-2.5 h-2.5 bg-green-500 border-2 border-[#141414] rounded-full" />
                  </div>
                  <div>
                    <div className="flex items-center gap-2">
                      <h2 className="text-sm font-bold text-white">
                        {selectedThread?.name || selectedUserEmail.split('@')[0]}
                      </h2>
                      <span className="text-[10px] font-mono px-1.5 py-0.5 rounded bg-white/5 text-gray-400">
                        {selectedUserEmail}
                      </span>
                    </div>
                    <div className="flex items-center gap-3 mt-0.5">
                      {selectedThread?.phone && (
                        <span className="text-[11px] text-gray-500 font-mono flex items-center gap-1">
                          <Phone size={10} className="text-gray-400" /> {selectedThread.phone}
                        </span>
                      )}
                      <button
                        onClick={handleTrackUser}
                        disabled={isTracking}
                        className="flex items-center gap-1 text-[11px] text-blue-400 hover:text-blue-300 font-semibold transition-colors disabled:opacity-50"
                      >
                        {isTracking ? <Loader2 size={11} className="animate-spin" /> : <MapPin size={11} />}
                        View on Map
                      </button>
                    </div>
                  </div>
                </div>

                <div className="flex items-center gap-2">
                  <button
                    onClick={handleTrackUser}
                    className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-semibold bg-blue-600/10 text-blue-400 border border-blue-500/30 hover:bg-blue-600/20 transition-all"
                  >
                    <MapPin size={13} />
                    Locate on Live Map
                  </button>
                </div>
              </div>

              {/* Messages Feed */}
              <div className="flex-1 overflow-y-auto p-6 space-y-4">
                {selectedThread?.messages.length === 0 ? (
                  <div className="text-center py-16 text-gray-500">
                    <MessageSquare size={32} className="mx-auto mb-3 opacity-20 text-blue-400" />
                    <p className="text-sm font-semibold text-gray-400">No previous messages with {selectedThread.name || selectedUserEmail}</p>
                    <p className="text-xs text-gray-600 mt-1">Type below to start the conversation or send instructions.</p>
                  </div>
                ) : (
                  selectedThread?.messages.map((msg) => {
                    const isMe = msg.is_admin
                    return (
                      <motion.div
                        key={msg.id}
                        initial={{ opacity: 0, scale: 0.95, y: 10 }}
                        animate={{ opacity: 1, scale: 1, y: 0 }}
                        transition={{ duration: 0.2 }}
                        className={`flex ${isMe ? 'justify-end' : 'justify-start'}`}
                      >
                        <div className={`max-w-[75%] ${isMe ? 'flex flex-row-reverse' : 'flex flex-row'} items-end gap-2`}>
                          <div
                            className={`px-4 py-3 rounded-2xl text-sm leading-relaxed shadow-sm ${
                              isMe
                                ? 'bg-blue-600 text-white rounded-br-none shadow-blue-950/40'
                                : 'bg-[#1e1e1e] text-gray-200 rounded-bl-none border border-[#2a2a2a]'
                            }`}
                          >
                            {/* Sender badge */}
                            <div className={`text-[10px] font-bold uppercase tracking-wider mb-1 flex items-center gap-1 ${isMe ? 'text-blue-200' : 'text-gray-400'}`}>
                              {isMe ? (
                                <>
                                  <Shield size={10} /> SafeNet Admin Support
                                </>
                              ) : (
                                <>
                                  <User size={10} /> {selectedThread?.name || 'User'}
                                </>
                              )}
                            </div>

                            <div className="whitespace-pre-wrap">{msg.message}</div>

                            <div className={`text-[9px] mt-1.5 font-mono flex items-center justify-end gap-1 ${isMe ? 'text-blue-200' : 'text-gray-500'}`}>
                              <Clock size={8} />
                              {formatMessageTime(msg.created_at)}
                            </div>
                          </div>
                        </div>
                      </motion.div>
                    )
                  })
                )}
                <div ref={messagesEndRef} />
              </div>

              {/* Message Input */}
              <div className="p-4 bg-[#0f0f0f] border-t border-[#1e1e1e]">
                <form onSubmit={handleSend} className="flex items-center gap-3">
                  <div className="flex-1 relative">
                    <input
                      type="text"
                      value={newMessage}
                      onChange={(e) => setNewMessage(e.target.value)}
                      placeholder={`Send message to ${selectedThread?.name || selectedUserEmail}...`}
                      className="w-full bg-[#1a1a1a] border border-[#2a2a2a] rounded-xl px-5 py-3 text-white placeholder-gray-600 focus:outline-none focus:border-blue-600 focus:ring-1 focus:ring-blue-600/20 transition-all text-sm"
                      disabled={isSending}
                    />
                  </div>
                  <button
                    type="submit"
                    disabled={!newMessage.trim() || isSending}
                    className="p-3 bg-blue-600 text-white rounded-xl font-bold hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed transition-all shadow-lg shadow-blue-900/20 flex items-center justify-center min-w-[50px]"
                  >
                    {isSending ? <Loader2 size={20} className="animate-spin" /> : <Send size={20} />}
                  </button>
                </form>
              </div>
            </>
          )}
        </div>
      </div>

      {/* ── Broadcast to All Users Modal ──────────────────────────────────────── */}
      <AnimatePresence>
        {isBroadcastModalOpen && (
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            className="fixed inset-0 z-[2000] flex items-center justify-center p-4 bg-black/75 backdrop-blur-sm"
            onClick={() => setIsBroadcastModalOpen(false)}
          >
            <motion.div
              initial={{ scale: 0.95, opacity: 0 }}
              animate={{ scale: 1, opacity: 1 }}
              exit={{ scale: 0.95, opacity: 0 }}
              onClick={(e) => e.stopPropagation()}
              className="bg-[#141414] border border-[#2a2a2a] rounded-2xl p-6 w-full max-w-lg shadow-2xl text-left"
            >
              <div className="flex items-center gap-3 mb-4">
                <div className="w-10 h-10 rounded-full bg-red-500/20 text-red-500 flex items-center justify-center">
                  <Megaphone size={20} />
                </div>
                <div>
                  <h3 className="text-lg font-bold text-white">Broadcast Alert to All Users</h3>
                  <p className="text-xs text-gray-400">Sends an instant push warning to all {Object.keys(threads).length} registered users.</p>
                </div>
              </div>

              <form onSubmit={handleBroadcastToAll}>
                <div className="mb-4">
                  <label className="block text-xs font-semibold text-gray-300 uppercase mb-2">
                    Announcement Message
                  </label>
                  <textarea
                    rows={4}
                    value={broadcastText}
                    onChange={(e) => setBroadcastText(e.target.value)}
                    placeholder="e.g. Warning: Heavy flooding reported near Godavari riverfront. Please avoid the area and use designated safe corridors."
                    className="w-full bg-[#1a1a1a] border border-[#2a2a2a] rounded-xl p-3 text-sm text-white placeholder-gray-600 focus:outline-none focus:border-red-500 transition-all resize-none"
                    required
                  />
                </div>

                <div className="flex items-center justify-end gap-3">
                  <button
                    type="button"
                    onClick={() => setIsBroadcastModalOpen(false)}
                    className="px-4 py-2 rounded-xl text-sm font-medium text-gray-400 hover:text-white transition-colors"
                  >
                    Cancel
                  </button>
                  <button
                    type="submit"
                    disabled={!broadcastText.trim() || isBroadcasting}
                    className="flex items-center gap-2 px-5 py-2.5 rounded-xl text-sm font-bold bg-red-600 hover:bg-red-500 text-white disabled:opacity-50 transition-all shadow-lg shadow-red-900/30"
                  >
                    {isBroadcasting ? <Loader2 size={16} className="animate-spin" /> : <Megaphone size={16} />}
                    Send to All Users
                  </button>
                </div>
              </form>
            </motion.div>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  )
}
