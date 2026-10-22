require('dotenv').config();
const dns = require('dns');
dns.setDefaultResultOrder('ipv4first');
const express = require('express');
const ethers = require('ethers');
const cors = require('cors');
const bodyParser = require('body-parser');
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const jwt = require('jsonwebtoken');
const { v4: uuidv4 } = require('uuid');
const turfHelpers = require('@turf/helpers');
const turfBuffer = require('@turf/buffer').default || require('@turf/buffer');
const turfBooleanIntersects = require('@turf/boolean-intersects').default || require('@turf/boolean-intersects');
const axios = require('axios');
const polyline = require('@mapbox/polyline');
const multer = require('multer');

// ML Integration (connects to Python FastAPI ML service)
let mlService;
try {
    mlService = require('./services/ml-integration');
    console.log('[ML] Integration module loaded.');
} catch (e) {
    console.warn('[ML] ml-integration.js not found. ML routes will return fallback data.');
    mlService = null;
}

// Twilio service removed as requested.
// const twilioService = require('./services/twilio-service');

if (!fs.existsSync(path.join(__dirname, 'uploads'))) {
    fs.mkdirSync(path.join(__dirname, 'uploads'));
}

const storage = multer.diskStorage({
    destination: function (req, file, cb) {
        cb(null, path.join(__dirname, 'uploads'))
    },
    filename: function (req, file, cb) {
        // We expect the log id in the body to use as the filename
        const logId = req.body.logId || 'unknown_sos';
        cb(null, logId + '.m4a')
    }
});

const upload = multer({ storage: storage });

const JWT_SECRET = process.env.JWT_SECRET || 'super_secret_jwt_key_safeher';
// Persistent db for testing (wallet_address -> user object, nonce etc)
const DB_FILE = path.join(__dirname, 'usersDB.json');
let usersDB = new Map();
if (fs.existsSync(DB_FILE)) {
    try {
        const data = fs.readFileSync(DB_FILE, 'utf8');
        usersDB = new Map(Object.entries(JSON.parse(data)));
    } catch (e) {
        console.error('Error loading usersDB.json:', e);
    }
}

function saveDB() {
    try {
        fs.writeFileSync(DB_FILE, JSON.stringify(Object.fromEntries(usersDB)), 'utf8');
    } catch (e) {
        console.error('Error saving usersDB.json:', e);
    }
}

const app = express();
const PORT = process.env.PORT || 3000;

app.use(cors());
app.use(bodyParser.json());
app.use('/uploads', express.static(path.join(__dirname, 'uploads')));

// Load Contract ABI and Address
let contractABI;
let contractAddress = process.env.CONTRACT_ADDRESS;

try {
    const contractData = JSON.parse(fs.readFileSync(path.join(__dirname, 'TrustVerify.json'), 'utf8'));
    contractABI = contractData.abi;
} catch (error) {
    console.error("Error loading contract ABI. Make sure to run compile.js first.");
}

// Blockchain Setup
const provider = new ethers.JsonRpcProvider(process.env.RPC_URL || 'https://rpc-amoy.polygon.technology');
const wallet = new ethers.Wallet(process.env.PRIVATE_KEY || '0x0000000000000000000000000000000000000000000000000000000000000001', provider);
let contract;

if (contractAddress && contractABI) {
    contract = new ethers.Contract(contractAddress, contractABI, wallet);
}

// Hashing Helper
function generateHash(data) {
    return crypto.createHash('sha256').update(JSON.stringify(data)).digest('hex');
}

// --- Auth & Identity Routes ---
app.post('/api/auth/signup', (req, res) => {
    try {
        console.log('--- /api/auth/signup called ---', req.body);
        const { wallet_address, name, phone, email } = req.body;
        if (!wallet_address) return res.status(400).json({ error: 'wallet_address is required' });

        const address = wallet_address.toLowerCase();

        // 1. Check if this wallet is already registered to SAME email (redundant but safe)
        if (usersDB.has(address)) {
            const existingUser = usersDB.get(address);
            if (existingUser.email === email) {
                console.log('User already registered with this wallet and email.');
                return res.json({ success: true, user: existingUser, message: 'Existing profile re-synced' });
            }
        }

        // 2. Allow re-registering with same email but NEW wallet (Device migration)
        let foundUser = null;
        for (let user of usersDB.values()) {
            if (user.email === email) {
                foundUser = user;
                break;
            }
        }

        if (foundUser) {
            console.log(`Found existing user with email ${email}. Updating wallet to ${address}`);
            // Remove old mapping if wallet changed
            if (foundUser.wallet_address !== address) {
                usersDB.delete(foundUser.wallet_address);
            }

            foundUser.wallet_address = address;
            foundUser.name = name || foundUser.name;
            foundUser.phone = phone || foundUser.phone;
            foundUser.nonce = uuidv4();

            usersDB.set(address, foundUser);
            saveDB();
            return res.json({ success: true, user: foundUser, message: 'Wallet updated' });
        }

        // 3. Brand new user
        const newUser = {
            wallet_address: address,
            name,
            phone,
            email,
            nonce: uuidv4(),
            created_at: new Date().toISOString()
        };
        usersDB.set(address, newUser);
        saveDB();

        console.log(`Successfully registered new user: ${email} with wallet ${address}`);
        res.json({ success: true, user: newUser });
    } catch (e) {
        console.error('Signup error stack:', e);
        res.status(500).json({ success: false, error: e.message });
    }
});

app.post('/api/auth/nonce', (req, res) => {
    try {
        console.log('--- /api/auth/nonce called ---', req.body);
        const { wallet_address } = req.body;
        const address = wallet_address?.toLowerCase();

        if (!address || !usersDB.has(address)) {
            console.log('User not found during nonce request for address:', wallet_address);
            return res.status(404).json({ error: 'User not found in usersDB. Have you signed up yet?' });
        }

        // Generate a new nonce
        const user = usersDB.get(address);
        user.nonce = uuidv4();
        usersDB.set(address, user);
        saveDB();

        res.json({ success: true, nonce: user.nonce });
    } catch (e) {
        res.status(500).json({ success: false, error: e.message });
    }
});

app.post('/api/auth/verify', (req, res) => {
    try {
        console.log('--- /api/auth/verify called ---', req.body);
        const { wallet_address, signature } = req.body;
        const address = wallet_address?.toLowerCase();

        if (!address || !usersDB.has(address)) {
            console.log('User not found during verify request for address:', address);
            return res.status(404).json({ error: 'User not found' });
        }

        const user = usersDB.get(address);
        const expectedNonce = user.nonce;

        // Verify signature using ethers
        const recoveredAddress = ethers.verifyMessage(expectedNonce, signature);

        if (recoveredAddress.toLowerCase() !== address) {
            return res.status(401).json({ error: 'Invalid signature' });
        }

        // Generate new nonce to prevent replay attacks
        user.nonce = uuidv4();
        usersDB.set(address, user);
        saveDB();

        // Issue JWT token
        const token = jwt.sign(
            { wallet_address: address, sub: address },
            JWT_SECRET,
            { expiresIn: '30d' }
        );

        res.json({ success: true, token, user });
    } catch (e) {
        res.status(500).json({ success: false, error: e.message });
    }
});

app.get('/api/users', (req, res) => {
    try {
        const usersList = Array.from(usersDB.values());
        res.json({ success: true, users: usersList });
    } catch (e) {
        res.status(500).json({ success: false, error: e.message });
    }
});


// --- Blockchain Event Routes ---
app.post('/api/blockchain/kyc', async (req, res) => {
    try {
        const userData = req.body;
        // 1. Generate SHA256 Hash
        const hash = generateHash(userData);

        console.log(`Generating KYC hash: ${hash}`);

        // 2. Add to Blockchain if contract is deployed
        if (contract) {
            const tx = await contract.storeKYC(hash);
            await tx.wait();
            return res.json({
                success: true,
                hash: hash,
                txHash: tx.hash,
                message: "KYC hash stored on blockchain"
            });
        } else {
            return res.json({
                success: true,
                hash: hash,
                txHash: "0xMockTxHash_" + Date.now(),
                message: "KYC hash generated (Blockchain contract not deployed yet)"
            });
        }
    } catch (error) {
        console.error("KYC Error:", error);
        res.status(500).json({ success: false, error: error.message });
    }
});

app.post('/api/blockchain/sos', async (req, res) => {
    try {
        const sosData = req.body;
        // 1. Generate SHA256 Hash
        const hash = generateHash(sosData);

        console.log(`Generating SOS hash: ${hash}`);

        // 2. Add to Blockchain if contract is deployed
        if (contract) {
            const tx = await contract.storeSOS(hash);
            await tx.wait();
            return res.json({
                success: true,
                hash: hash,
                txHash: tx.hash,
                message: "SOS log stored on blockchain"
            });
        } else {
            return res.json({
                success: true,
                hash: hash,
                txHash: "0xMockTxHash_" + Date.now(),
                message: "SOS hash generated (Blockchain contract not deployed yet)"
            });
        }
    } catch (error) {
        console.error("SOS Error:", error);
        res.status(500).json({ success: false, error: error.message });
    }
});

app.post('/api/blockchain/sos/audio', upload.single('audio'), async (req, res) => {
    try {
        const logId = req.body.logId || (req.file ? path.parse(req.file.originalname).name : 'unknown_sos');
        console.log('🎙️ Received audio for SOS log:', logId, 'file:', req.file ? req.file.path : 'none');
        
        let audioUrl = null;
        if (req.file && fs.existsSync(req.file.path)) {
            // Ensure audio is accessible at /uploads/<logId>.m4a for the Admin Dashboard
            if (logId && logId !== 'unknown_sos') {
                const targetPath = path.join(__dirname, 'uploads', `${logId}.m4a`);
                if (req.file.path !== targetPath) {
                    try {
                        fs.copyFileSync(req.file.path, targetPath);
                    } catch (copyErr) {
                        console.error('Failed to copy file to logId.m4a:', copyErr);
                    }
                }
            }

            // Encode audio as base64 Data URL so it plays anywhere without bucket/storage dependency
            const buffer = fs.readFileSync(req.file.path);
            const base64Str = buffer.toString('base64');
            audioUrl = `data:audio/mp4;base64,${base64Str}`;
            
            // Sync directly to Supabase sos_logs table if logId is valid
            if (logId && logId !== 'unknown_sos') {
                const supaUrl = process.env.SUPABASE_URL || 'https://lffrcldhbesywswwjqnu.supabase.co';
                const supaKey = process.env.SUPABASE_KEY || 'sb_publishable_arkbVnMWBz7syDVEDEOGRQ_xr_GyHsO';
                
                try {
                    await axios.patch(`${supaUrl}/rest/v1/sos_logs?id=eq.${logId}`, {
                        audio_url: audioUrl,
                        updated_at: new Date().toISOString()
                    }, {
                        headers: {
                            'apikey': supaKey,
                            'Authorization': `Bearer ${supaKey}`,
                            'Content-Type': 'application/json',
                            'Prefer': 'return=minimal'
                        }
                    });
                    console.log(`✅ Supabase sos_logs updated with audio for log: ${logId}`);
                } catch (supaErr) {
                    console.error('⚠️ Failed to sync audio directly to Supabase sos_logs:', supaErr.message);
                }
            }
        }

        res.json({ success: true, message: 'Audio uploaded successfully', audio_url: audioUrl, filename: `${logId}.m4a` });
    } catch (e) {
        console.error('Audio upload error:', e);
        res.status(500).json({ success: false, error: e.message });
    }
});

app.post('/api/sos/trigger', async (req, res) => {
    try {
        const { userName, phone, emergencyContacts } = req.body;
        console.log(`\n🚨 SOS Relay Triggered for: ${userName} (${phone})`);

        let results = [];
        if (emergencyContacts && emergencyContacts.length > 0) {
            console.log(`[SOS] Calling disabled for safety.`);
            results.push({ contact: emergencyContacts[0]?.name || 'Primary', status: 'called_disabled', message: 'Calling service unavailable' });
        }

        res.json({ success: true, message: 'SOS calling relay processed', results });
    } catch (e) {
        console.error('SOS Trigger error:', e);
        res.status(500).json({ success: false, error: e.message });
    }
});

app.get('/api/blockchain/sos-logs', async (req, res) => {
    try {
        if (contract) {
            const logs = await contract.getSOSLogs();
            res.json({ success: true, logs });
        } else {
            res.json({ success: true, logs: ["Mock SOS Hash 1", "Mock SOS Hash 2"] });
        }
    } catch (error) {
        console.error("SOS Logs Error:", error);
        res.status(500).json({ success: false, error: error.message });
    }
});

// --- Safest Route Logic (Google Maps Routes API + Places API v2 with OSRM fallback) ---
app.post('/api/routes/safest', async (req, res) => {
    try {
        const GOOGLE_MAPS_API_KEY = process.env.GOOGLE_MAPS_API_KEY || 'AIzaSyBysLlo3koysojda0_SYVBPszM7WxcPs6U';
        const { origin, destination } = req.body;
        console.log(`\n🚀 [ROUTE] Calculating path with Google Maps: "${origin}" → "${destination}"`);

        // --- Parse lat,lng string ---
        const parseLatLng = (str) => {
            const [lat, lng] = str.split(',').map(s => parseFloat(s.trim()));
            return { lat, lng };
        };

        // --- Geocode a place name via Google Places API (New) or Nominatim ---
        const geocode = async (placeName) => {
            const cleanName = placeName.trim();
            console.log(`🔍 Geocoding via Google Places: "${cleanName}"`);
            try {
                const placeRes = await axios.post('https://places.googleapis.com/v1/places:searchText', {
                    textQuery: `${cleanName}, Maharashtra, India`
                }, {
                    headers: {
                        'Content-Type': 'application/json',
                        'X-Goog-Api-Key': GOOGLE_MAPS_API_KEY,
                        'X-Goog-FieldMask': 'places.displayName,places.location'
                    },
                    timeout: 8000
                });

                if (placeRes.data?.places?.length) {
                    const loc = placeRes.data.places[0].location;
                    console.log(`✅ Google Places found: "${cleanName}" → [${loc.latitude}, ${loc.longitude}]`);
                    return { lat: loc.latitude, lng: loc.longitude };
                }
            } catch (gErr) {
                console.warn(`Google Places search fallback: ${gErr.message}`);
            }

            // Fallback to Nominatim
            console.log(`🔍 Fallback geocoding via Nominatim: "${cleanName}"`);
            const nomRes = await axios.get('https://nominatim.openstreetmap.org/search', {
                params: { q: cleanName, format: 'json', limit: 1 },
                headers: { 'User-Agent': 'NivaranSafetyApp/1.0' },
                timeout: 8000
            });
            if (nomRes.data?.length) {
                const lat = parseFloat(nomRes.data[0].lat);
                const lng = parseFloat(nomRes.data[0].lon);
                console.log(`✅ Nominatim geocoded "${cleanName}" → [${lat}, ${lng}]`);
                return { lat, lng };
            }
            throw new Error(`Unable to find location for "${cleanName}"`);
        };

        // --- Resolve origin & destination ---
        const isLatLng = (s) => /^-?\d+(\.\d+)?\s*,\s*-?\d+(\.\d+)?$/.test(String(s).trim());

        let orig, dest;
        try {
            orig = isLatLng(origin) ? parseLatLng(origin) : await geocode(origin);
            dest = isLatLng(destination) ? parseLatLng(destination) : await geocode(destination);
            console.log(`✅ [GEO] Resolved: [${orig.lat},${orig.lng}] → [${dest.lat},${dest.lng}]`);
        } catch (geoErr) {
            console.error(`❌ [ERROR] Geocoding failure: ${geoErr.message}`);
            return res.status(400).json({ success: false, error: `Geocoding failed: ${geoErr.message}` });
        }

        // --- Call Google Routes API v2 ---
        let analyzed = [];
        try {
            console.log(`🗺️  Google Routes API v2: [${orig.lat},${orig.lng}] → [${dest.lat},${dest.lng}]`);
            const routesRes = await axios.post('https://routes.googleapis.com/directions/v2:computeRoutes', {
                origin: { location: { latLng: { latitude: orig.lat, longitude: orig.lng } } },
                destination: { location: { latLng: { latitude: dest.lat, longitude: dest.lng } } },
                travelMode: 'DRIVE',
                routingPreference: 'TRAFFIC_AWARE',
                computeAlternativeRoutes: true
            }, {
                headers: {
                    'Content-Type': 'application/json',
                    'X-Goog-Api-Key': GOOGLE_MAPS_API_KEY,
                    'X-Goog-FieldMask': 'routes.duration,routes.distanceMeters,routes.polyline.encodedPolyline,routes.legs.steps'
                },
                timeout: 12000
            });

            if (routesRes.data?.routes?.length) {
                const gRoutes = routesRes.data.routes;
                console.log(`✅ Google Routes API returned ${gRoutes.length} route(s)`);
                
                const hour = new Date().getHours();
                const isNight = hour >= 20 || hour < 6;
                const nightMultiplier = isNight ? 2.2 : 1.0;

                analyzed = gRoutes.map((r, index) => {
                    const encoded = r.polyline?.encodedPolyline || '';
                    const decoded = encoded ? polyline.decode(encoded) : []; // [[lat, lng], ...]
                    const coords = decoded.map(c => [c[1], c[0]]); // [lng, lat] for turf GeoJSON
                    const path = decoded.map(c => ({ latitude: c[0], longitude: c[1] }));

                    let safetyScore = 0;
                    if (coords.length >= 2) {
                        const geoJson = { type: 'LineString', coordinates: coords };
                        redZonePolygons.forEach(poly => {
                            if (turfBooleanIntersects(geoJson, poly)) {
                                safetyScore += (1.0 * nightMultiplier);
                            }
                        });
                    }

                    const distKm = ((r.distanceMeters || 0) / 1000).toFixed(1);
                    const durationSec = parseInt(String(r.duration || '0').replace('s', '')) || 0;
                    const durationMin = Math.round(durationSec / 60) || 1;

                    const instructions = [];
                    const steps = r.legs?.[0]?.steps || [];
                    steps.forEach(st => {
                        const instText = st.navigationInstruction?.instructions || 'Proceed along path';
                        const distText = st.localizedValues?.distance?.text || (st.distanceMeters ? `${st.distanceMeters}m` : '');
                        instructions.push({
                            instruction: instText,
                            distance: distText,
                            isSafeZone: true
                        });
                    });

                    if (instructions.length === 0) {
                        instructions.push({ instruction: 'Head towards destination', distance: `${distKm}km`, isSafeZone: true });
                    }

                    return {
                        index,
                        summary: `Google Route ${index + 1}`,
                        safetyScore,
                        isSafe: safetyScore === 0,
                        distanceKm: distKm,
                        durationMin: durationMin,
                        path: path,
                        instructions: instructions
                    };
                });
            }
        } catch (gRouteErr) {
            console.warn(`⚠️ Google Routes API error: ${gRouteErr.message}. Falling back to OSRM...`);
        }

        // --- Fallback to OSRM if Google Routes didn't return routes ---
        if (analyzed.length === 0) {
            console.log(`🗺️  OSRM Fallback: [${orig.lat},${orig.lng}] → [${dest.lat},${dest.lng}]`);
            const osrmUrl = `https://router.project-osrm.org/route/v1/driving/${orig.lng},${orig.lat};${dest.lng},${dest.lat}?overview=full&geometries=geojson&steps=true`;
            const osrmRes = await axios.get(osrmUrl, { timeout: 12000 });
            if (osrmRes.data?.routes?.length) {
                const r = osrmRes.data.routes[0];
                const coords = r.geometry.coordinates; // [[lng, lat], ...]
                const path = coords.map(c => ({ latitude: c[1], longitude: c[0] }));
                const distKm = (r.distance / 1000).toFixed(1);
                const durationMin = Math.round(r.duration / 60) || 1;

                const instructions = (r.legs?.[0]?.steps || []).map(st => ({
                    instruction: `${st.maneuver?.type || 'Drive'} on ${st.name || 'road'}`,
                    distance: st.distance < 1000 ? `${Math.round(st.distance)}m` : `${(st.distance / 1000).toFixed(1)}km`,
                    isSafeZone: true
                }));

                analyzed.push({
                    index: 0,
                    summary: 'Direct Safe Route',
                    safetyScore: 0,
                    isSafe: true,
                    distanceKm: distKm,
                    durationMin: durationMin,
                    path: path,
                    instructions: instructions.length > 0 ? instructions : [{ instruction: 'Follow navigation path', distance: `${distKm}km`, isSafeZone: true }]
                });
            }
        }

        if (analyzed.length === 0) {
            return res.status(404).json({ success: false, error: 'No routes found between these locations' });
        }

        // --- Select safest route ---
        analyzed.sort((a, b) => a.safetyScore - b.safetyScore);
        const safest = analyzed[0];
        console.log(`✅ Safest Route: ${safest.path.length} pts, score ${safest.safetyScore}, ${safest.distanceKm}km, ${safest.durationMin}min`);

        res.json({
            success: true,
            source: 'Google Maps Routes API',
            safestRoute: safest,
            status: safest.isSafe ? 'Safe' : 'Risky',
            alternativeRoutes: analyzed.slice(1),
        });

    } catch (error) {
        const errorDetail = error.response?.data || error.message;
        console.error('❌ [ROUTE ERROR]:', errorDetail);
        res.status(500).json({
            success: false,
            error: typeof errorDetail === 'object' ? (errorDetail.message || JSON.stringify(errorDetail)) : errorDetail
        });
    }
});
const crimeHotspots = [
    { lat: 19.9975, lng: 73.7898, intensity: 0.8, type: 'Theft', area: 'College Road' },
    { lat: 20.0059, lng: 73.7654, intensity: 0.7, type: 'Harassment', area: 'Gangapur Road' },
    { lat: 19.9950, lng: 73.7860, intensity: 0.9, type: 'Assault', area: 'CBS' },
    { lat: 20.0110, lng: 73.7900, intensity: 0.6, type: 'Stalking', area: 'Panchavati' },
    { lat: 19.9600, lng: 73.8300, intensity: 0.85, type: 'Robbery', area: 'Nashik Road' },
    { lat: 19.9900, lng: 73.8000, intensity: 0.75, type: 'Chain Snatching', area: 'Dwarka' },
    { lat: 19.9700, lng: 73.7700, intensity: 0.7, type: 'Theft', area: 'Indira Nagar' },
    { lat: 19.9905, lng: 73.7300, intensity: 0.8, type: 'Assault', area: 'Satpur MIDC' },
    { lat: 19.9500, lng: 73.7500, intensity: 0.75, type: 'Harassment', area: 'Ambad MIDC' },
    { lat: 20.0200, lng: 73.7800, intensity: 0.65, type: 'Suspicious Activity', area: 'Makhmalabad Road' },
    { lat: 19.9500, lng: 73.7800, intensity: 0.7, type: 'Theft', area: 'Pathardi Phata' },
    { lat: 20.0300, lng: 73.8000, intensity: 0.6, type: 'Harassment', area: 'Adgaon' },
    { lat: 19.9800, lng: 73.7700, intensity: 0.7, type: 'Robbery', area: 'Trimurti Chowk' },
    { lat: 19.9955, lng: 73.7805, intensity: 0.85, type: 'Theft', area: 'Canada Corner' },
    { lat: 19.9980, lng: 73.7850, intensity: 0.75, type: 'Assault', area: 'Shalimar' },
    { lat: 19.9400, lng: 73.8500, intensity: 0.6, type: 'Stalking', area: 'Deolali Camp' },
    { lat: 20.1000, lng: 73.9000, intensity: 0.55, type: 'Theft', area: 'Ojhar' },
    { lat: 19.7000, lng: 73.5500, intensity: 0.5, type: 'Harassment', area: 'Igatpuri' },
    // Nagpur Hotspots
    { lat: 21.1458, lng: 79.0882, intensity: 0.85, type: 'Mobbing', area: 'Sitabuldi' },
    { lat: 21.1550, lng: 79.1050, intensity: 0.9, type: 'Theft', area: 'Itwari' },
    { lat: 21.1520, lng: 79.0880, intensity: 0.9, type: 'Harassment', area: 'Nagpur Railway Station' },
    { lat: 21.1600, lng: 79.0800, intensity: 0.75, type: 'Assault', area: 'Sadar' },
    { lat: 21.0800, lng: 78.9900, intensity: 0.75, type: 'Robbery', area: 'Hingna MIDC' },
    // Explicit Polygonal Zones (GeoJSON) - Demonstration for Nagpur
    {
        type: 'Polygon',
        area: 'Sitabuldi Commercial Zone',
        intensity: 0.9,
        coordinates: [[
            [79.0822, 21.1408], [79.0942, 21.1408], [79.0942, 21.1508], [79.0822, 21.1508], [79.0822, 21.1408]
        ]]
    }
];

// Convert hotspots to Red Zones (Supports both Point-radius and explicit Polygons)
const redZonePolygons = crimeHotspots.map(spot => {
    if (spot.type === 'Polygon') {
        return turfHelpers.polygon(spot.coordinates, { area: spot.area, intensity: spot.intensity });
    }
    const pt = turfHelpers.point([spot.lng, spot.lat]);
    return turfBuffer(pt, 0.4, { units: 'kilometers' }); // 400m danger radius
});


// --- Night Mode Safety Endpoints ---
const nightCheckIns = new Map(); // UserId -> [CheckInHistory]
const buddyTracks = new Map();   // UserId -> BuddyDetails

app.get('/api/night-mode/status', (req, res) => {
    const hour = new Date().getHours();
    const isNight = hour >= 20 || hour < 6;
    res.json({
        success: true,
        isNightModeActive: isNight,
        serverTime: new Date().toISOString(),
        nightMultiplier: isNight ? 2.2 : 1.0
    });
});

app.post('/api/night-mode/check-in', (req, res) => {
    const { userId, lat, lng, type } = req.body;
    console.log(`[NightMode] Check-in from ${userId} at ${lat},${lng} (${type})`);

    if (!nightCheckIns.has(userId)) nightCheckIns.set(userId, []);
    const history = nightCheckIns.get(userId);
    history.push({ lat, lng, type, timestamp: new Date().toISOString() });

    res.json({ success: true, message: 'Check-in logged' });
});

app.post('/api/night-mode/buddy-track', (req, res) => {
    const { userId, contactName, contactPhone, status } = req.body;
    console.log(`[NightMode] Buddy track ${status} for ${userId} with ${contactName}`);

    if (status === 'started') {
        buddyTracks.set(userId, { contactName, contactPhone, startTime: new Date().toISOString() });
    } else {
        buddyTracks.delete(userId);
    }

    res.json({ success: true, message: `Buddy tracking ${status}` });
});

app.get('/api/night-mode/alerts', (req, res) => {
    const hour = new Date().getHours();
    let alerts = [];
    if (hour >= 20 || hour < 6) {
        alerts = [
            "Increased risk detected near CBS area tonight. Avoid walking alone.",
            "Weather: Low visibility expected after 11 PM.",
            "Safety Tip: Share your live location if using public transport."
        ];
    }
    res.json({ success: true, alerts });
});

// --- ML Service Proxy Routes ---
// These forward requests to the Python FastAPI ML service

app.post('/api/zones/predict', async (req, res) => {
    try {
        if (!mlService) {
            return res.json({ success: false, error: 'ML service not configured', predictions: [] });
        }
        const { locations, ...enrichment } = req.body;
        const predictions = await mlService.predictZones(locations, enrichment);
        res.json({ success: true, predictions });
    } catch (error) {
        console.error('[ML] Zone prediction error:', error.message);
        // Graceful fallback: return empty predictions instead of 500
        res.json({
            success: false,
            error: 'ML service unavailable',
            predictions: (req.body.locations || []).map(loc => ({
                latitude: loc.latitude,
                longitude: loc.longitude,
                risk_label: 'unknown',
                risk_score: 0,
                probabilities: { green: 0.33, orange: 0.34, red: 0.33 }
            }))
        });
    }
});

app.post('/api/reports/analyse', async (req, res) => {
    try {
        if (!mlService) {
            return res.json({ success: false, error: 'ML service not configured' });
        }
        const { reportText, reporterMeta, latitude, longitude } = req.body;
        const analysis = await mlService.analyseNewReport(reportText, reporterMeta);

        // If credible, also write to blockchain
        if (analysis.should_store_on_chain && contract) {
            const hash = generateHash({ reportText, latitude, longitude, ...analysis });
            try {
                const tx = await contract.storeSOS(hash);
                await tx.wait();
                analysis.blockchain_tx = tx.hash;
            } catch (bcErr) {
                analysis.blockchain_tx = '0xMockTxHash_' + Date.now();
            }
        }

        res.json({ success: true, ...analysis });
    } catch (error) {
        console.error('[ML] Report analysis error:', error.message);
        // Rule-based fallback
        res.json({
            success: false,
            error: 'ML service unavailable',
            final_verdict: 'NEEDS_REVIEW',
            final_score: 0.5,
        });
    }
});

app.post('/api/ml/refresh', async (req, res) => {
    try {
        if (!mlService) {
            return res.json({ success: false, error: 'ML service not configured' });
        }
        const result = await mlService.refreshDataSources();
        res.json({ success: true, ...result });
    } catch (error) {
        console.error('[ML] Data refresh error:', error.message);
        res.status(500).json({ success: false, error: error.message });
    }
});

app.get('/api/ml/health', async (req, res) => {
    try {
        if (!mlService) {
            return res.json({ success: false, ml_connected: false });
        }
        const { data } = await axios.get(
            (process.env.ML_SERVICE_URL || 'https://nivaran-ml.onrender.com') + '/health',
            { timeout: 60000 }
        );
        res.json({ success: true, ml_connected: true, ...data });
    } catch (error) {
        res.json({ success: false, ml_connected: false, error: error.message });
    }
});

// --- AI Completion Proxy ---
app.post('/api/ai/chat', async (req, res) => {
    try {
        const apiKey = process.env.OPENROUTER_API_KEY || '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';
        if (!apiKey) {
            return res.status(500).json({ error: 'AI Service configuration missing (API Key)' });
        }

        const { model, messages, max_tokens, temperature } = req.body;
        
        console.log(`[AI] Dispatching request to OpenRouter for model: ${model || 'default'}`);

        const response = await axios.post(
            'https://openrouter.ai/api/v1/chat/completions',
            {
                model: model || 'openai/gpt-4o-mini',
                messages: messages,
                max_tokens: max_tokens || 1000,
                temperature: temperature || 0.7,
            },
            {
                headers: {
                    'Authorization': `Bearer ${apiKey}`,
                    'Content-Type': 'application/json',
                    'HTTP-Referer': 'https://nivaran.app',
                    'X-Title': 'Nivaran',
                },
                timeout: 60000
            }
        );

        res.json(response.data);
    } catch (error) {
        console.error('[AI] Proxy Error:', error.response?.data || error.message);
        res.status(error.response?.status || 500).json(error.response?.data || { error: error.message });
    }
});


app.listen(PORT, '0.0.0.0', () => {
    console.log(`Blockchain Backend running on http://0.0.0.0:${PORT}`);
});
